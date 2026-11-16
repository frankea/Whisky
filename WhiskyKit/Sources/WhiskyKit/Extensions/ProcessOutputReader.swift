//
//  ProcessOutputReader.swift
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

import Darwin
import Foundation
import os.log

/// Signals that every process writing to a run's output has closed it.
///
/// A Wine launcher exits long before its output ends: everything it starts
/// (the program, `explorer.exe`, the bottle's services) inherits its stdout
/// and stderr and writes to them until the bottle's session ends. The launch
/// returns when the launcher exits; this completes once the last of those
/// processes has closed the output too, when the run's log is complete.
public final class ProcessOutputCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    /// Whether the output has closed.
    public var isComplete: Bool {
        lock.withLock { completed }
    }

    /// Returns once the output has closed.
    public func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if completed {
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    func complete() {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        let pending = waiters
        waiters = []
        lock.unlock()
        pending.forEach { $0.resume() }
    }
}

/// Reads a process's stdout and stderr pipes into its output stream and log.
///
/// Two moments are kept apart. When the process exits, whatever its pipes
/// already hold is taken without waiting for more, and the stream gets
/// ``ProcessOutput/terminated(_:)`` and finishes, so the caller moves on as
/// soon as the process is gone. The pipes stay open as long as anything that
/// inherited them does, though, so reading carries on in the background,
/// appending to the log, until both reach end of file; only then is the log
/// closed and the completion signalled.
///
/// Every read is non-blocking and happens under one lock, so a read and the
/// exit drain never race over the same bytes, and nothing waits on a pipe
/// while holding it. A pipe's readability handler is removed when the pipe
/// reaches end of file, as it would otherwise fire on that condition without
/// end (whisky-app/whisky#917). Handlers are only ever installed or removed
/// outside the lock, so changing one never waits on a handler that is itself
/// waiting for the lock.
final class ProcessOutputReader: @unchecked Sendable {
    enum Source: Int, CaseIterable {
        case stdout
        case stderr
    }

    /// The reading state of one pipe, guarded by the lock.
    private struct Channel {
        var decoder = UTF8ChunkDecoder()
        var isClosed = false
    }

    /// The most the exit drain takes from one pipe. What a pipe can buffer is
    /// far less; the limit only stops a child that never stops writing from
    /// holding the launch up.
    static let exitDrainLimit = 1_024 * 1_024

    private let lock = NSLock()
    /// The stdout and stderr pipes, by ``Source``.
    private let pipes = [Pipe(), Pipe()]
    private var channels = [Channel(), Channel()]
    private let continuation: AsyncStream<ProcessOutput>.Continuation
    private let logHandle: FileHandle?
    private let lateOutput: AsyncStream<ProcessOutput>.Continuation?
    private let completion: ProcessOutputCompletion?
    private var processExited = false
    private var isFinished = false
    /// Read ends whose handler is to be removed once the lock is released.
    private var stoppedHandles: [FileHandle] = []

    /// - Parameters:
    ///   - continuation: The run's output stream, finished when the process exits.
    ///   - logHandle: The run's log, closed once the output has closed.
    ///   - lateOutput: Receives what arrives after the process exited, and is
    ///     finished once the output has closed.
    ///   - completion: Completed once the output has closed.
    init(
        continuation: AsyncStream<ProcessOutput>.Continuation,
        logHandle: FileHandle?,
        lateOutput: AsyncStream<ProcessOutput>.Continuation?,
        completion: ProcessOutputCompletion?
    ) {
        self.continuation = continuation
        self.logHandle = logHandle
        self.lateOutput = lateOutput
        self.completion = completion
        for pipe in pipes {
            // Only the read ends, which this process alone holds; the write
            // ends the children inherit keep blocking writes.
            let descriptor = pipe.fileHandleForReading.fileDescriptor
            _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        }
    }

    /// Makes the pipes the process's stdout and stderr.
    func attach(to process: Process) {
        process.standardOutput = pipes[Source.stdout.rawValue]
        process.standardError = pipes[Source.stderr.rawValue]
    }

    /// Starts reading, once the process is running.
    func start() {
        lock.lock()
        let open = Source.allCases.filter { !channels[$0.rawValue].isClosed }
        lock.unlock()
        for source in open {
            // Retains the reader until the pipe reaches end of file, when the
            // handler is removed. A pipe that closed in the meantime has its
            // handler removed on its first call.
            pipes[source.rawValue].fileHandleForReading.readabilityHandler = { _ in
                self.readAvailable(from: source)
            }
        }
    }

    /// Takes what the pipes hold now, then reports the exit and finishes the stream.
    func processDidExit(status: Int32) {
        lock.lock()
        for source in Source.allCases {
            drainOnExit(source)
        }
        continuation.yield(.terminated(status))
        continuation.finish()
        processExited = true
        finishIfDone()
        lock.unlock()
        removeStoppedHandlers()
    }

    /// Gives up on a process that never started.
    func cancel() {
        lock.lock()
        processExited = true
        for index in channels.indices {
            channels[index].isClosed = true
        }
        continuation.finish()
        finishIfDone()
        lock.unlock()
    }

