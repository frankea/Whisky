//
//  TroubleshootingHistory.swift
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

/// Bounded history of completed troubleshooting sessions for a bottle.
///
/// Stores the last ``maxEntries`` completed sessions with age-based eviction
/// (entries older than ``maxAgeDays`` are removed). Follows the
/// ``DiagnosisHistory`` persistence pattern with ``PropertyListEncoder``/
/// ``PropertyListDecoder`` and `.atomic` writes.
public struct TroubleshootingHistory: Codable, Sendable {
    /// Maximum number of entries retained in the history.
    public static let maxEntries = 20

    /// Maximum age in days before entries are evicted.
    public static let maxAgeDays = 30

    /// The plist filename used within a bottle directory.
    public static let fileName = "TroubleshootingHistory.plist"

    /// The stored history entries, ordered oldest-first.
    public private(set) var entries: [TroubleshootingHistoryEntry]

    /// Creates an empty troubleshooting history.
    public init() {
        self.entries = []
    }

    /// Appends a new entry and evicts stale or overflow entries.
    ///
    /// Eviction order: first remove entries older than ``maxAgeDays``,
    /// then FIFO-evict until count is at or below ``maxEntries``.
    ///
    /// - Parameter entry: The completed session entry to append.
    public mutating func append(_ entry: TroubleshootingHistoryEntry) {
        entries.append(entry)

        // Evict entries older than maxAgeDays
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.maxAgeDays, to: Date()) ?? Date()
        entries.removeAll { $0.completedAt < cutoff }

        // FIFO eviction if still over limit
        while entries.count > Self.maxEntries {
            entries.removeFirst()
        }
    }

    /// Loads a troubleshooting history from a bottle directory.
    ///
    /// Returns an empty history if the file does not exist or cannot be decoded.
    ///
    /// - Parameter bottleURL: The URL of the bottle directory.
    /// - Returns: The decoded history, or an empty history on failure.
    public static func load(from bottleURL: URL) -> TroubleshootingHistory {
        let url = bottleURL.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return TroubleshootingHistory()
        }

        do {
            let data = try Data(contentsOf: url)
            return try PropertyListDecoder().decode(TroubleshootingHistory.self, from: data)
        } catch {
            Logger(subsystem: "com.isaacmarovitz.Whisky", category: "TroubleshootingHistory")
                .error("Failed to load troubleshooting history: \(error.localizedDescription)")
            return TroubleshootingHistory()
        }
    }

    /// Saves the history to a bottle directory using atomic writes.
    ///
    /// - Parameter bottleURL: The URL of the bottle directory.
    public func save(to bottleURL: URL) {
        let url = bottleURL.appendingPathComponent(Self.fileName)
        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            let data = try encoder.encode(self)
            try data.write(to: url, options: .atomic)
        } catch {
            Logger(subsystem: "com.isaacmarovitz.Whisky", category: "TroubleshootingHistory")
                .error("Failed to save troubleshooting history: \(error.localizedDescription)")
        }
    }

    /// Returns entries sorted by completion date, newest first.
    public var recentEntries: [TroubleshootingHistoryEntry] {
        entries.sorted { $0.completedAt > $1.completedAt }
    }
}
