//
//  Bottle+Extensions.swift
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

// swiftlint:disable file_length
import AppKit
import Foundation
import os.log
import WhiskyKit

/// Phases reported during bottle duplication for progress feedback.
enum DuplicationPhase: Equatable {
    /// Calculating total size of the source bottle directory.
    case calculatingSize
    /// Copying files. `bytesCopied` and `totalBytes` track progress.
    case copying(bytesCopied: Int64, totalBytes: Int64)
    /// Rewriting metadata (pins, blocklist) for the new bottle.
    case updatingMetadata
    /// Registering the new bottle and reloading the bottle list.
    case finalizing
}

/// Returns a duplicate name following the Finder convention.
///
/// - If no existing bottle is named "\(baseName) Copy", returns "\(baseName) Copy".
/// - Otherwise tries "\(baseName) Copy 2", "Copy 3", etc.
///
/// - Parameters:
///   - baseName: The original bottle's name.
///   - existingNames: Names of all current bottles.
/// - Returns: The next available duplicate name.
func nextDuplicateName(baseName: String, existingNames: [String]) -> String {
    let candidate = "\(baseName) Copy"
    if !existingNames.contains(candidate) {
        return candidate
    }
    var counter = 2
    while existingNames.contains("\(baseName) Copy \(counter)") {
        counter += 1
    }
    return "\(baseName) Copy \(counter)"
}

/// MainActor-isolated cache for Wine usernames to avoid repeated filesystem scans.
@MainActor
private var wineUsernameCache: [URL: String] = [:]

extension Bottle {
    /// The detected Wine username for this bottle.
    ///
    /// Wine creates user profile directories in `drive_c/users/`. This property
    /// scans that directory to find the actual username used by Wine, which may
    /// differ from the default "crossover" depending on the Wine build or
    /// how the bottle was created.
    ///
    /// The result is cached to avoid repeated filesystem operations.
    ///
    /// - Returns: The detected username, or "crossover" as a fallback.
    @MainActor
    var wineUsername: String {
        if let cached = wineUsernameCache[url] {
            return cached
        }
        let usersDir = url.appending(path: "drive_c").appending(path: "users")
        let username = WinePrefixValidation.detectWineUsername(in: usersDir) ?? "crossover"
        wineUsernameCache[url] = username
        return username
    }

    /// Clears the cached Wine username for this bottle.
    ///
    /// Call this after operations that may change the username (e.g., prefix repair).
    @MainActor
    func clearWineUsernameCache() {
        wineUsernameCache.removeValue(forKey: url)
    }

    func openCDrive() {
        NSWorkspace.shared.open(url.appending(path: "drive_c"))
    }

    func openTerminal() {
        guard let whiskyCmdURL = Bundle.main.url(forResource: "WhiskyCmd", withExtension: nil) else { return }

        // Build a shell command that sources the WhiskyCmd environment
        // Use .esc to escape shell metacharacters and prevent command injection
        let command = "eval \"$(\"\(whiskyCmdURL.esc)\" shellenv \"\(settings.name.esc)\")\""
        let scriptContent = "#!/bin/bash\n\(command)\n"

        // Write to temp script file to handle all terminal apps consistently
        let tempDir = FileManager.default.temporaryDirectory
        let scriptURL = tempDir.appendingPathComponent("whisky-env-\(UUID().uuidString).sh")

        do {
            try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: scriptURL.path
            )
        } catch {
            Logger.wineKit.error("Failed to write terminal script: \(error)")
            return
        }

        // Register temp script for tracking and cleanup
        TempFileTracker.shared.register(file: scriptURL)

        let terminal = TerminalApp.preferred
        let appleScriptSource = terminal.generateAppleScript(for: scriptURL.path)

