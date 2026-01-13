//
//  FileHandle+Extensions.swift
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
@preconcurrency import ObjectiveC
import Darwin
import os.log
import SemanticVersion

private final class WineLogCapRegistry: @unchecked Sendable {
    static let shared = WineLogCapRegistry()

    private struct State {
        var bytesWritten: Int64
        var didWriteTruncationMarker: Bool
    }

    private let lock = NSLock()
    private var states: [ObjectIdentifier: State] = [:]
    nonisolated(unsafe) private static var deinitObserverKey: UInt8 = 0

    private final class DeinitObserver {
        let onDeinit: () -> Void
        init(onDeinit: @escaping () -> Void) { self.onDeinit = onDeinit }
        deinit { onDeinit() }
    }

    private init() {}

    func write(_ data: Data, to handle: FileHandle) {
        let key = ObjectIdentifier(handle)
        attachDeinitObserverIfNeeded(to: handle, key: key)

        lock.lock()
        defer { lock.unlock() }

        var state = states[key] ?? State(
            bytesWritten: currentSizeBytes(for: handle),
            didWriteTruncationMarker: false
        )

        // Once truncation starts, discard further output without buffering.
        if state.didWriteTruncationMarker {
            // `state` isn't mutated in this branch, so writing it back to `states` would be redundant.
            return
        }

        let maxBytes = Wine.maxLogFileBytes
        let markerData = Wine.logTruncationMarker.data(using: .utf8) ?? Data()
        let dataCap = max(0, maxBytes - Int64(markerData.count))

        if state.bytesWritten < dataCap {
            let remainingForData = dataCap - state.bytesWritten
            if Int64(data.count) <= remainingForData {
                writeData(data, to: handle)
                state.bytesWritten += Int64(data.count)
            } else {
                if remainingForData > 0 {
                    let prefix = data.prefix(Int(remainingForData))
                    writeData(prefix, to: handle)
                    state.bytesWritten += Int64(prefix.count)
                }
                writeTruncationMarkerIfPossible(markerData, maxBytes: maxBytes, state: &state, handle: handle)
            }
        } else {
            // We've hit the data budget; begin truncation and append the marker once.
            writeTruncationMarkerIfPossible(markerData, maxBytes: maxBytes, state: &state, handle: handle)
        }

        states[key] = state
    }

    func removeState(for handle: FileHandle) {
        removeState(forKey: ObjectIdentifier(handle))
    }

    private func removeState(forKey key: ObjectIdentifier) {
        lock.lock()
        defer { lock.unlock() }
        states.removeValue(forKey: key)
    }

