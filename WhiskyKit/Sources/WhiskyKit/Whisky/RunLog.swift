//
//  RunLog.swift
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

/// A single entry in a program's run log history.
///
/// Each launch of a Windows program creates a `RunLogEntry` that tracks the session
/// metadata: when it started, when it ended, how it exited, and where the log file
/// is stored. The log file name is stored as a relative path (not an absolute URL)
/// so that entries survive bottle moves.
public struct RunLogEntry: Codable, Identifiable, Equatable, Sendable {
    /// Unique identifier for this run.
    public let id: UUID

    /// When the program was launched.
    public let startTime: Date

    /// When the program exited. `nil` while still running.
    public var endTime: Date?

    /// The process exit code. `nil` while still running.
    public var exitCode: Int32?

    /// Log file name relative to the logs folder (not an absolute path).
    public let logFileName: String

    /// Display name of the program that was launched.
    public let programName: String

    /// Name of the WINEDEBUG preset active during this run, if any.
    public var activeWineDebugPreset: String?

    /// Whether WINEDEBUG output was captured during this run.
    public var hasWineDebugOutput: Bool = false

    /// Whether the program is still running (no end time recorded yet).
    public var isRunning: Bool {
        endTime == nil
    }

    /// Duration of the run in seconds, or `nil` if still running.
    public var duration: TimeInterval? {
        guard let end = endTime else { return nil }
        return end.timeIntervalSince(startTime)
    }

    /// Creates a new run log entry for a program launch.
    ///
    /// - Parameters:
    ///   - programName: Display name of the program being launched.
    ///   - logFileName: Log file name relative to the logs folder.
    public init(programName: String, logFileName: String) {
        self.id = UUID()
        self.startTime = Date()
        self.logFileName = logFileName
        self.programName = programName
    }
}

/// Bounded, per-program run log history with FIFO eviction.
///
/// Stores the last ``maxEntriesPerProgram`` run entries for a given program.
/// Older entries are evicted when the limit is exceeded, and the caller
/// is given the removed entries so it can clean up their log files.
///
/// Follows the ``DiagnosisHistory`` persistence pattern from Phase 5.
public struct RunLogHistory: Codable, Equatable {
    /// Maximum number of run entries retained per program.
    public static let maxEntriesPerProgram = 10

    /// The stored run entries, ordered oldest-first.
    public var entries: [RunLogEntry] = []

    /// Creates an empty run log history.
    public init() {}

    /// Appends a new entry, pruning the oldest entries if count exceeds the max.
    ///
    /// - Parameter entry: The run log entry to append.
    /// - Returns: Any entries that were removed due to pruning. The caller
    ///   should delete their associated log files.
    @discardableResult
    public mutating func append(_ entry: RunLogEntry) -> [RunLogEntry] {
        entries.append(entry)
        var removed: [RunLogEntry] = []
        while entries.count > Self.maxEntriesPerProgram {
            removed.append(entries.removeFirst())
        }
        return removed
    }

    /// Marks a run entry as completed with an exit code.
    ///
    /// - Parameters:
    ///   - id: The UUID of the entry to update.
    ///   - exitCode: The process exit code.
    ///   - hasWineDebug: Whether WINEDEBUG output was captured.
    public mutating func markCompleted(id: UUID, exitCode: Int32, hasWineDebug: Bool) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].endTime = Date()
        entries[index].exitCode = exitCode
        entries[index].hasWineDebugOutput = hasWineDebug
    }

    /// Resolves all log file names to full URLs in the given logs folder.
    ///
    /// - Parameter logsFolder: The URL to the logs directory.
    /// - Returns: An array of resolved log file URLs.
    public func logFileURLs(in logsFolder: URL) -> [URL] {
        entries.map { logsFolder.appending(path: $0.logFileName) }
    }

    /// Removes a specific entry by ID.
    ///
    /// - Parameter id: The UUID of the entry to remove.
    /// - Returns: The removed entry, or `nil` if not found.
    @discardableResult
    public mutating func deleteEntry(id: UUID) -> RunLogEntry? {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return nil }
        return entries.remove(at: index)
    }

    /// Prunes entries to keep only the most recent ones.
    ///
    /// - Parameter keepLast: The number of most recent entries to keep.
    ///   Defaults to ``maxEntriesPerProgram``.
    /// - Returns: The entries that were removed.
    @discardableResult
    public mutating func deleteOldEntries(keepLast: Int = maxEntriesPerProgram) -> [RunLogEntry] {
        guard entries.count > keepLast else { return [] }
        let removeCount = entries.count - keepLast
        let removed = Array(entries.prefix(removeCount))
        entries.removeFirst(removeCount)
        return removed
    }
}

/// Caseless enum providing persistence operations for run log history.
///
/// Run history is stored in a separate `.run-history.plist` file per program
/// (not in the main `ProgramSettings` plist) to avoid bloating the settings file.
public enum RunLogStore {
    private static let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "RunLogStore")

    /// Returns the URL for a program's run history plist file.
    ///
    /// - Parameters:
    ///   - programName: The program's file name (e.g., `"game.exe"`).
    ///   - bottleURL: The bottle's root directory URL.
    /// - Returns: URL to `{bottle}/Program Settings/{programName}.run-history.plist`.
    public static func historyURL(for programName: String, in bottleURL: URL) -> URL {
        bottleURL
            .appending(path: "Program Settings")
            .appending(path: programName)
            .appendingPathExtension("run-history.plist")
    }

    /// Loads the run history for a program, returning an empty history on failure.
    ///
    /// - Parameters:
    ///   - programName: The program's file name.
    ///   - bottleURL: The bottle's root directory URL.
    /// - Returns: The decoded history, or an empty history on failure.
    public static func load(for programName: String, in bottleURL: URL) -> RunLogHistory {
        let url = historyURL(for: programName, in: bottleURL)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return RunLogHistory()
        }

        do {
            let data = try Data(contentsOf: url)
            return try PropertyListDecoder().decode(RunLogHistory.self, from: data)
        } catch {
            logger.error("Failed to load run history: \(error.localizedDescription)")
            return RunLogHistory()
        }
    }

    /// Saves a run history to disk.
    ///
    /// Creates the `Program Settings` directory if it does not exist.
    ///
    /// - Parameters:
    ///   - history: The run log history to save.
    ///   - programName: The program's file name.
    ///   - bottleURL: The bottle's root directory URL.
    public static func save(_ history: RunLogHistory, for programName: String, in bottleURL: URL) {
        let url = historyURL(for: programName, in: bottleURL)
        let settingsFolder = bottleURL.appending(path: "Program Settings")

        do {
            if !FileManager.default.fileExists(atPath: settingsFolder.path(percentEncoded: false)) {
                try FileManager.default.createDirectory(at: settingsFolder, withIntermediateDirectories: true)
            }

            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            let data = try encoder.encode(history)
            try data.write(to: url)
        } catch {
            logger.error("Failed to save run history: \(error.localizedDescription)")
        }
    }

    /// Calculates the total size of all `.log` files in a logs folder.
    ///
    /// - Parameter logsFolder: The URL to the logs directory.
    /// - Returns: Total size in bytes, or 0 on failure.
    public static func totalLogSize(in logsFolder: URL) -> Int64 {
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: logsFolder,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            )

            return urls.reduce(Int64(0)) { total, url in
                guard url.pathExtension.lowercased() == "log" else { return total }
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return total + Int64(size)
            }
        } catch {
            return 0
        }
    }
}
