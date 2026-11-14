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
import os.log

/// A single entry in the remediation timeline.
///
/// Records one remediation card that was applied from a program's crash
/// diagnosis, with optional before/after values to show what changed.
/// The timeline file is already per program, so an entry carries no path:
/// nothing in it points into the user's home folder.
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

    public init(
        timestamp: Date,
        actionId: String,
        actionTitle: String,
        beforeValue: String?,
        afterValue: String?
    ) {
        self.timestamp = timestamp
        self.actionId = actionId
        self.actionTitle = actionTitle
        self.beforeValue = beforeValue
        self.afterValue = afterValue
    }
}

/// Bounded timeline of the remediation cards applied for one program.
///
/// Tracks the last ``maxEntries`` cards applied from the program's crash
/// diagnosis, with timestamps and before/after values, for the "remediation
/// history" part of a diagnostic export. Stored next to the program's
/// settings at ``url(forProgramAt:inBottleAt:)``.
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

    /// Where the timeline for the program at `programURL` lives.
    ///
    /// `<bottle>/Program Settings/<identity>.remediation-timeline.plist`, next
    /// to the program's settings. Keyed like the settings file, by the
    /// executable's stem plus a hash of its bottle-relative path, so two
    /// programs sharing a file name (the classic `Launch.exe` case) keep
    /// separate histories.
    ///
    /// - Parameters:
    ///   - programURL: The program's executable.
    ///   - bottleURL: The bottle the program belongs to.
    /// - Returns: The URL of the timeline plist.
    public static func url(forProgramAt programURL: URL, inBottleAt bottleURL: URL) -> URL {
        bottleURL
            .appending(path: "Program Settings")
            .appending(path: Program.settingsIdentity(for: programURL, bottleURL: bottleURL))
            .appendingPathExtension("remediation-timeline.plist")
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

    /// Saves the timeline to a plist file, creating its folder when needed.
    ///
    /// - Parameter url: The URL where the timeline should be saved.
    /// - Throws: An error if encoding or writing fails.
    public func save(to url: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(self)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    /// Appends `entry` to the stored timeline of the program at `programURL`.
    ///
    /// Loads the timeline from ``url(forProgramAt:inBottleAt:)``, records the
    /// entry and saves it back. A failure is logged, never thrown: the
    /// remediation itself has already been applied.
    ///
    /// - Parameters:
    ///   - entry: The applied remediation card.
    ///   - programURL: The program whose diagnosis offered the card.
    ///   - bottleURL: The bottle the program belongs to.
    public static func record(
        _ entry: RemediationTimelineEntry,
        forProgramAt programURL: URL,
        inBottleAt bottleURL: URL
    ) {
        let url = url(forProgramAt: programURL, inBottleAt: bottleURL)
        var timeline = load(from: url)
        timeline.record(entry)
        do {
            try timeline.save(to: url)
        } catch {
            Logger(subsystem: "com.franke.Whisky", category: "RemediationTimeline")
                .error("Failed to save remediation timeline: \(error.localizedDescription)")
        }
    }
}