    private func readAvailable(from source: Source) {
        lock.lock()
        let handle = pipes[source.rawValue].fileHandleForReading
        if channels[source.rawValue].isClosed {
            stoppedHandles.append(handle)
        } else {
            switch handle.readChunk() {
            case let .data(data):
                emit(channels[source.rawValue].decoder.decode(data), from: source)
            case .endOfFile:
                close(source)
            case .wouldBlock:
                // Woken with nothing to read, as after the exit drain took it.
                break
            }
        }
        lock.unlock()
        removeStoppedHandlers()
    }

    private func removeStoppedHandlers() {
        lock.lock()
        let handles = stoppedHandles
        stoppedHandles = []
        lock.unlock()
        for handle in handles {
            handle.readabilityHandler = nil
        }
    }

    private func drainOnExit(_ source: Source) {
        var taken = 0
        while !channels[source.rawValue].isClosed, taken < Self.exitDrainLimit {
            switch pipes[source.rawValue].fileHandleForReading.readChunk() {
            case let .data(data):
                taken += data.count
                emit(channels[source.rawValue].decoder.decode(data), from: source)
            case .endOfFile:
                close(source)
            case .wouldBlock:
                return
            }
        }
    }

    private func close(_ source: Source) {
        channels[source.rawValue].isClosed = true
        stoppedHandles.append(pipes[source.rawValue].fileHandleForReading)
        emit(channels[source.rawValue].decoder.flush(), from: source)
        finishIfDone()
    }

    private func emit(_ text: String, from source: Source) {
        guard !text.isEmpty else { return }
        let output: ProcessOutput = source == .stdout ? .message(text) : .error(text)
        if processExited {
            // The process is gone; this is what it started writing on its own,
            // which the log keeps and the system log is spared.
            lateOutput?.yield(output)
        } else {
            continuation.yield(output)
            switch source {
            case .stdout:
                Logger.wineKit.info("\(text, privacy: .public)")
            case .stderr:
                Logger.wineKit.warning("\(text, privacy: .public)")
            }
        }
        logHandle?.writeWineLog(line: text)
    }

    private func finishIfDone() {
        guard processExited, !isFinished, channels.allSatisfy(\.isClosed) else { return }
        isFinished = true
        do {
            try logHandle?.closeWineLog()
        } catch {
            Logger.wineKit.error("Failed to close the log: \(error)")
        }
        lateOutput?.finish()
        completion?.complete()
    }
}

extension FileHandle {
    /// The outcome of one non-blocking read from a pipe.
    enum ChunkRead: Equatable {
        /// Bytes that were waiting.
        case data(Data)
        /// Every writer has closed the pipe; nothing more will come.
        case endOfFile
        /// Nothing to read right now.
        case wouldBlock
    }

    /// Reads what is available, without waiting for more, from a descriptor
    /// in non-blocking mode. A read error other than an interruption or an
    /// empty pipe reads as end of file, so a reader stops rather than spins.
    func readChunk(maxCount: Int = 64 * 1_024) -> ChunkRead {
        var buffer = [UInt8](repeating: 0, count: maxCount)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(fileDescriptor, $0.baseAddress, maxCount) }
            if count > 0 {
                return .data(Data(buffer.prefix(count)))
            }
            if count == 0 {
                return .endOfFile
            }
            switch errno {
            case EINTR:
                continue
            case EAGAIN:
                return .wouldBlock
            default:
                return .endOfFile
            }
        }
    }
}

/// Decodes UTF-8 that arrives in chunks of arbitrary size.
///
/// A multi-byte character split across two reads is held back until the rest
/// of it arrives, and bytes that are not UTF-8 at all become replacement
/// characters, so no chunk of output is ever dropped for its encoding.
struct UTF8ChunkDecoder {
    private var pending = Data()

    /// Decodes `data` after whatever an earlier chunk left unfinished.
    mutating func decode(_ data: Data) -> String {
        var bytes = pending
        bytes.append(data)
        let length = Self.completeLength(of: bytes)
        pending = Data(bytes.dropFirst(length))
        return Self.lossyString(bytes.prefix(length))
    }

    /// Decodes what is still held back, at the end of the output.
    mutating func flush() -> String {
        defer { pending = Data() }
        return Self.lossyString(pending)
    }

    /// Decodes bytes, replacing what isn't UTF-8 rather than failing: output
    /// is never dropped for a stray byte.
    private static func lossyString(_ bytes: Data) -> String {
        // swiftlint:disable:next optional_data_string_conversion
        String(decoding: bytes, as: UTF8.self)
    }

    /// The length of `bytes` without the character its last bytes leave unfinished.
    static func completeLength(of bytes: Data) -> Int {
        var index = bytes.endIndex
        // A character is at most four bytes, so its lead byte is among the last four.
        while index > bytes.startIndex, bytes.endIndex - index < 4 {
            index -= 1
            let byte = bytes[index]
            if byte & 0xC0 == 0x80 {
                continue
            }
            let length = byte >= 0xF0 ? 4 : byte >= 0xE0 ? 3 : byte >= 0xC0 ? 2 : 1
            let isUnfinished = bytes.endIndex - index < length
            return isUnfinished ? bytes.distance(from: bytes.startIndex, to: index) : bytes.count
        }
        return bytes.count
    }
}
