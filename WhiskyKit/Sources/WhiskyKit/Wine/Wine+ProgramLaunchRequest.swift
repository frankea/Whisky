//
//  Wine+ProgramLaunchRequest.swift
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

extension Wine {
    /// What a launch asks of `prepareProgramLaunch` besides the program and its
    /// bottle: the launch parameters of `runProgram`, carried as one value so a
    /// caller's request reaches the preparation whole.
    ///
    /// Every field is required, so a parameter cannot be left behind on the way.
    struct ProgramLaunchRequest {
        /// Command-line arguments to pass to the program.
        let args: [String]
        /// Additional environment variables for this execution.
        let environment: [String: String]
        /// Per-program setting overrides. `nil` fields inherit from the bottle.
        let programOverrides: ProgramOverrides?
        /// The program's settings, which carry its diagnostic `WINEDEBUG` preset.
        let programSettings: ProgramSettings?
        /// Environment variables from the game's GameDB profile.
        let gameProfileEnvironment: [String: String]
        /// Whether the DLL overrides belong to a process this one spawns.
        let overridesApplyToDescendants: Bool
        /// The executable names of what this launch starts.
        let descendantExecutables: [String]
        /// Where the executables of what this launch starts are.
        let descendantExecutableURLs: [URL]
        /// Executables among what this launch starts that keep their own settings.
        let ownSettingsExecutables: [URL]
        /// Launchers what this launch starts brings up on its own.
        let descendantLaunchers: [LauncherType]
    }

    /// Runs a program the way the public `runProgram` does, from a request.
    ///
    /// - Parameters:
    ///   - url: The URL to the Windows executable (.exe) file.
    ///   - bottle: The ``Bottle`` in which to run the program.
    ///   - request: What the launch asks for.
    ///   - onOutput: Receives the launch's output events as they arrive.
    /// - Returns: The exit code and log file of the run.
    /// - Throws: An error if the program cannot be started or Wine encounters an error.
    @MainActor
    static func runProgram(
        at url: URL, bottle: Bottle, request: ProgramLaunchRequest,
        onOutput: (@MainActor (ProcessOutput) -> Void)?
    ) async throws -> ProgramRunResult {
        try await runProgram(at: url, bottle: bottle, programSettings: request.programSettings, onOutput: onOutput) {
            // Run... and opening a file with Whisky launch through here, so the
            // audio settings (the pinned output device among them) reach the
            // registry on these launches too.
            await syncAudioRegistry(bottle: bottle)
            return try await prepareProgramLaunch(at: url, bottle: bottle, request: request)
        }
    }

    /// Prepares a bottle for a request, as `runProgram` does before it starts the program.
    ///
    /// - Parameters:
    ///   - url: The URL to the Windows executable (.exe) file.
    ///   - bottle: The ``Bottle`` in which to run the program.
    ///   - request: What the launch asks for.
    ///   - recommendedBackend: What `.recommended` resolves to for the bottle's games.
    ///   - builtinD3D12IsD3DMetal: Whether the runtime's builtin `d3d12` is D3DMetal's.
    ///   - overrideWriter: What writes the DLL overrides into the prefix registry.
    ///   - importer: What imports the CJK font aliases the prefix is missing.
    ///   - dxvkFolder: The DXVK payload.
    ///   - dxmtFolder: The DXMT payload.
    /// - Returns: The environment and `wine64` arguments the launch runs with.
    /// - Throws: An error if a backend's files cannot be deployed or the DLL override import
    ///   cannot be started.
    @MainActor
    static func prepareProgramLaunch(
        at url: URL, bottle: Bottle, request: ProgramLaunchRequest,
        recommendedBackend: GraphicsBackend = GraphicsBackendResolver.resolve(),
        builtinD3D12IsD3DMetal: Bool = GPTKImporter.isDeployed(),
        overrideWriter: DLLOverrideWriter = { try await syncDLLOverrides(bottle: $0, scopes: $1) },
        importer: RegistryImporter = { try await importRegistry(document: $0, bottle: $1) },
        dxvkFolder: URL = Wine.dxvkFolder,
        dxmtFolder: URL = Wine.dxmtFolder
    ) async throws -> PreparedLaunch {
        try await prepareProgramLaunch(
            at: url, args: request.args, bottle: bottle, environment: request.environment,
            programOverrides: request.programOverrides, programSettings: request.programSettings,
            gameProfileEnvironment: request.gameProfileEnvironment,
            overridesApplyToDescendants: request.overridesApplyToDescendants,
            descendantExecutables: request.descendantExecutables,
            descendantExecutableURLs: request.descendantExecutableURLs,
            ownSettingsExecutables: request.ownSettingsExecutables,
            descendantLaunchers: request.descendantLaunchers,
            recommendedBackend: recommendedBackend, builtinD3D12IsD3DMetal: builtinD3D12IsD3DMetal,
            overrideWriter: overrideWriter, importer: importer,
            dxvkFolder: dxvkFolder, dxmtFolder: dxmtFolder
        )
    }
}
