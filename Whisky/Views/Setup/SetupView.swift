//
//  SetupView.swift
//  Whisky
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

import SwiftUI
import WhiskyKit

enum SetupStage {
    case rosetta
    case whiskyWineDownload
    case whiskyWineInstall
}

struct SetupView: View {
    @State private var path: [SetupStage] = []
    @State var tarLocation: URL = .init(fileURLWithPath: "")
    @State private var whiskyWineDiagnostics = WhiskyWineSetupDiagnostics()
    @Binding var showSetup: Bool
    var firstTime: Bool = true

    var body: some View {
        VStack {
            NavigationStack(path: $path) {
                WelcomeView(path: $path, showSetup: $showSetup, firstTime: firstTime)
                    .navigationBarBackButtonHidden(true)
                    .navigationDestination(for: SetupStage.self) { stage in
                        switch stage {
                        case .rosetta:
                            RosettaView(path: $path, showSetup: $showSetup)
                        case .whiskyWineDownload:
                            WhiskyWineDownloadView(
                                tarLocation: $tarLocation,
                                path: $path,
                                showSetup: $showSetup,
                                diagnostics: $whiskyWineDiagnostics
                            )
                        case .whiskyWineInstall:
                            WhiskyWineInstallView(
                                tarLocation: $tarLocation,
                                path: $path,
                                showSetup: $showSetup,
                                diagnostics: $whiskyWineDiagnostics
                            )
                        }
                    }
            }
        }
        .padding()
        .interactiveDismissDisabled()
    }
}

struct WhiskyWineSetupDiagnostics: Codable, Sendable {
    private(set) var sessionID = UUID()
    private(set) var startedAt = Date()
    // NOTE: Do not record secrets/tokens in diagnostics. This is user-shareable.
    private(set) var events: [String] = []

    private static let eventTimestampFormatStyle = Date.ISO8601FormatStyle()

    var versionPlistURL: String?
    var downloadURL: String?
    var versionHTTPStatus: Int?
    var downloadHTTPStatus: Int?

    var bytesReceived: Int64 = 0
    var bytesExpected: Int64 = 0
    var lastProgressAt: Date?

    var downloadStartedAt: Date?
    var downloadFinishedAt: Date?
    var installStartedAt: Date?
    var installFinishedAt: Date?

    mutating func reset() {
        sessionID = UUID()
        startedAt = Date()
        events = []
        resetDownloadState()
        installStartedAt = nil
        installFinishedAt = nil
    }

    mutating func resetDownloadState(reason: String? = nil) {
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

    mutating func record(_ message: String) {
        let timestamp = Date().formatted(Self.eventTimestampFormatStyle)
        events.append("[\(timestamp)] \(message)")
        if events.count > 200 {
            events.removeFirst(events.count - 200)
        }
    }

    mutating func recordProgress(bytesReceived: Int64, bytesExpected: Int64) {
        self.bytesReceived = bytesReceived
        self.bytesExpected = bytesExpected
        lastProgressAt = Date()
    }

    func reportString(stage: String, error: String? = nil) -> String {
        let estimatedCapacity = max(200, events.count) + 20
        var lines: [String] = []
        lines.reserveCapacity(estimatedCapacity)

        appendHeaderLines(into: &lines, stage: stage, error: error)
        appendNetworkLines(into: &lines)
        appendProgressLines(into: &lines)
        appendDiskLines(into: &lines)
        appendEventLines(into: &lines)

        let report = lines.joined(separator: "\n")
        return truncateReport(report, limit: 8_000)
    }

    private func appendHeaderLines(into lines: inout [String], stage: String, error: String?) {
        lines.append("WhiskyWine Setup Diagnostics (Issue #63)")
        lines.append("Session: \(sessionID.uuidString)")
        lines.append("Stage: \(stage)")
        lines.append("Generated: \(Date().formatted())")
        appendIfPresent("Error", value: error, into: &lines)
        lines.append("")
    }

    private func appendNetworkLines(into lines: inout [String]) {
        lines.append("[NETWORK]")
        appendIfPresent("Version plist", value: versionPlistURL, into: &lines)
        appendIfPresent("Version plist HTTP", value: versionHTTPStatus, into: &lines)
        appendIfPresent("Download URL", value: downloadURL, into: &lines)
        appendIfPresent("Download HTTP", value: downloadHTTPStatus, into: &lines)
        lines.append("")
    }

    private func appendProgressLines(into lines: inout [String]) {
        lines.append("[PROGRESS]")
        lines.append("Bytes received: \(bytesReceived)")
        lines.append("Bytes expected: \(bytesExpected)")
        appendIfPresent("Last progress", value: lastProgressAt?.formatted(), into: &lines)
        appendIfPresent("Download started", value: downloadStartedAt?.formatted(), into: &lines)
        appendIfPresent("Download finished", value: downloadFinishedAt?.formatted(), into: &lines)
        appendIfPresent("Install started", value: installStartedAt?.formatted(), into: &lines)
        appendIfPresent("Install finished", value: installFinishedAt?.formatted(), into: &lines)
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

    private func truncateReport(_ report: String, limit: Int) -> String {
        guard report.count > limit else { return report }
        let limitIndex = report.index(report.startIndex, offsetBy: limit, limitedBy: report.endIndex)
            ?? report.endIndex
        let prefix = report[..<limitIndex]
        if let lastNewline = prefix.lastIndex(of: "\n") {
            return String(report[..<lastNewline])
        }
        if let lastWhitespace = prefix.lastIndex(where: { $0.isWhitespace }) {
            return String(report[..<lastWhitespace])
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
