//
//  WinePrefixDiagnostics.swift
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

/// Captures diagnostic information about Wine prefix health for debugging dependency installation issues.
///
/// This struct follows the pattern established by `WhiskyWineSetupDiagnostics` to provide
/// bounded, shareable diagnostic reports when winetricks or other dependency installations fail
/// due to missing user profile directories or empty `%AppData%` environment variable.
///
/// ## Overview
///
/// Wine prefixes require properly initialized user profile directories for many Windows
/// dependencies to install correctly. When these directories are missing or the Wine
/// username differs from expectations, `%AppData%` can resolve to an empty string,
/// causing winetricks verbs like `dotnet48`, `d3dx9`, and `vcrun` to fail.
///
/// ## Usage
///
/// ```swift
/// var diagnostics = WinePrefixDiagnostics()
/// diagnostics.prefixPath = bottle.url.path
/// diagnostics.record("Checking prefix health")
///
/// // ... perform checks ...
///
/// let report = diagnostics.reportString(error: "AppData directory missing")
/// ```
public struct WinePrefixDiagnostics: Codable, Sendable {
    public private(set) var sessionID = UUID()
    public private(set) var timestamp = Date()
    public private(set) var events: [String] = []

    /// Maximum number of diagnostic events to retain.
    public static let maxEventCount = 100

    /// Maximum report size in UTF-8 bytes to keep sharing manageable.
    public static let maxReportBytes = 8_000

    private static let issueURL = "https://github.com/Whisky-App/Whisky/issues/64"
    private static let eventTimestampFormatter = Date.ISO8601FormatStyle()

    // MARK: - Prefix State

    /// The path to the Wine prefix (WINEPREFIX).
    public var prefixPath: String?

    /// Whether the prefix directory exists.
    public var prefixExists: Bool = false

    /// Whether drive_c exists within the prefix.
    public var driveCExists: Bool = false

    /// Whether the users directory exists.
    public var usersDirectoryExists: Bool = false

    /// The detected Wine username (from scanning users directory).
    public var detectedUsername: String?

    /// Whether the user profile directory exists.
    public var userProfileExists: Bool = false

    /// Whether the AppData directory exists.
    public var appDataExists: Bool = false

    /// Whether AppData/Roaming exists.
    public var roamingExists: Bool = false

    /// Whether AppData/Local exists.
    public var localAppDataExists: Bool = false

    // MARK: - Initialization

    public init() {}

    // MARK: - Event Recording

    /// Records a diagnostic event with timestamp.
    public mutating func record(_ message: String) {
        let timestamp = Date().formatted(Self.eventTimestampFormatter)
        events.append("[\(timestamp)] \(message)")
        if events.count > Self.maxEventCount {
            events.removeFirst(events.count - Self.maxEventCount)
        }
    }

    // MARK: - Report Generation

    /// Generates a diagnostic report string suitable for sharing in issue reports.
    ///
    /// The report prioritizes including the most recent events when truncation is needed.
    ///
    /// - Parameter error: Optional error message to include in the report header.
    /// - Returns: A formatted diagnostic report bounded to `maxReportBytes`.
    public func reportString(error: String? = nil) -> String {
        var prefixLines: [String] = []
        prefixLines.reserveCapacity(20)

        appendHeaderLines(into: &prefixLines, error: error)
        appendPrefixStateLines(into: &prefixLines)

        return buildReport(prefixLines: prefixLines, events: events, limit: Self.maxReportBytes)
    }

    private func appendHeaderLines(into lines: inout [String], error: String?) {
        lines.append("Wine Prefix Diagnostics (\(Self.issueURL))")
        lines.append("Session: \(sessionID.uuidString)")
        lines.append("Generated: \(Date().formatted(Self.eventTimestampFormatter))")
        if let error {
            lines.append("Error: \(error)")
        }
        lines.append("")
    }

    private func appendPrefixStateLines(into lines: inout [String]) {
        lines.append("[PREFIX STATE]")
        appendIfPresent("Prefix path", value: prefixPath, into: &lines)
        lines.append("Prefix exists: \(prefixExists)")
        lines.append("drive_c exists: \(driveCExists)")
        lines.append("users/ exists: \(usersDirectoryExists)")
        appendIfPresent("Detected username", value: detectedUsername, into: &lines)
        lines.append("User profile exists: \(userProfileExists)")
        lines.append("AppData exists: \(appDataExists)")
        lines.append("AppData/Roaming exists: \(roamingExists)")
        lines.append("AppData/Local exists: \(localAppDataExists)")
        lines.append("")
    }

    private func appendIfPresent(_ label: String, value: String?, into lines: inout [String]) {
        guard let value else { return }
        lines.append("\(label): \(value)")
    }

    private func buildReport(prefixLines: [String], events: [String], limit: Int) -> String {
        var lines = prefixLines
        lines.append("[EVENTS]")

        let prefixString = lines.joined(separator: "\n")
        let prefixBytes = prefixString.utf8.count
        guard prefixBytes < limit else {
            return truncateReport(prefixString, limit: limit)
        }
        guard !events.isEmpty else { return prefixString }

        // Include as many recent events as fit within the limit
        let availableBytes = limit - prefixBytes
        var includedEvents: [String] = []
        includedEvents.reserveCapacity(events.count)
        var usedBytes = 0

        // Iterate from most recent to oldest
        for event in events.reversed() {
            let eventBytes = event.utf8.count + 1 // +1 for newline
            if usedBytes + eventBytes > availableBytes {
                break
            }
            includedEvents.append(event)
            usedBytes += eventBytes
        }

        guard !includedEvents.isEmpty else { return prefixString }
        return prefixString + "\n" + includedEvents.reversed().joined(separator: "\n")
    }

    private func truncateReport(_ report: String, limit: Int) -> String {
        var prefixBytes = report.utf8.prefix(limit)

        // Drop trailing bytes until we have valid UTF-8
        while !prefixBytes.isEmpty,
              String(bytes: prefixBytes, encoding: .utf8) == nil {
            prefixBytes = prefixBytes.dropLast()
        }

        guard let prefixString = String(bytes: prefixBytes, encoding: .utf8) else {
            return ""
        }

        // Truncate at last newline for cleaner output
        if let lastNewline = prefixString.lastIndex(of: "\n") {
            return String(prefixString[..<lastNewline])
        }
        return prefixString
    }
}
