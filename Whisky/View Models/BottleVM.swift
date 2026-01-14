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

        let request = BottleCreationRequest(
            bottleName: bottleName,
            winVersion: winVersion,
            bottleURL: bottleURL,
            newBottleDir: newBottleDir
        )
        Task {
            await self.createBottleTask(request: request)
        }
        return newBottleDir
    }

    private struct BottleCreationRequest {
        let bottleName: String
        let winVersion: WinVersion
        let bottleURL: URL
        let newBottleDir: URL
    }

    private func createBottleTask(request: BottleCreationRequest) async {
        var bottle: Bottle?
        do {
            try createBottleDirectory(at: request.newBottleDir)

            // Create bottle on main actor (since Bottle is @MainActor)
            let createdBottle = Bottle(bottleUrl: request.newBottleDir, inFlight: true)
            bottle = createdBottle
            bottles.append(createdBottle)

            // Configure bottle settings (all on MainActor)
            createdBottle.settings.windowsVersion = request.winVersion
            createdBottle.settings.name = request.bottleName

            // Wine operations are async and can run on background threads
            try await Wine.changeWinVersion(bottle: createdBottle, win: request.winVersion)
            let wineVer = try await Wine.wineVersion()
            createdBottle.settings.wineVersion = SemanticVersion(wineVer) ?? SemanticVersion(0, 0, 0)

            // Save settings
            createdBottle.saveBottleSettings()

            persistBottleCreation(request: request)
            loadBottles()
        } catch {
            handleBottleCreationFailure(error, request: request, bottle: bottle)
        }
    }

    private func createBottleDirectory(at url: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: nil
        )
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw BottleCreationError.directoryCreationFailed
        }
    }

    private func persistBottleCreation(request: BottleCreationRequest) {
        if !bottlesList.paths.contains(request.newBottleDir) {
            bottlesList.paths.append(request.newBottleDir)
        }
    }

    private func handleBottleCreationFailure(
        _ error: Error,
        request: BottleCreationRequest,
        bottle: Bottle?
    ) {
        let message = error.localizedDescription
        let diagnostics = makeBottleCreationDiagnostics(
            bottleName: request.bottleName,
            winVersion: request.winVersion,
            bottleURL: request.bottleURL,
            newBottleDir: request.newBottleDir,
            error: error
        )
        bottleVMLogger.error("Failed to create new bottle: \(message)")
        bottleVMLogger.error("\(diagnostics, privacy: .public)")
        bottleCreationAlert = BottleCreationAlert(
            title: "Bottle Creation Failed",
            message: message,
            diagnostics: diagnostics
        )

        // Clean up on failure
        if let bottle, let index = bottles.firstIndex(of: bottle) {
            bottles.remove(at: index)
        }
        try? FileManager.default.removeItem(at: request.newBottleDir)
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

        let context = BottleCreationDiagnosticsContext(
            bottleName: bottleName,
            winVersion: winVersion,
            bottleURL: bottleURL,
            newBottleDir: newBottleDir,
            redactHome: redactHome
        )

        let lines = makeBottleCreationDiagnosticsLines(
            context: context,
            whiskyVersionString: formattedWhiskyVersion(),
            nsError: error as NSError
        )

        // Keep diagnostics bounded for copy/paste.
        return lines.joined(separator: "\n").prefix(4_000).description
    }

    private struct BottleCreationDiagnosticsContext {
        let bottleName: String
        let winVersion: WinVersion
        let bottleURL: URL
        let newBottleDir: URL
        let bottleURLPath: String
        let newBottleDirPath: String
        let bottleDataPath: String

        init(
            bottleName: String,
            winVersion: WinVersion,
            bottleURL: URL,
            newBottleDir: URL,
            redactHome: (String) -> String
        ) {
            self.bottleName = bottleName
            self.winVersion = winVersion
            self.bottleURL = bottleURL
            self.newBottleDir = newBottleDir
            bottleURLPath = redactHome(bottleURL.path(percentEncoded: false))
            newBottleDirPath = redactHome(newBottleDir.path(percentEncoded: false))
            bottleDataPath = redactHome(BottleData.bottleEntriesDir.path(percentEncoded: false))
        }
    }

    private func formattedWhiskyVersion() -> String {
        let whiskyVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        guard !whiskyVersion.isEmpty else { return "unknown" }
        return buildNumber.isEmpty ? whiskyVersion : "\(whiskyVersion) (\(buildNumber))"
    }

    private func makeBottleCreationDiagnosticsLines(
        context: BottleCreationDiagnosticsContext,
        whiskyVersionString: String,
        nsError: NSError
    ) -> [String] {
        var lines: [String] = []
        lines.reserveCapacity(32)

        lines.append("Whisky Bottle Creation Diagnostics (Issue #61)")
        lines.append("Timestamp: \(Date().formatted())")
        lines.append("")
        appendBottleCreationInputLines(into: &lines, context: context)
        appendBottleCreationSystemLines(into: &lines, whiskyVersionString: whiskyVersionString)
        appendBottleCreationFilesystemLines(into: &lines, context: context)
        appendBottleCreationErrorLines(into: &lines, nsError: nsError)

        return lines
    }

    private func appendBottleCreationInputLines(
        into lines: inout [String],
        context: BottleCreationDiagnosticsContext
    ) {
        lines.append("[INPUT]")
        lines.append("Bottle Name: \(context.bottleName)")
        lines.append("Windows Version: \(context.winVersion)")
        lines.append("Target Folder: \(context.bottleURLPath)")
        lines.append("New Bottle Dir: \(context.newBottleDirPath)")
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
        context: BottleCreationDiagnosticsContext
    ) {
        lines.append("[FILESYSTEM]")
        let fileManager = FileManager.default
        let targetFolderExists = fileManager
            .fileExists(atPath: context.bottleURL.path(percentEncoded: false)) ? "yes" : "no"
        let newBottleDirExists = fileManager
            .fileExists(atPath: context.newBottleDir.path(percentEncoded: false)) ? "yes" : "no"
        lines.append("Target folder exists: \(targetFolderExists)")
        lines.append("New bottle dir exists: \(newBottleDirExists)")
        lines.append("BottleData file: \(context.bottleDataPath)")
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
