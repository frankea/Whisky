//
//  WineLogCapRegistry.swift
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
@preconcurrency import ObjectiveC
import os.log

/// How a Whisky log file is kept under its size cap.
///
/// A log keeps its head, the launch header Whisky writes first plus the early
/// output after it, and its newest output. When a write would take the file
/// past ``maxBytes``, the file is cut back to the head, the truncation marker
/// is written after it, and then the last ``tailBytes`` of output, so the log
/// always ends with what the program wrote last: a crash at the end of a long,
/// noisy session is still at the end of its log, where crash classification
/// reads.
struct WineLogLimits: Sendable {
    /// The most a log file may hold.
    let maxBytes: Int64
    /// How much of the start of the log survives a truncation.
    let headBytes: Int
    /// How much of the newest output a truncation keeps after the marker.
    let tailBytes: Int

    /// The limits every Whisky log is written with.
    static let standard = WineLogLimits(
        maxBytes: Wine.maxLogFileBytes,
        headBytes: Wine.logHeadBytes,
        tailBytes: Wine.logTailBytes
    )
}

/// Enforces ``WineLogLimits`` for every open log file handle.
///
/// The state is keyed by handle and guarded by one lock, so stdout and stderr
/// writers for the same log never interleave a truncation with a write.
final class WineLogCapRegistry: @unchecked Sendable {
    static let shared = WineLogCapRegistry()

    private struct State {
        /// The size of the file, which is also where the next write lands.
        var bytesWritten: Int64
        /// The first bytes written, kept until a truncation seals the head.
        var head = Data()
        /// Where the head ends, once known.
        var headLength: Int64?
        /// The newest output, kept only while the file is within ``WineLogLimits/tailBytes``
        /// of its cap, so a truncation can carry it over.
        var recent = Data()
        /// How many times the file has been truncated, written after the marker.
        var truncations = 0
        /// Set when the file could not be truncated; further output is discarded.
        var isDisabled = false
    }

    private let lock = NSLock()
    private var states: [ObjectIdentifier: State] = [:]
    private nonisolated(unsafe) static var deinitObserverKey: UInt8 = 0

    private final class DeinitObserver {
        let onDeinit: () -> Void
        init(onDeinit: @escaping () -> Void) {
            self.onDeinit = onDeinit
        }

        deinit { onDeinit() }
    }

    private init() {}

    func write(_ data: Data, to handle: FileHandle, limits: WineLogLimits = .standard) {
        let key = ObjectIdentifier(handle)
        attachDeinitObserverIfNeeded(to: handle, key: key)

        lock.lock()
        defer { lock.unlock() }

        var state = states[key] ?? makeState(for: handle, limits: limits)
        defer { states[key] = state }
        guard !state.isDisabled, !data.isEmpty else { return }

        if state.bytesWritten + Int64(data.count) <= limits.maxBytes {
            writeData(data, to: handle)
            remember(data, in: &state, limits: limits)
            state.bytesWritten += Int64(data.count)
        } else {
            truncate(appending: data, state: &state, handle: handle, limits: limits)
        }
    }

    func removeState(for handle: FileHandle) {
        removeState(forKey: ObjectIdentifier(handle))
    }

    private func removeState(forKey key: ObjectIdentifier) {
        lock.lock()
        defer { lock.unlock() }
        states.removeValue(forKey: key)
    }

    private func makeState(for handle: FileHandle, limits: WineLogLimits) -> State {
        guard let size = currentSizeBytes(for: handle) else {
            // Nothing can be measured or cut on this handle, so nothing is written to it.
            var state = State(bytesWritten: limits.maxBytes)
            state.isDisabled = true
            return state
        }
        var state = State(bytesWritten: size)
        if size > 0 {
            // Written before this handle was tracked, so its bytes were never
            // seen; the head is whatever of it fits.
            state.headLength = min(size, Int64(limits.headBytes))
        }
        return state
    }

    /// Records what a write that fit added: the head while it is still being
    /// filled, and the newest output once the file nears its cap.
    private func remember(_ data: Data, in state: inout State, limits: WineLogLimits) {
        if state.headLength == nil, state.head.count < limits.headBytes {
            state.head.append(data.prefix(limits.headBytes - state.head.count))
        }
        let end = state.bytesWritten + Int64(data.count)
        guard end > limits.maxBytes - Int64(limits.tailBytes) else { return }
        state.recent.append(data)
        // Trimmed in batches, not on every write, so a stream of small writes
        // doesn't copy the whole window each time.
        if state.recent.count > limits.tailBytes * 2 {
            state.recent = Data(state.recent.suffix(limits.tailBytes))
        }
    }

