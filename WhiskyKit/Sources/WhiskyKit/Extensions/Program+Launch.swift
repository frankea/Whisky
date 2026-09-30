//
//  Program+Launch.swift
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

public extension Program {
    /// Launches this program the way Whisky does.
    ///
    /// Prepares the bottle for the program with its own environment, overrides
    /// and settings, the audio registry included, then runs it. Every launch of
    /// a ``Program`` in Wine goes through here, the app's and `WhiskyCmd run`'s
    /// alike, so a program behaves the same whichever of them started it.
    ///
    /// - Parameters:
    ///   - args: Arguments for the program, one word each.
    ///   - onOutput: Receives each output event of the Wine process as it arrives.
    /// - Returns: The exit code and log file of the run.
    /// - Throws: An error if the bottle cannot be prepared or the program cannot be started.
    @discardableResult
    func launch(
        args: [String], onOutput: (@MainActor (ProcessOutput) -> Void)? = nil
    ) async throws -> Wine.ProgramRunResult {
        try await Wine.runProgram(at: url, bottle: bottle, programSettings: settings, onOutput: onOutput) {
            try await prepareLaunch(args: args)
        }
    }

    /// Prepares the bottle to run this program, then returns the command that runs it.
    ///
    /// Where `generateTerminalCommand(args:)` only describes a launch, this first
    /// prepares the bottle exactly as ``launch(args:onOutput:)`` does: the audio
    /// settings, any missing CJK font aliases and the launch's DLL overrides go
    /// into the prefix registry, and the graphics backend's files into the
    /// prefix. The command then runs the program with its own overrides and
    /// settings, and clears any `WINEDLLOVERRIDES` the terminal exports, which
    /// would shadow the per-executable registry entries.
    ///
    /// - Parameter args: Arguments for the program, one word each.
    /// - Returns: The full Wine command string ready for terminal execution.
    /// - Throws: An error if the bottle cannot be prepared.
    func prepareTerminalCommand(args: [String]) async throws -> String {
        try await Wine.generateRunCommand(for: prepareLaunch(args: args))
    }
}

extension Program {
    /// Prepares the bottle for a launch of this program and returns what the launch runs.
    ///
    /// The one place a program's settings become a launch: ``launch(args:onOutput:)``
    /// runs what this returns and ``prepareTerminalCommand(args:)`` prints it, so
    /// every run mode applies the same settings.
    ///
    /// - Parameters:
    ///   - args: Arguments for the program, one word each.
    ///   - overrideWriter: What writes the DLL overrides into the prefix registry. Tests
    ///     pass a recorder, so they can see what a launch writes without running Wine.
    ///   - importer: What imports the CJK font aliases the prefix is missing. Tests pass
    ///     a recorder here too.
    /// - Returns: The environment and `wine64` arguments of the launch.
    /// - Throws: An error if the bottle cannot be prepared.
    func prepareLaunch(
        args: [String],
        overrideWriter: Wine.DLLOverrideWriter = { try await Wine.syncDLLOverrides(bottle: $0, scopes: $1) },
        importer: Wine.RegistryImporter = { try await Wine.importRegistry(document: $0, bottle: $1) }
    ) async throws -> Wine.PreparedLaunch {
        await Wine.syncAudioRegistry(bottle: bottle)
        return try await Wine.prepareProgramLaunch(
            at: url, args: args, bottle: bottle, environment: generateEnvironment(),
            programOverrides: settings.overrides, programSettings: settings,
            overrideWriter: overrideWriter, importer: importer
        )
    }
}
