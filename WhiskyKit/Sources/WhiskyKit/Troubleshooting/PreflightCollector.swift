//
//  PreflightCollector.swift
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

/// Gathers cheap, eagerly-collected state at the start of a troubleshooting session.
///
/// The preflight snapshot provides identity and runtime context to
/// ``TroubleshootingCheck`` implementations without requiring expensive
/// diagnostic operations. All data collected here should be fast to obtain
/// (no Wine process launches, no file scanning beyond directory listing).
///
/// Follows the caseless enum pattern used by ``PatternLoader`` and ``GameDBLoader``.
public enum PreflightCollector {
    private static let logger = Logger(
        subsystem: "com.isaacmarovitz.Whisky",
        category: "PreflightCollector"
    )

    /// Collects cheap preflight data for a troubleshooting session.
    ///
    /// Gathers bottle identity, program identity, running process state,
    /// recent log file location, audio device info, and resolved graphics
    /// backend. All operations are fast and do not launch Wine processes.
    ///
    /// - Parameters:
    ///   - bottle: The bottle being troubleshot.
    ///   - program: The program being troubleshot, if any.
    /// - Returns: A ``PreflightData`` snapshot.
    @MainActor
    public static func collect(bottle: Bottle, program: Program?) async -> PreflightData {
        let isRunning = await Wine.isWineserverRunning(for: bottle)
        let processCount = ProcessRegistry.shared.getProcessCount(for: bottle)

        let resolvedBackend: GraphicsBackend = if bottle.settings.graphicsBackend == .recommended {
            GraphicsBackendResolver.resolve()
        } else {
            bottle.settings.graphicsBackend
        }

        // Audio device info (best-effort)
        let audioMonitor = AudioDeviceMonitor()
        let audioDevice = audioMonitor.defaultOutputDevice()

        // Recent log and exit code from run history
        let (recentLogURL, lastExitCode) = findRecentRunInfo(for: bottle, program: program)

        logger.debug(
            "Preflight: wineserver=\(isRunning), procs=\(processCount), backend=\(resolvedBackend.rawValue)"
        )

        return PreflightData(
            bottleURL: bottle.url,
            bottleName: bottle.settings.name,
            programURL: program?.url,
            programName: program?.name,
            launcherType: nil, // LauncherDetection is in app target; populated by app layer if needed
            isWineserverRunning: isRunning,
            processCount: processCount,
            recentLogURL: recentLogURL,
            lastExitCode: lastExitCode,
            audioDeviceName: audioDevice?.name,
            audioTransportType: audioDevice?.transportType.displayName,
            graphicsBackend: resolvedBackend.rawValue,
            collectedAt: Date()
        )
    }

    // MARK: - Private Helpers

    /// Finds the most recent log file URL and exit code for a program.
    ///
    /// Queries the run log history for the program (or scans the bottle's
    /// log directory if no program is specified) to find the most recent
    /// log entry.
    ///
    /// - Parameters:
    ///   - bottle: The bottle to search in.
    ///   - program: The program to search for, if any.
    /// - Returns: A tuple of the most recent log URL and exit code.
    @MainActor
    private static func findRecentRunInfo(
        for bottle: Bottle,
        program: Program?
    ) -> (URL?, Int32?) {
        guard let program else {
            // No program context; try to find any recent log in the bottle
            return (findRecentLogInBottle(bottle: bottle), nil)
        }

        let history = RunLogStore.load(for: program.name, in: bottle.url)
        guard let mostRecent = history.entries.last else {
            return (nil, nil)
        }

        let logsFolder = bottle.url
            .appending(path: "logs")
            .appending(path: program.name)
        let logURL = logsFolder.appending(path: mostRecent.logFileName)
        let logExists = FileManager.default.fileExists(atPath: logURL.path(percentEncoded: false))

        return (logExists ? logURL : nil, mostRecent.exitCode)
    }

    /// Scans the bottle's log directory for the most recently modified log file.
    ///
    /// Used when no program context is available. Searches all subdirectories
    /// of the logs folder for `.log` files and returns the most recent one.
    private static func findRecentLogInBottle(bottle: Bottle) -> URL? {
        let logsFolder = bottle.url.appending(path: "logs")
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: logsFolder.path(percentEncoded: false)) else {
            return nil
        }

        guard let enumerator = fileManager.enumerator(
            at: logsFolder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        else {
            return nil
        }

        var mostRecentURL: URL?
        var mostRecentDate: Date?

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "log" else { continue }

            guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modDate = values.contentModificationDate
            else {
                continue
            }

            if let existingDate = mostRecentDate {
                if modDate > existingDate {
                    mostRecentDate = modDate
                    mostRecentURL = fileURL
                }
            } else {
                mostRecentDate = modDate
                mostRecentURL = fileURL
            }
        }

        return mostRecentURL
    }
}
