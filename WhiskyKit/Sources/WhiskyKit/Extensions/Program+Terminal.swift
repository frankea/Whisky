//
//  Program+Terminal.swift
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

import AppKit
import Foundation
import os.log

/// An error opening a program in the user's terminal.
public struct TerminalLaunchError: LocalizedError, Equatable {
    /// What went wrong, as the terminal or AppleScript reported it.
    public let message: String

    public var errorDescription: String? {
        message
    }
}

public extension Program {
    /// Runs this program in the user's terminal, reporting a failure in an alert.
    ///
    /// The shift-click Run. The bottle is prepared the way a launch prepares it
    /// before the terminal opens, so this returns at once and the work happens
    /// in a task.
    func runInTerminal() {
        Task {
            do {
                try await openInTerminal()
            } catch {
                showRunError(message: error.localizedDescription)
            }
        }
    }

    /// Prepares the bottle for this program, then opens the user's terminal running it.
    ///
    /// The command is the one `WhiskyCmd run --command` prints: the prefix is
    /// created if missing, and the DLL overrides, backend files and CJK font
    /// aliases a launch needs are in place before the terminal starts it. The
    /// program's saved arguments are split on whitespace, as a launch splits them.
    ///
    /// - Throws: An error if the bottle cannot be prepared, the script cannot be
    ///   written, or the terminal cannot be opened.
    func openInTerminal() async throws {
        let arguments = settings.arguments.split { $0.isWhitespace }.map(String.init)
        let scriptURL = try await writeTerminalScript(args: arguments)

        // Give the terminal time to read the script before it goes away,
        // whichever way opening it turns out.
        defer {
            Task {
                try? await Task.sleep(for: .seconds(5))
                await TempFileTracker.shared.cleanupWithRetry(file: scriptURL)
            }
        }

        let appleScript = TerminalApp.preferred.generateAppleScript(for: scriptURL.path)
        guard let script = NSAppleScript(source: appleScript) else {
            throw TerminalLaunchError(message: String(
                localized: "program.terminal.error.scriptInvalid",
                defaultValue: "The command to open the terminal couldn't be prepared."
            ))
        }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            Logger.wineKit.error("Failed to run terminal script \(error)")
            let description = error["NSAppleScriptErrorMessage"] as? String
            throw TerminalLaunchError(message: description ?? String(describing: error))
        }
    }
}

extension Program {
    /// Prepares the bottle for this program and writes a script that runs it.
    ///
    /// The command goes through a script file rather than the AppleScript
    /// itself, which avoids AppleScript's string limits and escaping for long
    /// Wine commands.
    ///
    /// - Parameters:
    ///   - args: Arguments for the program, one word each.
    ///   - overrideWriter: What writes the DLL overrides into the prefix registry.
    ///   - importer: What imports the CJK font aliases the prefix is missing.
    ///   - bootstrapper: What creates the Wine prefix when the bottle has none yet.
    /// - Returns: The executable script, registered for cleanup.
    /// - Throws: An error if the bottle cannot be prepared or the script cannot be written.
    func writeTerminalScript(
        args: [String],
        overrideWriter: Wine.DLLOverrideWriter = { try await Wine.syncDLLOverrides(bottle: $0, scopes: $1) },
        importer: Wine.RegistryImporter = { try await Wine.importRegistry(document: $0, bottle: $1) },
        bootstrapper: Wine.PrefixBootstrapper = { try await Wine.bootstrapPrefix(bottle: $0) }
    ) async throws -> URL {
        let launch = try await prepareLaunch(
            args: args, overrideWriter: overrideWriter, importer: importer, bootstrapper: bootstrapper
        )
        let command = Wine.generateRunCommand(for: launch)

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisky-run-\(UUID().uuidString).sh")
        try "#!/bin/bash\n\(command)\n".write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        TempFileTracker.shared.register(file: scriptURL)
        return scriptURL
    }
}