        Task.detached(priority: .userInitiated) {
            var error: NSDictionary?
            guard let appleScript = NSAppleScript(source: appleScriptSource) else { return }
            appleScript.executeAndReturnError(&error)

            if let error {
                Logger.wineKit.error("Failed to run terminal script \(error)")
                guard let description = error["NSAppleScriptErrorMessage"] as? String else { return }
                await self.showRunError(message: String(describing: description))
            }

            // Clean up temp script after a delay to ensure the terminal has read it
            try? await Task.sleep(for: .seconds(5))
            await TempFileTracker.shared.cleanupWithRetry(file: scriptURL)
        }
    }

    @discardableResult
    // swiftlint:disable:next function_body_length
    func getStartMenuPrograms() -> [Program] {
        let globalStartMenu = url
            .appending(path: "drive_c")
            .appending(path: "ProgramData")
            .appending(path: "Microsoft")
            .appending(path: "Windows")
            .appending(path: "Start Menu")

        let userStartMenu = url
            .appending(path: "drive_c")
            .appending(path: "users")
            .appending(path: wineUsername)
            .appending(path: "AppData")
            .appending(path: "Roaming")
            .appending(path: "Microsoft")
            .appending(path: "Windows")
            .appending(path: "Start Menu")

        var startMenuPrograms: [Program] = []
        var linkURLs: [URL] = []
        let globalEnumerator = FileManager.default.enumerator(
            at: globalStartMenu,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        while let url = globalEnumerator?.nextObject() as? URL {
            if url.pathExtension == "lnk" {
                linkURLs.append(url)
            }
        }

        let userEnumerator = FileManager.default.enumerator(
            at: userStartMenu,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        while let url = userEnumerator?.nextObject() as? URL {
            if url.pathExtension == "lnk" {
                linkURLs.append(url)
            }
        }

        linkURLs.sort(by: { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() })

        for link in linkURLs {
            do {
                if let program = try ShellLinkHeader.getProgram(
                    url: link,
                    handle: FileHandle(forReadingFrom: link),
                    bottle: self
                ) {
                    if !startMenuPrograms.contains(where: { $0.url == program.url }) {
                        startMenuPrograms.append(program)
                        try FileManager.default.removeItem(at: link)
                    }
                }
            } catch {
                Logger.wineKit.warning("Failed to process Start Menu shortcut: \(error.localizedDescription)")
            }
        }

        return startMenuPrograms
    }

    func updateInstalledPrograms() {
        let driveC = url.appending(path: "drive_c")
        var programs: [Program] = []
        var foundURLS: Set<URL> = []

        for folderName in ["Program Files", "Program Files (x86)"] {
            let folderURL = driveC.appending(path: folderName)
            let enumerator = FileManager.default.enumerator(
                at: folderURL, includingPropertiesForKeys: [.isExecutableKey], options: [.skipsHiddenFiles]
            )

            while let url = enumerator?.nextObject() as? URL {
                guard !url.hasDirectoryPath, url.pathExtension == "exe" else { continue }
                // Skip ClickOnce cache executables (noisy internal artifacts)
                guard !url.path.contains("/Apps/2.0/") else { continue }
                guard !settings.blocklist.contains(url) else { continue }
                foundURLS.insert(url)
                programs.append(Program(url: url, bottle: self))
            }
        }

        // Detect ClickOnce applications
        let clickOnceApps = ClickOnceManager.shared.detectAppRefFile(in: self, wineUsername: wineUsername)
        for appRefURL in clickOnceApps {
            let displayName = ClickOnceManager.shared.displayName(for: appRefURL)
            let program = Program(appRefURL: appRefURL, bottle: self, displayName: displayName)
            programs.append(program)
        }

        // Add missing programs from pins
        for pin in settings.pins {
            guard let url = pin.url else { continue }
            guard !foundURLS.contains(url) else { continue }
            programs.append(Program(url: url, bottle: self))
        }

        self.programs = programs.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    @MainActor
    func move(destination: URL) {
        do {
            if let bottle = BottleVM.shared.bottles.first(where: { $0.url == url }) {
                bottle.inFlight = true
                for index in 0 ..< bottle.settings.pins.count {
                    let pin = bottle.settings.pins[index]
                    if let url = pin.url {
                        bottle.settings.pins[index].url = url.updateParentBottle(
                            old: url,
                            new: destination
                        )
                    }
                }

                for index in 0 ..< bottle.settings.blocklist.count {
                    let blockedUrl = bottle.settings.blocklist[index]
                    bottle.settings.blocklist[index] = blockedUrl.updateParentBottle(
                        old: url,
                        new: destination
                    )
                }
            }
            try FileManager.default.moveItem(at: url, to: destination)
            if let path = BottleVM.shared.bottlesList.paths.firstIndex(of: url) {
                BottleVM.shared.bottlesList.paths[path] = destination
            }
            BottleVM.shared.loadBottles()
        } catch {
            Logger.wineKit.error("Failed to move bottle: \(error.localizedDescription)")
        }
    }

    /// Exports the bottle as a gzip-compressed tar archive.
    ///
    /// This operation runs on a background thread to avoid blocking the UI.
    /// The bottle's `inFlight` property is set during the operation to show progress.
    ///
    /// - Parameter destination: The URL where the archive should be saved.
    /// - Throws: `TarError` if the archive operation fails, or an error if the bottle is not found.
    @MainActor
    func exportAsArchive(destination: URL) async throws {
        guard let bottle = BottleVM.shared.bottles.first(where: { $0.url == url }) else {
            throw NSError(
                domain: "com.franke.Whisky",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Bottle not found"]
            )
        }
        bottle.inFlight = true
        defer { bottle.inFlight = false }

        // Capture URL before entering detached task to satisfy actor isolation
        let sourceURL = url
        try await Task.detached(priority: .userInitiated) {
            try Tar.tar(folder: sourceURL, toURL: destination)
        }.value
    }

    /// Duplicates the bottle to a new directory with the given name.
    ///
    /// This operation runs on a background thread to avoid blocking the UI.
    /// The bottle's `inFlight` property is set during the operation to show progress.
    /// An optional progress callback reports duplication phases for UI feedback.
    ///
    /// On copy failure the partially created directory is removed before re-throwing.
    /// Transient artifacts (old logs, diagnosis history) are excluded from the clone.
    ///
    /// - Parameters:
    ///   - newName: The name for the duplicated bottle.
    ///   - progress: Optional callback reporting ``DuplicationPhase`` updates.
    /// - Returns: The URL of the newly created bottle directory.
    /// - Throws: An error if the bottle is not found or the copy operation fails.
    @MainActor
    func duplicate(
        newName: String,
        progress: (@Sendable (DuplicationPhase) -> Void)? = nil
    ) async throws -> URL {
        guard let bottle = BottleVM.shared.bottles.first(where: { $0.url == url }) else {
            throw NSError(
                domain: "com.franke.Whisky",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Bottle not found"]
            )
        }
        bottle.inFlight = true
        defer { bottle.inFlight = false }

        // Create new bottle directory in the same parent folder
        let parentDir = url.deletingLastPathComponent()
        let newBottleDir = parentDir.appendingPathComponent(UUID().uuidString)

        // Capture URLs before entering detached task to satisfy actor isolation
        let sourceURL = url
        try await Task.detached(priority: .userInitiated) {
            // Phase: calculate size
            progress?(.calculatingSize)
            let totalBytes = Self.calculateDirectorySize(at: sourceURL)

            // Phase: copying
            progress?(.copying(bytesCopied: 0, totalBytes: totalBytes))
            do {
                try FileManager.default.copyItem(at: sourceURL, to: newBottleDir)
            } catch {
                // Clean up partial clone on failure
                try? FileManager.default.removeItem(at: newBottleDir)
                throw error
            }
            progress?(.copying(bytesCopied: totalBytes, totalBytes: totalBytes))

            // Remove transient artifacts from the clone
            Self.removeTransientArtifacts(in: newBottleDir)
        }.value

        // Phase: updating metadata
        progress?(.updatingMetadata)

        // Update the new bottle's settings
        let newBottle = Bottle(bottleUrl: newBottleDir)
        newBottle.settings.name = newName

        // Update pin URLs to point to the new bottle
        for index in 0 ..< newBottle.settings.pins.count {
            if let pinURL = newBottle.settings.pins[index].url {
                newBottle.settings.pins[index].url = pinURL.updateParentBottle(
                    old: sourceURL,
                    new: newBottleDir
                )
            }
        }

        // Update blocklist URLs to point to the new bottle
        for index in 0 ..< newBottle.settings.blocklist.count {
            newBottle.settings.blocklist[index] = newBottle.settings.blocklist[index]
                .updateParentBottle(old: sourceURL, new: newBottleDir)
        }

        // Explicitly save settings to ensure all modifications are persisted
        // (modifying nested struct properties may not always trigger didSet)
        newBottle.saveBottleSettings()

        // Phase: finalizing
        progress?(.finalizing)

        // Register the new bottle
        BottleVM.shared.bottlesList.paths.append(newBottleDir)
        BottleVM.shared.loadBottles()

        return newBottleDir
    }

    /// Calculates the total allocated size of a directory tree.
    nonisolated private static func calculateDirectorySize(at url: URL) -> Int64 {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey]),
               let size = values.totalFileAllocatedSize {
                total += Int64(size)
            }
        }
        return total
    }

    /// Removes transient artifacts from a cloned bottle directory.
    ///
    /// Deletes old log files, diagnosis history sidecars, and temp files so the
    /// duplicate starts clean.
    nonisolated private static func removeTransientArtifacts(in bottleDir: URL) {
        let fileManager = FileManager.default

        // Remove .log files from the logs directory
        let logsDir = bottleDir.appending(path: "logs")
        if let logEnumerator = fileManager.enumerator(
            at: logsDir,
            includingPropertiesForKeys: nil,
            options: [.skipsSubdirectoryDescendants]
        ) {
            for case let fileURL as URL in logEnumerator where fileURL.pathExtension == "log" {
                try? fileManager.removeItem(at: fileURL)
            }
        }

        // Remove diagnosis history sidecar files
        if let enumerator = fileManager.enumerator(
            at: bottleDir,
            includingPropertiesForKeys: nil,
            options: []
        ) {
            for case let fileURL as URL in enumerator
                where fileURL.lastPathComponent.hasSuffix(".diagnosis-history.plist") {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }

    @MainActor
    func remove(delete: Bool) async {
        // Check for running processes before deletion
        let isRunning = await Wine.isWineserverRunning(for: self)
        let trackedCount = ProcessRegistry.shared.getProcessCount(for: self)

        if isRunning || trackedCount > 0 {
            let alert = NSAlert()
            alert.messageText = String(localized: "bottle.remove.hasProcesses.title")
            alert.informativeText = String(localized: "bottle.remove.hasProcesses.message")
            alert.alertStyle = .warning
            let stopAndRemove = alert.addButton(
                withTitle: String(localized: "bottle.remove.hasProcesses.stopAndRemove")
            )
            stopAndRemove.hasDestructiveAction = true
            alert.addButton(withTitle: String(localized: "bottle.remove.hasProcesses.cancel"))

            let response = alert.runModal()
            guard response == .alertFirstButtonReturn else { return }

            Wine.killBottle(bottle: self)
            try? await Task.sleep(for: .seconds(2))
            ProcessRegistry.shared.clearRegistry(for: url)
        }

        do {
            if let bottle = BottleVM.shared.bottles.first(where: { $0.url == url }) {
                bottle.inFlight = true
            }

            if delete {
                try FileManager.default.removeItem(at: url)
            }

            if let path = BottleVM.shared.bottlesList.paths.firstIndex(of: url) {
                BottleVM.shared.bottlesList.paths.remove(at: path)
            }
            BottleVM.shared.loadBottles()
        } catch {
            Logger.wineKit.error("Failed to remove bottle: \(error.localizedDescription)")
        }
    }

    @MainActor
    func rename(newName: String) {
        settings.name = newName
    }

    @MainActor private func showRunError(message: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "alert.message")
        alert.informativeText = String(localized: "alert.info")
            + " \(self.url.lastPathComponent): "
            + message
        alert.alertStyle = .critical
        alert.addButton(withTitle: String(localized: "button.ok"))
        alert.runModal()
    }
}
