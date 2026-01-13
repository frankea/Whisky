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
            continuation.onTermination = { termination in
                switch termination {
                case .finished:
                    break
                case .cancelled:
                    guard self.isRunning else { return }
                    self.terminate()
                @unknown default:
                    break
                }
            }

            continuation.yield(.started)

            pipe.fileHandleForReading.readabilityHandler = { pipe in
                guard let line = pipe.nextLine() else { return }
                outputLock.lock()
                defer { outputLock.unlock() }
                continuation.yield(.message(line))
                guard !line.isEmpty else { return }
                Logger.wineKit.info("\(line, privacy: .public)")
                fileHandle?.writeWineLog(line: line)
            }

            errorPipe.fileHandleForReading.readabilityHandler = { pipe in
                guard let line = pipe.nextLine() else { return }
                outputLock.lock()
                defer { outputLock.unlock() }
                continuation.yield(.error(line))
                guard !line.isEmpty else { return }
                Logger.wineKit.warning("\(line, privacy: .public)")
                fileHandle?.writeWineLog(line: line)
            }

            terminationHandler = { (process: Process) in
                do {
                    // Stop readability handlers first to avoid racing / double-consuming output.
                    pipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil

                    outputLock.lock()
                    defer { outputLock.unlock() }

                    // Drain any remaining output. `readabilityHandler` may stop firing before the last bytes are consumed.
                    if let remainingOut = try pipe.fileHandleForReading.readToEnd(),
                       let out = String(data: remainingOut, encoding: .utf8),
                       !out.isEmpty {
                        continuation.yield(.message(out))
                        Logger.wineKit.info("\(out, privacy: .public)")
                        fileHandle?.writeWineLog(line: out)
                    }

                    if let remainingErr = try errorPipe.fileHandleForReading.readToEnd(),
                       let err = String(data: remainingErr, encoding: .utf8),
                       !err.isEmpty {
                        continuation.yield(.error(err))
                        Logger.wineKit.warning("\(err, privacy: .public)")
                        fileHandle?.writeWineLog(line: err)
                    }
                    try fileHandle?.closeWineLog()
                } catch {
                    Logger.wineKit.error("Error while clearing data: \(error)")
                }

                process.logTermination(name: name)
                continuation.yield(.terminated(process.terminationStatus))
                continuation.finish()
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
