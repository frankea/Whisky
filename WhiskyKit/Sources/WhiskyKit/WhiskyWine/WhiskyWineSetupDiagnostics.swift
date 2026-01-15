//
//  WhiskyWineSetupDiagnostics.swift
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

public struct WhiskyWineSetupDiagnostics: Codable, Sendable {
    public private(set) var sessionID = UUID()
    public private(set) var startedAt = Date()
    // SECURITY: Do not record secrets/tokens in diagnostics. This is user-shareable.
    // URLs below are safe to expose (public GitHub/CDN endpoints, no auth tokens).
    private(set) var events: [String] = []

    static let maxEventCount = 200
    // Limit report size in UTF-8 bytes to keep sharing manageable.
    static let maxReportBytes = 8_000

    private static let eventTimestampFormatStyle = Date.ISO8601FormatStyle()
    private static let issueURL = "https://github.com/Whisky-App/Whisky/issues/63"

    public struct InstallAttempt: Codable, Sendable {
        public let startedAt: Date
        public let finishedAt: Date
        public let succeeded: Bool

        public init(startedAt: Date, finishedAt: Date, succeeded: Bool) {
            self.startedAt = startedAt
            self.finishedAt = finishedAt
            self.succeeded = succeeded
        }
    }

    /// Public version plist URL (safe to share)
    public var versionPlistURL: String?
    /// Public download URL (safe to share)
    public var downloadURL: String?
    public var versionHTTPStatus: Int?
    public var downloadHTTPStatus: Int?

    public var bytesReceived: Int64 = 0
    public var bytesExpected: Int64 = 0
    public var lastProgressAt: Date?

    public var downloadStartedAt: Date?
    public var downloadFinishedAt: Date?
    public var installStartedAt: Date?
    public var installFinishedAt: Date?
    public private(set) var installAttempts: [InstallAttempt] = []

    public init() {}

    public mutating func reset() {
        sessionID = UUID()
        startedAt = Date()
        events = []
        resetDownloadState()
        installStartedAt = nil
        installFinishedAt = nil
        installAttempts = []
    }

    public mutating func resetDownloadState(reason: String? = nil) {
        versionPlistURL = nil
        downloadURL = nil
        versionHTTPStatus = nil
        downloadHTTPStatus = nil
        bytesReceived = 0
        bytesExpected = 0
        lastProgressAt = nil
        downloadStartedAt = nil
        downloadFinishedAt = nil
        if let reason {
            record(reason)
        }
    }

    public mutating func record(_ message: String) {
        let timestamp = Date().formatted(Self.eventTimestampFormatStyle)
        events.append("[\(timestamp)] \(message)")
        if events.count > Self.maxEventCount {
            events.removeFirst(events.count - Self.maxEventCount)
        }
    }

    public mutating func recordProgress(bytesReceived: Int64, bytesExpected: Int64) {
        self.bytesReceived = bytesReceived
        self.bytesExpected = bytesExpected
        lastProgressAt = Date()
    }

    public mutating func recordInstallAttempt(startedAt: Date, finishedAt: Date, succeeded: Bool) {
        installAttempts.append(InstallAttempt(
            startedAt: startedAt,
            finishedAt: finishedAt,
            succeeded: succeeded
        ))
    }

    public func reportString(stage: String, error: String? = nil) -> String {
        let estimatedCapacity = max(Self.maxEventCount, events.count) + installAttempts.count + 20
        var lines: [String] = []
        lines.reserveCapacity(estimatedCapacity)

        appendHeaderLines(into: &lines, stage: stage, error: error)
        appendNetworkLines(into: &lines)
        appendProgressLines(into: &lines)
        appendInstallAttemptLines(into: &lines)
        appendDiskLines(into: &lines)
        appendEventLines(into: &lines)

        let report = lines.joined(separator: "\n")
        return truncateReport(report, limit: Self.maxReportBytes)
    }

    private func appendHeaderLines(into lines: inout [String], stage: String, error: String?) {
        lines.append("WhiskyWine Setup Diagnostics (\(Self.issueURL))")
        lines.append("Session: \(sessionID.uuidString)")
        lines.append("Stage: \(stage)")
        lines.append("Generated: \(Date().formatted(Self.eventTimestampFormatStyle))")
        appendIfPresent("Error", value: error, into: &lines)
        lines.append("")
    }

