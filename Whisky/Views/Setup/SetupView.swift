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
    private(set) var events: [String] = []

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
        versionPlistURL = nil
        downloadURL = nil
        versionHTTPStatus = nil
        downloadHTTPStatus = nil
        bytesReceived = 0
        bytesExpected = 0
        lastProgressAt = nil
        downloadStartedAt = nil
        downloadFinishedAt = nil
        installStartedAt = nil
        installFinishedAt = nil
    }

    mutating func record(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
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
        var lines: [String] = []
        lines.reserveCapacity(128)

        lines.append("WhiskyWine Setup Diagnostics (Issue #63)")
        lines.append("Session: \(sessionID.uuidString)")
        lines.append("Stage: \(stage)")
        lines.append("Generated: \(Date().formatted())")
        if let error {
            lines.append("Error: \(error)")
        }
        lines.append("")

        lines.append("[NETWORK]")
        if let versionPlistURL { lines.append("Version plist: \(versionPlistURL)") }
        if let versionHTTPStatus { lines.append("Version plist HTTP: \(versionHTTPStatus)") }
        if let downloadURL { lines.append("Download URL: \(downloadURL)") }
        if let downloadHTTPStatus { lines.append("Download HTTP: \(downloadHTTPStatus)") }
        lines.append("")

        lines.append("[PROGRESS]")
        lines.append("Bytes received: \(bytesReceived)")
        lines.append("Bytes expected: \(bytesExpected)")
        if let lastProgressAt { lines.append("Last progress: \(lastProgressAt.formatted())") }
        if let downloadStartedAt { lines.append("Download started: \(downloadStartedAt.formatted())") }
        if let downloadFinishedAt { lines.append("Download finished: \(downloadFinishedAt.formatted())") }
        if let installStartedAt { lines.append("Install started: \(installStartedAt.formatted())") }
        if let installFinishedAt { lines.append("Install finished: \(installFinishedAt.formatted())") }
        lines.append("")

        lines.append("[DISK]")
        if let tmp = Self.availableDiskString(for: FileManager.default.temporaryDirectory) {
            lines.append("Temp available: \(tmp)")
        }
        if let appSupport = Self.availableDiskString(for: WhiskyWineInstaller.applicationFolder) {
            lines.append("App Support available: \(appSupport)")
        }
        lines.append("")

        lines.append("[EVENTS]")
        lines.append(contentsOf: events)

        return lines.joined(separator: "\n").prefix(8_000).description
    }

    private static func availableDiskString(for url: URL) -> String? {
        do {
            let values = try url.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityKey
            ])
            let bytes = values.volumeAvailableCapacityForImportantUsage ?? values.volumeAvailableCapacity
            guard let bytes else { return nil }
            return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        } catch {
            return nil
        }
    }
}