    /// Cuts the file back to its head, then writes the marker and the newest
    /// output, `data` included.
    private func truncate(appending data: Data, state: inout State, handle: FileHandle, limits: WineLogLimits) {
        let headLength = state.headLength ?? Self.sealedHeadLength(of: state.head)
        state.headLength = headLength
        state.head = Data()

        let markerData = Data((Wine.logTruncationMarker + Wine.logTruncationCountLine(state.truncations + 1)).utf8)
        let room = max(0, limits.maxBytes - headLength)
        let marker = markerData.prefix(Int(min(room, Int64(markerData.count))))
        let tailRoom = Int(min(room - Int64(marker.count), Int64(limits.tailBytes)))
        let tail = Self.lineAlignedSuffix(of: state.recent + data, maxCount: tailRoom)

        do {
            try handle.truncate(atOffset: UInt64(headLength))
        } catch {
            // Without a truncation the cap can't be kept, so stop writing.
            Logger.wineKit.info("Failed to truncate log; discarding further output: \(error)")
            state.isDisabled = true
            return
        }
        state.truncations += 1
        // The marker goes first: a reader that finds new output past it also finds its new count.
        writeData(marker, to: handle)
        writeData(tail, to: handle)
        state.bytesWritten = headLength + Int64(marker.count) + Int64(tail.count)
        state.recent = state.bytesWritten > limits.maxBytes - Int64(limits.tailBytes) ? tail : Data()
    }

    /// The length of the head a truncation keeps: what was captured of it, up
    /// to its last full line.
    static func sealedHeadLength(of head: Data) -> Int64 {
        guard let lastNewline = head.lastIndex(of: UInt8(ascii: "\n")) else {
            return Int64(head.count)
        }
        return Int64(head.distance(from: head.startIndex, to: lastNewline) + 1)
    }

    /// The last `maxCount` bytes of `data`, starting at a line when the cut
    /// fell inside one and a later line exists.
    static func lineAlignedSuffix(of data: Data, maxCount: Int) -> Data {
        guard maxCount > 0 else { return Data() }
        guard data.count > maxCount else { return data }
        let suffix = data.suffix(maxCount)
        if let newline = suffix.firstIndex(of: UInt8(ascii: "\n")), newline < suffix.index(before: suffix.endIndex) {
            return Data(suffix[suffix.index(after: newline)...])
        }
        return Data(suffix)
    }

    private func attachDeinitObserverIfNeeded(to handle: FileHandle, key: ObjectIdentifier) {
        // Ensure state is cleared even if `closeWineLog()` isn't called (e.g., early returns / errors).
        if objc_getAssociatedObject(handle, &Self.deinitObserverKey) != nil { return }
        let observer = DeinitObserver { [weak self] in
            self?.removeState(forKey: key)
        }
        objc_setAssociatedObject(handle, &Self.deinitObserverKey, observer, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    private func currentSizeBytes(for handle: FileHandle) -> Int64? {
        do {
            // Ensures subsequent writes remain append-only.
            let offset = try handle.seekToEnd()
            return Int64(offset)
        } catch {
            Logger.wineKit.info("Failed to determine current file size; seekToEnd() threw: \(error)")
            // Fall back to `fstat` (doesn't require seeking) to avoid unnecessarily disabling logging.
            var fileStat = stat()
            if fstat(handle.fileDescriptor, &fileStat) == 0 {
                return Int64(fileStat.st_size)
            }

            return nil
        }
    }

    private func writeData(_ data: Data, to handle: FileHandle) {
        guard !data.isEmpty else { return }
        do {
            try handle.write(contentsOf: data)
        } catch {
            Logger.wineKit.info("Failed to write log data: \(error)")
        }
    }
}

extension Wine {
    /// What the line after ``logTruncationMarker`` starts with, before the log's truncation count.
    static let logTruncationCountPrefix = "[Whisky] Truncation count: "

    /// The line written after ``logTruncationMarker`` by a log's `count`th truncation.
    ///
    /// Each truncation rewrites everything after the log's head, and the log may grow back
    /// past where a reader had got to before it reads again. The count tells a reader
    /// following the log that this happened (``WineLogFollower``).
    static func logTruncationCountLine(_ count: Int) -> String {
        "\(logTruncationCountPrefix)\(count)\n"
    }
}
