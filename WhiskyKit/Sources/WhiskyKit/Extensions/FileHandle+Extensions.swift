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
import os.log
import SemanticVersion

extension FileHandle {
    private enum Constants {
        /// Prevents extremely large environments from bloating logs while still providing useful diagnostics.
        static let maxEnvironmentKeysToLog = 200
    }

    func extract<T>(_ type: T.Type, offset: UInt64 = 0) -> T? {
        do {
            try self.seek(toOffset: offset)
            // A read straddling EOF returns fewer bytes than requested;
            // loading T from the short buffer would read out of bounds.
            if let data = try self.read(upToCount: MemoryLayout<T>.size),
               data.count >= MemoryLayout<T>.size {
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
    /// A log that reaches its cap keeps its head (the launch header and early output) and its
    /// newest output, with the truncation marker between them (``WineLogLimits``).
    func writeWineLog(line: String) {
        writeWineLog(line: line, limits: .standard)
    }

    /// Writes a line to a Whisky log file under the given limits. Tests use small ones.
    func writeWineLog(line: String, limits: WineLogLimits) {
        guard let data = line.data(using: .utf8) else { return }
        WineLogCapRegistry.shared.write(data, to: self, limits: limits)
    }

    /// Closes a Whisky log file handle and clears any associated in-memory cap state.
    func closeWineLog() throws {
        defer {
            WineLogCapRegistry.shared.removeState(for: self)
        }
        try close()
    }

    func writeApplicationInfo() {
        var header = String()
        let macOSVersion = ProcessInfo.processInfo.operatingSystemVersion
        let macOSVersionString =
            "\(macOSVersion.majorVersion).\(macOSVersion.minorVersion).\(macOSVersion.patchVersion)"

        header += "Whisky Version: \(WhiskyAppVersion.current)\n"
        header += "Date: \(ISO8601DateFormatter().string(from: Date.now))\n"
        header += "macOS Version: \(macOSVersionString)\n\n"
        writeWineLog(line: header)
    }

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
