//
//  BottleVM.swift
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

import Foundation
import os.log
import SemanticVersion
import WhiskyKit

// MARK: - Bottle Creation Errors

enum BottleCreationError: LocalizedError {
    case directoryCreationFailed
    case metadataCreationFailed
    case wineVersionChangeFailed
    case persistenceSaveFailed

    var errorDescription: String? {
        switch self {
        case .directoryCreationFailed:
            "Failed to create bottle directory"
        case .metadataCreationFailed:
            "Failed to create bottle metadata"
        case .wineVersionChangeFailed:
            "Failed to configure Windows version"
        case .persistenceSaveFailed:
            "Failed to save bottle to persistence"
        }
    }
}

private let bottleVMLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.franke.Whisky",
    category: "BottleVM"
)

@MainActor
final class BottleVM: ObservableObject {
    static let shared = BottleVM()

    var bottlesList = BottleData()
    @Published var bottles: [Bottle] = []
    @Published var bottleCreationAlert: BottleCreationAlert?

    struct BottleCreationAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let diagnostics: String
    }

    func loadBottles() {
        bottles = bottlesList.loadBottles()
    }

    func countActive() -> Int {
        bottles.filter { $0.isAvailable == true }.count
    }

    func createNewBottle(bottleName: String, winVersion: WinVersion, bottleURL: URL) -> URL {
        let newBottleDir = bottleURL.appending(path: UUID().uuidString)

        Task {
            var bottleId: Bottle?
            do {
                // Create directory with proper error handling (FileManager is thread-safe)
                let fileManager = FileManager.default
                try fileManager.createDirectory(
                    at: newBottleDir,
                    withIntermediateDirectories: true,
                    attributes: nil
                )

                // Verify directory was created
                guard fileManager.fileExists(atPath: newBottleDir.path(percentEncoded: false)) else {
                    throw BottleCreationError.directoryCreationFailed
                }

                // Create bottle on main actor (since Bottle is @MainActor)
                let bottle = Bottle(bottleUrl: newBottleDir, inFlight: true)
                bottleId = bottle
                self.bottles.append(bottle)

                // Configure bottle settings (all on MainActor)
                bottle.settings.windowsVersion = winVersion
                bottle.settings.name = bottleName

                // Wine operations are async and can run on background threads
                try await Wine.changeWinVersion(bottle: bottle, win: winVersion)
                let wineVer = try await Wine.wineVersion()
                bottle.settings.wineVersion = SemanticVersion(wineVer) ?? SemanticVersion(0, 0, 0)

                // Save settings
                bottle.saveBottleSettings()

                // Add record to persistence
                if !self.bottlesList.paths.contains(newBottleDir) {
                    self.bottlesList.paths.append(newBottleDir)
                }
                self.loadBottles()
            } catch {
                let title = "Bottle Creation Failed"
                let message = error.localizedDescription
                let diagnostics = self.makeBottleCreationDiagnostics(
                    bottleName: bottleName,
                    winVersion: winVersion,
                    bottleURL: bottleURL,
                    newBottleDir: newBottleDir,
                    error: error
                )
                bottleVMLogger.error("Failed to create new bottle: \(message)")
                bottleVMLogger.error("\(diagnostics, privacy: .public)")
                self.bottleCreationAlert = BottleCreationAlert(
                    title: title,
                    message: message,
                    diagnostics: diagnostics
                )
                // Clean up on failure
                if let bottle = bottleId {
                    if let index = self.bottles.firstIndex(of: bottle) {
                        self.bottles.remove(at: index)
                    }
                }
                // Try to clean up the directory
                try? FileManager.default.removeItem(at: newBottleDir)
            }
        }
        return newBottleDir
    }

    private func makeBottleCreationDiagnostics(
        bottleName: String,
        winVersion: WinVersion,
        bottleURL: URL,
        newBottleDir: URL,
        error: Error
    ) -> String {
        func redactHome(_ path: String) -> String {
            let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
            return path.replacingOccurrences(of: home, with: "~")
        }

        let nsError = error as NSError
        let whiskyVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        let whiskyVersionString = formattedWhiskyVersion(
            appVersion: whiskyVersion,
            buildNumber: buildNumber
        )

        var lines: [String] = []
        lines.reserveCapacity(32)

        lines.append("Whisky Bottle Creation Diagnostics (Issue #61)")
        lines.append("Timestamp: \(Date().formatted())")
        lines.append("")
        appendBottleCreationInputLines(
            into: &lines,
            bottleName: bottleName,
            winVersion: winVersion,
            bottleURL: bottleURL,
            newBottleDir: newBottleDir,
            redactHome: redactHome
        )
        appendBottleCreationSystemLines(
            into: &lines,
            whiskyVersionString: whiskyVersionString
        )
        appendBottleCreationFilesystemLines(
            into: &lines,
            bottleURL: bottleURL,
            newBottleDir: newBottleDir,
            redactHome: redactHome
        )
        appendBottleCreationErrorLines(into: &lines, nsError: nsError)

        // Keep diagnostics bounded for copy/paste.
        return lines.joined(separator: "\n").prefix(4_000).description
    }

    private func formattedWhiskyVersion(appVersion: String, buildNumber: String) -> String {
        guard !appVersion.isEmpty else { return "unknown" }
        return buildNumber.isEmpty ? appVersion : "\(appVersion) (\(buildNumber))"
    }

    private func appendBottleCreationInputLines(
        into lines: inout [String],
        bottleName: String,
        winVersion: WinVersion,
        bottleURL: URL,
        newBottleDir: URL,
        redactHome: (String) -> String
    ) {
        lines.append("[INPUT]")
        lines.append("Bottle Name: \(bottleName)")
        lines.append("Windows Version: \(winVersion)")
        lines.append("Target Folder: \(redactHome(bottleURL.path(percentEncoded: false)))")
        lines.append("New Bottle Dir: \(redactHome(newBottleDir.path(percentEncoded: false)))")
        lines.append("")
    }

    private func appendBottleCreationSystemLines(
        into lines: inout [String],
        whiskyVersionString: String
    ) {
        lines.append("[SYSTEM]")
        lines.append("macOS Version: \(MacOSVersion.current.description)")
        lines.append("Whisky Version: \(whiskyVersionString)")
        let whiskyWineInstalled = WhiskyWineInstaller.isWhiskyWineInstalled() ? "yes" : "no"
        lines.append("WhiskyWine Installed: \(whiskyWineInstalled)")
        if let whiskyWineVersion = WhiskyWineInstaller.whiskyWineVersion() {
            lines.append("WhiskyWine Version: \(whiskyWineVersion)")
        }
        lines.append("")
    }

    private func appendBottleCreationFilesystemLines(
        into lines: inout [String],
        bottleURL: URL,
        newBottleDir: URL,
        redactHome: (String) -> String
    ) {
        lines.append("[FILESYSTEM]")
        let fileManager = FileManager.default
        let targetFolderExists = fileManager.fileExists(atPath: bottleURL.path(percentEncoded: false)) ? "yes" : "no"
        let newBottleDirExists = fileManager.fileExists(atPath: newBottleDir.path(percentEncoded: false)) ? "yes" : "no"
        lines.append("Target folder exists: \(targetFolderExists)")
        lines.append("New bottle dir exists: \(newBottleDirExists)")
        lines.append("BottleData file: \(redactHome(BottleData.bottleEntriesDir.path(percentEncoded: false)))")
        lines.append("")
    }

    private func appendBottleCreationErrorLines(
        into lines: inout [String],
        nsError: NSError
    ) {
        lines.append("[ERROR]")
        lines.append("Error: \(nsError.localizedDescription)")
        lines.append("NSError: domain=\(nsError.domain) code=\(nsError.code)")
    }
}
