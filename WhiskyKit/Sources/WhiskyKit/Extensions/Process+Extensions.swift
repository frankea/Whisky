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
    /// Runs the process, returning a stream of its output.
    ///
    /// The stream finishes as soon as the process exits, with whatever output it
    /// had written by then. Anything the process started that inherited its
    /// stdout and stderr (for `wine`, the program and the bottle's services)
    /// keeps them open, and their output goes on into `fileHandle`, which is
    /// closed once the last of them has closed it.
    ///
    /// - Parameters:
    ///   - name: The name the process is logged under.
    ///   - fileHandle: The log the output is written to, closed once the output has closed.
    ///   - completion: Completed once the output has closed.
    ///   - lateOutput: Receives the output that arrives after the process exited,
    ///     and is finished once the output has closed.
    /// - Returns: The output of the process, ending with ``ProcessOutput/terminated(_:)``.
    /// - Throws: An error if the process cannot be started.
    func runStream(
        name: String,
        fileHandle: FileHandle?,
        completion: ProcessOutputCompletion? = nil,
        lateOutput: AsyncStream<ProcessOutput>.Continuation? = nil
    ) throws -> AsyncStream<ProcessOutput> {
        let (stream, continuation) = AsyncStream.makeStream(of: ProcessOutput.self)
        let reader = ProcessOutputReader(
            continuation: continuation,
            logHandle: fileHandle,
            lateOutput: lateOutput,
            completion: completion
        )
        reader.attach(to: self)
        continuation.yield(.started)
        continuation.onTermination = makeStreamTerminationCallback()
        terminationHandler = { process in
            process.logTermination(name: name)
            reader.processDidExit(status: process.terminationStatus)
        }

        logProcessInfo(name: name)
        fileHandle?.writeInfo(for: self)
        do {
            try run()
        } catch {
            reader.cancel()
            throw error
        }
        reader.start()
        return stream
    }

    private func makeStreamTerminationCallback()
        -> @Sendable (AsyncStream<ProcessOutput>.Continuation.Termination) -> Void {
        { termination in
            if case .cancelled = termination, self.isRunning {
                self.terminate()
            }
        }
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