    private func attachDeinitObserverIfNeeded(to handle: FileHandle, key: ObjectIdentifier) {
        // Ensure state is cleared even if `closeWineLog()` isn't called (e.g., early returns / errors).
        if objc_getAssociatedObject(handle, &Self.deinitObserverKey) != nil { return }
        let observer = DeinitObserver { [weak self] in
            self?.removeState(forKey: key)
        }
        objc_setAssociatedObject(handle, &Self.deinitObserverKey, observer, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    private func currentSizeBytes(for handle: FileHandle) -> Int64 {
        do {
            // Ensures subsequent writes remain append-only.
            let offset = try handle.seekToEnd()
            return Int64(offset)
        } catch {
            Logger.wineKit.info("Failed to determine current file size; seekToEnd() threw: \(error)")
            // Fall back to `fstat` (doesn't require seeking) to avoid unnecessarily disabling logging.
            var st = stat()
            if fstat(handle.fileDescriptor, &st) == 0 {
                return Int64(st.st_size)
            }

            // If we still can't determine the current size, assume the cap is already reached to avoid writing past it.
            return Wine.maxLogFileBytes
        }
    }

    private func writeData(_ data: Data, to handle: FileHandle) {
        do {
            try handle.write(contentsOf: data)
        } catch {
            Logger.wineKit.info("Failed to write log data: \(error)")
        }
    }

    private func writeTruncationMarkerIfPossible(
        _ markerData: Data,
        maxBytes: Int64,
        state: inout State,
        handle: FileHandle
    ) {
        guard !state.didWriteTruncationMarker else { return }
        let remainingTotal = maxBytes - state.bytesWritten
        if remainingTotal > 0 {
            let markerSlice = markerData.prefix(Int(remainingTotal))
            writeData(markerSlice, to: handle)
            state.bytesWritten += Int64(markerSlice.count)
        }
        state.didWriteTruncationMarker = true
    }
}

extension FileHandle {
    private enum Constants {
        /// Prevents extremely large environments from bloating logs while still providing useful diagnostics.
        static let maxEnvironmentKeysToLog = 200
    }

    func extract<T>(_ type: T.Type, offset: UInt64 = 0) -> T? {
        do {
            try self.seek(toOffset: offset)
            if let data = try self.read(upToCount: MemoryLayout<T>.size) {
                return data.withUnsafeBytes { $0.loadUnaligned(as: T.self) }
            } else {
                return nil
            }
        } catch {
            return nil
        }
    }

    func write(line: String) {
        do {
            guard let data = line.data(using: .utf8) else { return }
            try write(contentsOf: data)
        } catch {
            Logger.wineKit.info("Failed to write line: \(error)")
        }
    }

    /// Writes a line to a Whisky log file while enforcing the log size cap.
    ///
    /// This method is thread-safe across concurrent stdout/stderr writers for the same file handle.
    /// Once the per-file cap is reached, additional output is discarded without buffering.
    /// A single truncation marker is appended once when truncation begins.
    func writeWineLog(line: String) {
        guard let data = line.data(using: .utf8) else { return }
        WineLogCapRegistry.shared.write(data, to: self)
    }

    /// Closes a Whisky log file handle and clears any associated in-memory cap state.
    func closeWineLog() throws {
        defer {
            WineLogCapRegistry.shared.removeState(for: self)
        }
        try close()
    }

    // swiftlint:disable line_length
    func writeApplicationInfo() {
        var header = String()
        let macOSVersion = ProcessInfo.processInfo.operatingSystemVersion

        header += "Whisky Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "")\n"
        header += "Date: \(ISO8601DateFormatter().string(from: Date.now))\n"
        header += "macOS Version: \(macOSVersion.majorVersion).\(macOSVersion.minorVersion).\(macOSVersion.patchVersion)\n\n"
        writeWineLog(line: header)
    }

    // swiftlint:enable line_length

    func writeInfo(for process: Process) {
        var header = String()

        if let arguments = process.arguments {
            header += "Arguments: \(arguments.joined(separator: " "))\n\n"
        }

        if let environment = process.environment, !environment.isEmpty {
            // Avoid persisting raw environment values to logs (can contain secrets like tokens, API keys, etc.).
            let maxKeysToLog = Constants.maxEnvironmentKeysToLog
            let sortedKeys = environment.keys.sorted()
            let keysToLog = sortedKeys.prefix(maxKeysToLog)
            let keysDescription = keysToLog.joined(separator: ", ")
            header += "Environment (keys only):\n\(keysDescription)"
            if sortedKeys.count > maxKeysToLog {
                header += "\n... (\(sortedKeys.count - maxKeysToLog) more)"
            }
            header += "\n\n"
        }

        writeWineLog(line: header)
    }

    @MainActor
    func writeInfo(for bottle: Bottle) {
        var header = String()
        header += "Bottle Name: \(bottle.settings.name)\n"
        header += "Bottle URL: \(bottle.url.path)\n\n"

        if let version = WhiskyWineInstaller.whiskyWineVersion() {
            header += "WhiskyWine Version: \(version.major).\(version.minor).\(version.patch)\n"
        }
        header += "Windows Version: \(bottle.settings.windowsVersion)\n"
        header += "Enhanced Sync: \(bottle.settings.enhancedSync)\n\n"

        header += "Metal HUD: \(bottle.settings.metalHud)\n"
        header += "Metal Trace: \(bottle.settings.metalTrace)\n\n"

        if bottle.settings.dxvk {
            header += "DXVK: \(bottle.settings.dxvk)\n"
            header += "DXVK Async: \(bottle.settings.dxvkAsync)\n"
            header += "DXVK HUD: \(bottle.settings.dxvkHud)\n\n"
        }

        writeWineLog(line: header)
    }
}
