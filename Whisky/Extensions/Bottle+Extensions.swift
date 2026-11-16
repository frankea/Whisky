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

        // Build a shell command that sources the WhiskyCmd environment.
        // Single-quoted through ShellQuoting: `.esc` backslash-escapes spaces,
        // and inside double quotes bash keeps those backslashes, so any bottle
        // name with a space reached WhiskyCmd as `QA\ Smoke` and failed to
        // resolve.
        let whiskyCmd = whiskyCmdURL.path(percentEncoded: false)
        let shellenv = ShellQuoting.commandLine([whiskyCmd, "shellenv", settings.name])
        let command = "eval \"$(\(shellenv))\""
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

    /// Rescans the bottle for installed programs and repopulates ``programs``.
    ///
    /// The expensive work — walking the `Program Files` trees and parsing each
    /// executable's PE header — runs off the main actor so switching to or
    /// opening a large bottle no longer hitches the UI. ``programsLoading`` is
    /// set for the duration so views can show a progress indicator.
    ///
    /// Concurrent callers are coalesced via ``Bottle/coalesceProgramScan(_:)``:
    /// a redundant call awaits the in-flight scan rather than dropping it, so a
    /// caller that reads ``programs`` right after (e.g. the Start Menu auto-pin)
    /// sees that scan's completed results instead of a half-populated or empty
    /// list.
    @MainActor
    func updateInstalledPrograms() async {
        await coalesceProgramScan { [self] in
            programsLoading = true
            defer { programsLoading = false }

            let driveC = url.appending(path: "drive_c")
            // Snapshot main-actor state before crossing to the background task.
            let blocklist = Set(settings.blocklist)
            let pinURLs = settings.pins.compactMap(\.url)

            // Walk Program Files, parse each PE, and classify each executable's
            // DXVK steering off the main actor (both are Sendable). Pinned
            // programs outside Program Files are read there too, so a view never
            // looks at a program's files (#372).
            let scanned: [ScannedProgram] = await Task.detached(priority: .userInitiated) {
                let found = Bottle.discoverInstalledExecutables(driveC: driveC, blocklist: blocklist)
                let foundSet = Set(found)
                return (found + pinURLs.filter { !foundSet.contains($0) }).map {
                    ScannedProgram(
                        url: $0,
                        peFile: try? PEFile(url: $0),
                        steering: DXVKSteering.inspect(executable: $0)
                    )
                }
            }.value

            var programs: [Program] = []
            var added: Set<URL> = []
            for entry in scanned where added.insert(entry.url).inserted {
                programs.append(
                    Program(url: entry.url, bottle: self, peFile: entry.peFile, dxvkSteering: entry.steering)
                )
            }

            self.programs = programs.sorted { $0.name.lowercased() < $1.name.lowercased() }
        }
    }

    /// Moves the bottle to a new location.
    ///
    /// Thin adapter over `BottleOperations.move`, which owns the
    /// rewrite-before-move and rollback-on-failure semantics for pins and
    /// blocklist URLs.
    ///
    /// - Throws: The file move's error, so the caller can tell the user.
    @MainActor
    func move(destination: URL) throws {
        try BottleOperations.move(bottleAt: url, to: destination, registry: BottleVM.shared)
    }

    /// Exports the bottle as a gzip-compressed tar archive.
    ///
    /// Thin adapter over `BottleOperations.export`.
    ///
    /// - Parameter destination: The URL where the archive should be saved.
    /// - Throws: `TarError` if the archive operation fails, or an error if the bottle is not found.
    @MainActor
    func exportAsArchive(destination: URL) async throws {
        try await BottleOperations.export(bottleAt: url, to: destination, registry: BottleVM.shared)
    }

    /// Duplicates the bottle to a new directory with the given name.
    ///
    /// Thin adapter over `BottleOperations.duplicate`.
    ///
    /// - Parameters:
    ///   - newName: The name for the duplicated bottle.
    ///   - progress: Optional callback reporting `DuplicationPhase` updates.
    /// - Returns: The URL of the newly created bottle directory.
    /// - Throws: An error if the bottle is not found or the copy operation fails.
    @MainActor
    func duplicate(
        newName: String,
        progress: (@Sendable (DuplicationPhase) -> Void)? = nil
    ) async throws -> URL {
        try await BottleOperations.duplicate(
            bottleAt: url,
            newName: newName,
            registry: BottleVM.shared,
            progress: progress
        )
    }

    /// Removes the bottle from the list, optionally deleting its files, after
    /// offering to stop any running processes.
    ///
    /// - Returns: `false` when the user cancels that prompt and nothing was
    ///   removed.
    /// - Throws: The deletion's error, so the caller can tell the user.
    @MainActor @discardableResult
    func remove(delete: Bool) async throws -> Bool {
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
            guard response == .alertFirstButtonReturn else { return false }

            Wine.killBottle(bottle: self)
            try? await Task.sleep(for: .seconds(2))
            ProcessRegistry.shared.clearRegistry(for: url)
        }

        try BottleOperations.remove(bottleAt: url, deleteFiles: delete, registry: BottleVM.shared)
        return true
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

// MARK: - BottleRegistry Conformance

/// Bridges `BottleOperations` to the app's bottle list. The `loadBottles()`
/// requirement is satisfied by the existing method on `BottleVM`.
extension BottleVM: BottleRegistry {
    var bottlePaths: [URL] {
        get { bottlesList.paths }
        set { bottlesList.paths = newValue }
    }

    func bottle(for url: URL) -> Bottle? {
        bottles.first(where: { $0.url == url })
    }
}

/// An executable as the background scan in ``Bottle/updateInstalledPrograms()``
/// read it.
private struct ScannedProgram: Sendable {
    let url: URL
    let peFile: PEFile?
    let steering: DXVKSteering?
}
