//
//  Wine+ProcessManagement.swift
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

private let processLogger = Logger(
    subsystem: Bundle.whiskyBundleIdentifier,
    category: "Wine.ProcessManagement"
)

// MARK: - Wine Process Management Helpers

public extension Wine {
    /// Probes whether a wineserver is currently running for the given bottle.
    ///
    /// Uses `wineserver -k0` which sends signal 0 (a no-op) to the wineserver.
    /// Exit code 0 means the wineserver is alive; any other code (or error)
    /// means it is not running. This does **not** spawn a new wineserver.
    ///
    /// - Parameter bottle: The bottle whose wineserver to probe.
    /// - Returns: `true` if the wineserver is active, `false` otherwise.
    @MainActor
    static func isWineserverRunning(for bottle: Bottle) async -> Bool {
        do {
            let stream = try Wine.runWineserverProcess(
                name: "wineserver-probe",
                args: ["-k0"],
                bottle: bottle
            )

            var running = false
            for await output in stream {
                if case let .terminated(code) = output {
                    running = code == 0
                }
            }

            processLogger.debug(
                "Wineserver probe for '\(bottle.settings.name)': \(running ? "active" : "idle")"
            )
            return running
        } catch {
            processLogger.debug(
                "Wineserver probe for '\(bottle.settings.name)' failed: \(error.localizedDescription)"
            )
            return false
        }
    }

    /// Parses the CSV output of `tasklist.exe` into an array of ``WineProcess`` values.
    ///
    /// The expected format is quoted CSV with a header line:
    /// ```
    /// "Image Name","PID","Session Name","Session#","Mem Usage"
    /// "game.exe","42","Console","0","24 K"
    /// ```
    ///
    /// Lines that cannot be parsed (wrong field count, non-numeric PID) are silently skipped.
    /// All returned processes have ``ProcessSource/untracked`` source; the caller should
    /// update the source after merging with ``ProcessRegistry`` data.
    ///
    /// - Parameter output: The raw string output from `tasklist.exe`.
    /// - Returns: An array of parsed ``WineProcess`` instances.
    static func parseTasklistOutput(_ output: String) -> [WineProcess] {
        let lines = output.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
        var processes: [WineProcess] = []
        processes.reserveCapacity(lines.count)

        for line in lines {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
                .map { field in
                    var trimmed = field.trimmingCharacters(in: .whitespaces)
                    // Strip surrounding quotes
                    if trimmed.hasPrefix("\""), trimmed.hasSuffix("\"") {
                        trimmed = String(trimmed.dropFirst().dropLast())
                    }
                    return trimmed
                }

            // Require at least 5 fields: Image Name, PID, Session Name, Session#, Mem Usage
            guard fields.count >= 5 else { continue }

            // Skip the header line
            if fields[1] == "PID" { continue }

            // Parse the PID
            guard let pid = Int32(fields[1]) else { continue }

            let imageName = fields[0]
            let memoryUsage = fields[4]

            processes.append(WineProcess(
                imageName: imageName,
                winePID: pid,
                memoryUsage: memoryUsage,
                kind: ProcessKind.classify(imageName)
            ))
        }

        return processes
    }

    /// Sends a graceful kill request for a single Wine process via `taskkill.exe`.
    ///
    /// This asks the process to terminate cleanly. If the process has already
    /// exited, the error is silently ignored.
    ///
    /// - Parameters:
    ///   - winePID: The Wine/Windows PID to terminate.
    ///   - bottle: The bottle containing the process.
    @MainActor
    static func gracefulKillProcess(winePID: Int32, bottle: Bottle) async {
        do {
            try await Wine.runWine(
                ["taskkill.exe", "/PID", String(winePID)],
                bottle: bottle
            )
            processLogger.info("Sent graceful kill to Wine PID \(winePID)")
        } catch {
            processLogger.debug(
                "Graceful kill for Wine PID \(winePID) failed (process may have exited): \(error.localizedDescription)"
            )
        }
    }

    /// Sends a forced kill request for a single Wine process via `taskkill.exe /F`.
    ///
    /// This forcefully terminates the process without giving it a chance to
    /// clean up. If the process has already exited, the error is silently ignored.
    ///
    /// - Parameters:
    ///   - winePID: The Wine/Windows PID to terminate.
    ///   - bottle: The bottle containing the process.
    @MainActor
    static func forceKillProcess(winePID: Int32, bottle: Bottle) async {
        do {
            try await Wine.runWine(
                ["taskkill.exe", "/PID", String(winePID), "/F"],
                bottle: bottle
            )
            processLogger.info("Sent force kill to Wine PID \(winePID)")
        } catch {
            processLogger.debug(
                "Force kill for Wine PID \(winePID) failed (process may have exited): \(error.localizedDescription)"
            )
        }
    }
}
