//
//  Process+Extensions.swift
//  WhiskyKit
//
//  This file is part of Whisky.
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//

import Foundation
import os.log

/// Output events from a running process
/// - Note: Uses Int32 termination status instead of Process references for Sendable conformance
public enum ProcessOutput: Hashable, Sendable {
    /// Process has started
    case started
    /// Message from stdout
    case message(String)
    /// Message from stderr
    case error(String)
    /// Process terminated with exit code
    case terminated(Int32)
}

public extension Process {
    /// Run the process returning a stream output
    func runStream(name: String, fileHandle: FileHandle?) throws -> AsyncStream<ProcessOutput> {
        let stream = makeStream(name: name, fileHandle: fileHandle)
        self.logProcessInfo(name: name)
        fileHandle?.writeInfo(for: self)
        try run()
        return stream
    }

    private func makeStream(name: String, fileHandle: FileHandle?) -> AsyncStream<ProcessOutput> {
        let pipe = Pipe()
        let errorPipe = Pipe()
        let outputLock = NSLock()
        standardOutput = pipe
        standardError = errorPipe

        return AsyncStream<ProcessOutput> { continuation in
            continuation.yield(.started)

            continuation.onTermination = self.makeStreamTerminationCallback()

            pipe.fileHandleForReading.readabilityHandler = self.makeReadabilityHandler(
                kind: .stdout,
                outputLock: outputLock,
                continuation: continuation,
                fileHandle: fileHandle
            )

            errorPipe.fileHandleForReading.readabilityHandler = self.makeReadabilityHandler(
                kind: .stderr,
                outputLock: outputLock,
                continuation: continuation,
                fileHandle: fileHandle
            )

            terminationHandler = self.makeProcessTerminationHandler(
                name: name,
                pipe: pipe,
                errorPipe: errorPipe,
                outputLock: outputLock,
                continuation: continuation,
                fileHandle: fileHandle
            )
        }
    }

    private enum StreamKind {
        case stdout
        case stderr
    }

    private struct TerminationContext {
        let name: String
        let pipe: Pipe
        let errorPipe: Pipe
        let outputLock: NSLock
        let continuation: AsyncStream<ProcessOutput>.Continuation
        let fileHandle: FileHandle?
    }

    private func makeStreamTerminationCallback()
        -> @Sendable (AsyncStream<ProcessOutput>.Continuation.Termination) -> Void {
        { termination in
            if case .cancelled = termination, self.isRunning {
                self.terminate()
            }
        }
    }

    private func makeReadabilityHandler(
        kind: StreamKind,
        outputLock: NSLock,
        continuation: AsyncStream<ProcessOutput>.Continuation,
        fileHandle: FileHandle?
    ) -> @Sendable (FileHandle) -> Void {
        { pipeHandle in
            guard let line = pipeHandle.nextLine() else { return }
            outputLock.lock()
            defer { outputLock.unlock() }
            self.emit(line: line, kind: kind, continuation: continuation, fileHandle: fileHandle)
        }
    }

    private func makeProcessTerminationHandler(
        name: String,
        pipe: Pipe,
        errorPipe: Pipe,
        outputLock: NSLock,
        continuation: AsyncStream<ProcessOutput>.Continuation,
        fileHandle: FileHandle?
    ) -> @Sendable (Process) -> Void {
        { process in
            do {
                // Stop readability handlers first to avoid racing / double-consuming output.
                pipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil

                outputLock.lock()
                defer { outputLock.unlock() }

                try self.drainToLog(
                    pipe.fileHandleForReading,
                    kind: .stdout,
                    continuation: continuation,
                    fileHandle: fileHandle
                )
                try self.drainToLog(
                    errorPipe.fileHandleForReading,
                    kind: .stderr,
                    continuation: continuation,
                    fileHandle: fileHandle
                )
                try fileHandle?.closeWineLog()
            } catch {
                Logger.wineKit.error("Error while clearing data: \(error)")
            }

            process.logTermination(name: name)
            continuation.yield(.terminated(process.terminationStatus))
            continuation.finish()
        }
    }

    private func drainToLog(
        _ handle: FileHandle,
        kind: StreamKind,
        continuation: AsyncStream<ProcessOutput>.Continuation,
        fileHandle: FileHandle?
    ) throws {
        // `readabilityHandler` may stop firing before the last bytes are consumed.
        guard let remaining = try handle.readToEnd(),
              let text = String(data: remaining, encoding: .utf8),
              !text.isEmpty
        else { return }
        emit(line: text, kind: kind, continuation: continuation, fileHandle: fileHandle)
    }

    private func emit(
        line: String,
        kind: StreamKind,
        continuation: AsyncStream<ProcessOutput>.Continuation,
        fileHandle: FileHandle?
    ) {
        switch kind {
        case .stdout:
            continuation.yield(.message(line))
            guard !line.isEmpty else { return }
            Logger.wineKit.info("\(line, privacy: .public)")
        case .stderr:
            continuation.yield(.error(line))
            guard !line.isEmpty else { return }
            Logger.wineKit.warning("\(line, privacy: .public)")
        }
        fileHandle?.writeWineLog(line: line)
    }

    private func logTermination(name: String) {
        if terminationStatus == 0 {
            Logger.wineKit.info(
                "Terminated \(name) with status code '\(self.terminationStatus, privacy: .public)'"
            )
        } else {
            Logger.wineKit.warning(
                "Terminated \(name) with status code '\(self.terminationStatus, privacy: .public)'"
            )
        }
    }

    private func logProcessInfo(name: String) {
        Logger.wineKit.info("Running process \(name)")

        if let arguments {
            Logger.wineKit.info("Arguments: `\(arguments.joined(separator: " "))`")
        }
        if let executableURL {
            Logger.wineKit.info("Executable: `\(executableURL.path(percentEncoded: false))`")
        }
        if let directory = currentDirectoryURL {
            Logger.wineKit.info("Directory: `\(directory.path(percentEncoded: false))`")
        }
        if let environment {
            Logger.wineKit.info("Environment: \(environment)")
        }
    }
}

extension FileHandle {
    func nextLine() -> String? {
        guard let line = String(data: availableData, encoding: .utf8) else { return nil }
        if !line.isEmpty {
            return line
        } else {
            return nil
        }
    }
}
