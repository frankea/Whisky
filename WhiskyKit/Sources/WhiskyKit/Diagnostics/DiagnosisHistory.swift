//
//  DiagnosisHistory.swift
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

/// A single entry in a program's crash diagnosis history.
///
/// Each entry captures the essential metadata from a ``CrashDiagnosis``
/// so that users can review past diagnoses without re-analyzing logs.
public struct DiagnosisHistoryEntry: Codable, Sendable {
    /// When the diagnosis was performed.
    public let timestamp: Date

    /// Reference to the log file that was analyzed.
    public let logFileRef: String

    /// The primary crash category identified.
    public let primaryCategory: CrashCategory

    /// The confidence tier of the primary diagnosis.
    public let confidenceTier: ConfidenceTier

    /// Top matched pattern signatures (max 3).
    public let topSignatures: [String]

    /// IDs of suggested remediation cards.
    public let remediationCardIds: [String]

    /// The WINEDEBUG preset active during the run, if any.
    public let wineDebugPreset: WineDebugPreset?

    /// Identifier for the bottle that was analyzed.
    public let bottleIdentifier: String

    /// Path to the program executable that was analyzed.
    public let programPath: String

    public init(
        timestamp: Date,
        logFileRef: String,
        primaryCategory: CrashCategory,
        confidenceTier: ConfidenceTier,
        topSignatures: [String],
        remediationCardIds: [String],
        wineDebugPreset: WineDebugPreset?,
        bottleIdentifier: String,
        programPath: String
    ) {
        self.timestamp = timestamp
        self.logFileRef = logFileRef
        self.primaryCategory = primaryCategory
        self.confidenceTier = confidenceTier
        self.topSignatures = Array(topSignatures.prefix(3))
        self.remediationCardIds = remediationCardIds
        self.wineDebugPreset = wineDebugPreset
        self.bottleIdentifier = bottleIdentifier
        self.programPath = programPath
    }
}

/// Bounded, per-program crash diagnosis history with FIFO eviction.
///
/// Stores the last ``maxEntries`` diagnosis entries for a given program.
/// Older entries are evicted when the limit is exceeded. Persists to
/// a plist file using `PropertyListEncoder`/`PropertyListDecoder`,
/// following the ``ProgramSettings`` persistence pattern.
public struct DiagnosisHistory: Codable, Sendable {
    /// Maximum number of entries retained per program.
    public static let maxEntries = 5

    /// The stored diagnosis entries, ordered newest-last.
    public private(set) var entries: [DiagnosisHistoryEntry]

    /// Creates an empty diagnosis history.
    public init() {
        self.entries = []
    }

    /// Appends a new entry, evicting the oldest when the limit is exceeded.
    ///
    /// - Parameter entry: The diagnosis entry to append.
    public mutating func append(_ entry: DiagnosisHistoryEntry) {
        entries.append(entry)
        while entries.count > Self.maxEntries {
            entries.removeFirst()
        }
    }

    /// Removes all entries from the history.
    public mutating func clear() {
        entries.removeAll()
    }

    /// Whether the history contains no entries.
    public var isEmpty: Bool {
        entries.isEmpty
    }

    /// Loads a diagnosis history from a plist file.
    ///
    /// Returns an empty history if the file does not exist or cannot be decoded.
    ///
    /// - Parameter url: The URL to the plist file.
    /// - Returns: The decoded history, or an empty history on failure.
    public static func load(from url: URL) -> DiagnosisHistory {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return DiagnosisHistory()
        }

        do {
            let data = try Data(contentsOf: url)
            return try PropertyListDecoder().decode(DiagnosisHistory.self, from: data)
        } catch {
            return DiagnosisHistory()
        }
    }

    /// Saves the history to a plist file.
    ///
    /// - Parameter url: The URL where the history should be saved.
    /// - Throws: An error if encoding or writing fails.
    public func save(to url: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(self)
        try data.write(to: url)
    }
}
