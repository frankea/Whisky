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

import AppKit
import Foundation
import os.log
import WhiskyKit

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
            try? FileManager.default.removeItem(at: scriptURL)
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
                print(error)
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
                guard !settings.blocklist.contains(url) else { continue }
                foundURLS.insert(url)
                programs.append(Program(url: url, bottle: self))
            }
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
            print("Failed to move bottle")
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
    ///
    /// - Parameter newName: The name for the duplicated bottle.
    /// - Returns: The URL of the newly created bottle directory.
    /// - Throws: An error if the bottle is not found or the copy operation fails.
    @MainActor
    func duplicate(newName: String) async throws -> URL {
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
            try FileManager.default.copyItem(at: sourceURL, to: newBottleDir)
        }.value

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

        // Register the new bottle
        BottleVM.shared.bottlesList.paths.append(newBottleDir)
        BottleVM.shared.loadBottles()

        return newBottleDir
    }

    @MainActor
    func remove(delete: Bool) {
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
            print("Failed to remove bottle")
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
