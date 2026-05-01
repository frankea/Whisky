//
//  RemediationTimeline.swift
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

/// A single entry in the remediation timeline.
///
/// Records one remediation action that was applied, with optional
/// before/after values to show what changed.
public struct RemediationTimelineEntry: Codable, Sendable {
    /// When the remediation action was applied.
    public let timestamp: Date

    /// The stable identifier of the remediation action.
    public let actionId: String

    /// Human-readable title of the action.
    public let actionTitle: String

    /// The value before the remediation was applied, if applicable.
    public let beforeValue: String?

    /// The value after the remediation was applied, if applicable.
    public let afterValue: String?

    /// Identifier for the bottle where the action was applied.
    public let bottleIdentifier: String

    /// Path to the program executable the action targets.
    public let programPath: String

    public init(
        timestamp: Date,
        actionId: String,
        actionTitle: String,
        beforeValue: String?,
        afterValue: String?,
        bottleIdentifier: String,
        programPath: String
    ) {
        self.timestamp = timestamp
        self.actionId = actionId
        self.actionTitle = actionTitle
        self.beforeValue = beforeValue
        self.afterValue = afterValue
        self.bottleIdentifier = bottleIdentifier
        self.programPath = programPath
    }
}

/// Bounded timeline of remediation actions applied per bottle/program.
///
/// Tracks the last ``maxEntries`` remediation actions with timestamps
/// and before/after values for export in diagnostic reports.
/// Follows the same persistence pattern as ``DiagnosisHistory``.
public struct RemediationTimeline: Codable, Sendable {
    /// Maximum number of entries retained.
    public static let maxEntries = 10

    /// The stored timeline entries, ordered newest-last.
    public private(set) var entries: [RemediationTimelineEntry]

    /// Creates an empty remediation timeline.
    public init() {
        self.entries = []
    }

    /// Records a new remediation action, evicting the oldest when the limit is exceeded.
    ///
    /// - Parameter entry: The timeline entry to record.
    public mutating func record(_ entry: RemediationTimelineEntry) {
        entries.append(entry)
        while entries.count > Self.maxEntries {
            entries.removeFirst()
        }
    }

    /// Removes all entries from the timeline.
    public mutating func clear() {
        entries.removeAll()
    }

    /// Whether the timeline contains no entries.
    public var isEmpty: Bool {
        entries.isEmpty
    }

    /// Loads a remediation timeline from a plist file.
    ///
    /// Returns an empty timeline if the file does not exist or cannot be decoded.
    ///
    /// - Parameter url: The URL to the plist file.
    /// - Returns: The decoded timeline, or an empty timeline on failure.
    public static func load(from url: URL) -> RemediationTimeline {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return RemediationTimeline()
        }

        do {
            let data = try Data(contentsOf: url)
            return try PropertyListDecoder().decode(RemediationTimeline.self, from: data)
        } catch {
            return RemediationTimeline()
        }
    }

    /// Saves the timeline to a plist file.
    ///
    /// - Parameter url: The URL where the timeline should be saved.
    /// - Throws: An error if encoding or writing fails.
    public func save(to url: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(self)
        try data.write(to: url)
    }
}
