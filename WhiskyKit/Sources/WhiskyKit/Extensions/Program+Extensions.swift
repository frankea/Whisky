//
//  Program+Extensions.swift
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

public extension Program {
    func run() {
        if NSEvent.modifierFlags.contains(.shift) {
            self.runInTerminal()
        } else {
            self.runInWine()
        }
    }

    /// Launches the program respecting user's modifier key preference and returns the result.
    /// - Parameter useTerminal: Whether to launch in Terminal mode (e.g., Shift was held).
    ///   **Important:** Capture `NSEvent.modifierFlags.contains(.shift)` synchronously at the call site,
    ///   before entering any async context, to avoid race conditions with key state.
    /// - Returns: LaunchResult indicating success, terminal launch, or failure
    @MainActor
    func launchWithUserMode(useTerminal: Bool) async -> LaunchResult {
        // Check for terminal mode (typically shift-click)
        if useTerminal {
            self.runInTerminal()
            return .launchedInTerminal(programName: self.name)
        }

        // Normal Wine launch with program-specific settings
        let arguments = settings.arguments.split { $0.isWhitespace }.map(String.init)
        let environment = generateEnvironment()

        do {
            try await Wine.runProgram(
                at: self.url, args: arguments, bottle: self.bottle, environment: environment
            )
            return .launchedSuccessfully(programName: self.name)
        } catch {
            return .launchFailed(programName: self.name, errorDescription: error.localizedDescription)
        }
    }

    func generateTerminalCommand() -> String {
        Wine.generateRunCommand(
            at: self.url, bottle: bottle, args: settings.arguments, environment: generateEnvironment()
        )
    }

    func runInTerminal() {
        // Write command to a temp script file to avoid AppleScript string length limits
        // and complex escaping issues with very long Wine commands
        let command = generateTerminalCommand()
        let scriptContent = "#!/bin/bash\n\(command)\n"

        let tempDir = FileManager.default.temporaryDirectory
        let scriptURL = tempDir.appendingPathComponent("whisky-run-\(UUID().uuidString).sh")

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

        // Use the user's preferred terminal application
        let terminal = TerminalApp.preferred
        let appleScript = terminal.generateAppleScript(for: scriptURL.path)

        Task {
            var error: NSDictionary?
            guard let script = NSAppleScript(source: appleScript) else { return }
            script.executeAndReturnError(&error)

            if let error {
                Logger.wineKit.error("Failed to run terminal script \(error)")
                guard let description = error["NSAppleScriptErrorMessage"] as? String else { return }
                self.showRunError(message: String(describing: description))
            }

            // Clean up temp script after a delay to ensure the terminal has read it
            try? await Task.sleep(for: .seconds(5))
            try? FileManager.default.removeItem(at: scriptURL)
        }
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

extension Program {
    func runInWine() {
        let arguments = settings.arguments.split { $0.isWhitespace }.map(String.init)
        let environment = generateEnvironment()

        Task {
            do {
                try await Wine.runProgram(
                    at: self.url, args: arguments, bottle: self.bottle, environment: environment
                )
            } catch {
                self.showRunError(message: error.localizedDescription)
            }
        }
    }
}