    private func appendNetworkLines(into lines: inout [String]) {
        lines.append("[NETWORK]")
        appendIfPresent("Version plist", value: sanitizedURLString(versionPlistURL), into: &lines)
        appendIfPresent("Version plist HTTP", value: versionHTTPStatus, into: &lines)
        appendIfPresent("Download URL", value: sanitizedURLString(downloadURL), into: &lines)
        appendIfPresent("Download HTTP", value: downloadHTTPStatus, into: &lines)
        lines.append("")
    }

    private func appendProgressLines(into lines: inout [String]) {
        lines.append("[PROGRESS]")
        lines.append("Bytes received: \(bytesReceived)")
        lines.append("Bytes expected: \(bytesExpected)")
        appendIfPresent("Last progress", value: formattedTimestamp(lastProgressAt), into: &lines)
        appendIfPresent("Download started", value: formattedTimestamp(downloadStartedAt), into: &lines)
        appendIfPresent("Download finished", value: formattedTimestamp(downloadFinishedAt), into: &lines)
        appendIfPresent("Install started", value: formattedTimestamp(installStartedAt), into: &lines)
        appendIfPresent("Install finished", value: formattedTimestamp(installFinishedAt), into: &lines)
        lines.append("")
    }

    private func appendInstallAttemptLines(into lines: inout [String]) {
        guard !installAttempts.isEmpty else { return }
        lines.append("[INSTALL ATTEMPTS]")
        for (index, attempt) in installAttempts.enumerated() {
            let start = attempt.startedAt.formatted(Self.eventTimestampFormatStyle)
            let finish = attempt.finishedAt.formatted(Self.eventTimestampFormatStyle)
            let result = attempt.succeeded ? "success" : "failed"
            lines.append("Attempt \(index + 1): started \(start) finished \(finish) result \(result)")
        }
        lines.append("")
    }

    private func appendDiskLines(into lines: inout [String]) {
        lines.append("[DISK]")
        if let tmp = Self.availableDiskString(for: FileManager.default.temporaryDirectory) {
            lines.append("Temp available: \(tmp)")
        }
        if let appSupport = Self.availableDiskString(for: WhiskyWineInstaller.applicationFolder) {
            lines.append("App Support available: \(appSupport)")
        }
        lines.append("")
    }

    private func appendEventLines(into lines: inout [String]) {
        lines.append("[EVENTS]")
        lines.append(contentsOf: events)
    }

    private func formattedTimestamp(_ date: Date?) -> String? {
        guard let date else { return nil }
        return date.formatted(Self.eventTimestampFormatStyle)
    }

    private func sanitizedURLString(_ urlString: String?) -> String? {
        guard let urlString, let url = URL(string: urlString) else { return urlString }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return urlString }
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString ?? urlString
    }

    private func truncateReport(_ report: String, limit: Int) -> String {
        // Limit is based on UTF-8 byte count to keep shared output bounded.
        let utf8View = report.utf8
        guard utf8View.count > limit else { return report }

        let cappedLimit = max(limit, 0)
        var utf8Index = utf8View.index(utf8View.startIndex, offsetBy: cappedLimit)
        var limitIndex = String.Index(utf8Index, within: report)
        while limitIndex == nil && utf8Index > utf8View.startIndex {
            utf8Index = utf8View.index(before: utf8Index)
            limitIndex = String.Index(utf8Index, within: report)
        }

        let prefix = report[..<(limitIndex ?? report.startIndex)]
        if let lastNewline = prefix.lastIndex(of: "\n") {
            return String(prefix[..<lastNewline])
        }
        if let lastWhitespace = prefix.lastIndex(where: { $0.isWhitespace }) {
            return String(prefix[..<lastWhitespace])
        }
        return String(prefix)
    }

    private func appendIfPresent(_ label: String, value: (some CustomStringConvertible)?, into lines: inout [String]) {
        guard let value else { return }
        lines.append("\(label): \(value)")
    }

    private static func availableDiskString(for url: URL) -> String? {
        do {
            let values = try url.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityKey
            ])
            let importantBytes = values.volumeAvailableCapacityForImportantUsage
            let standardBytes = values.volumeAvailableCapacity.map(Int64.init)
            guard let bytes = importantBytes ?? standardBytes else { return nil }
            return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        } catch {
            return nil
        }
    }
}
