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
    /// Brings the bottle's audio registry in line with its settings, then runs
    /// the program with its own environment, overrides and settings. The app's
    /// launches and `WhiskyCmd run` go through here, so a program behaves the
    /// same whichever of them started it.
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
        await Wine.syncAudioRegistry(bottle: bottle)
        return try await Wine.runProgram(
            at: url, args: args, bottle: bottle, environment: generateEnvironment(),
            programOverrides: settings.overrides, programSettings: settings,
            onOutput: onOutput
        )
    }

    /// Prepares the bottle to run this program, then returns the command that runs it.
    ///
    /// Where `generateTerminalCommand(args:)` only describes a launch, this first
    /// prepares the bottle the way ``launch(args:onOutput:)`` does: the audio
    /// settings and the launch's DLL overrides go into the prefix registry, and
    /// the graphics backend's files into the prefix. The command then carries no
    /// `WINEDLLOVERRIDES` to shadow per-executable registry entries, and runs the
    /// program the way Whisky would, with its own overrides and settings.
    ///
    /// - Parameter args: Arguments for the program, one word each.
    /// - Returns: The full Wine command string ready for terminal execution.
    /// - Throws: An error if the bottle cannot be prepared.
    func prepareTerminalCommand(args: [String]) async throws -> String {
        try await prepareTerminalCommand(
            args: args, overrideWriter: { try await Wine.syncDLLOverrides(bottle: $0, scopes: $1) }
        )
    }
}

extension Program {
    /// Prepares the terminal command with the registry write injected, so tests
    /// can see what preparing the bottle writes without running Wine.
    func prepareTerminalCommand(
        args: [String], overrideWriter: Wine.DLLOverrideWriter
    ) async throws -> String {
        await Wine.syncAudioRegistry(bottle: bottle)
        let launch = try await Wine.prepareProgramLaunch(
            at: url, args: args, bottle: bottle, environment: generateEnvironment(),
            programOverrides: settings.overrides, programSettings: settings,
            overrideWriter: overrideWriter
        )
        return Wine.generateRunCommand(for: launch)
    }
}
