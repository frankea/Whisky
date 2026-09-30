//
//  ProgramLaunchPreparationTests.swift
//  WhiskyKitTests
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
import Testing
@testable import WhiskyKit

/// Captures what a launch would write to the prefix registry, in place of the
/// `reg import` that needs Wine.
@MainActor
private final class RegistryRecorder {
    private(set) var writes: [[(scope: Wine.DLLOverrideScope, overrides: String)]] = []

    var writer: Wine.DLLOverrideWriter {
        { _, scopes in self.writes.append(scopes) }
    }

    /// The overrides the only write gave `scope`, parsed; `nil` when there was
    /// no single write or it left `scope` out.
    func overrides(for scope: Wine.DLLOverrideScope) -> [String: String]? {
        guard writes.count == 1, let entry = writes[0].first(where: { $0.scope == scope }) else {
            return nil
        }
        return Wine.parseDLLOverrides(entry.overrides)
    }
}

@Suite("Program launch preparation")
@MainActor
final class ProgramLaunchPreparationTests {
    private let tempRoot: URL

    init() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "launch_prep_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    /// A DXVK bottle with a custom `d2d1=n,b` override, the setup from #266.
    private func makeBottle() throws -> Bottle {
        let bottleURL = tempRoot.appending(path: "Bottle")
        try FileManager.default.createDirectory(
            at: bottleURL.appending(path: "drive_c"), withIntermediateDirectories: true
        )
        let bottle = Bottle(bottleUrl: bottleURL)
        bottle.settings.graphicsBackend = .dxvk
        bottle.settings.dllOverrides = [DLLOverrideEntry(dllName: "d2d1", mode: .nativeThenBuiltin)]
        return bottle
    }

    private func makeExecutable(_ relativePath: String, in bottle: Bottle) throws -> URL {
        let url = bottle.url.appending(path: "drive_c").appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("MZ".utf8).write(to: url)
        return url
    }

    /// A program that disables the DLL its bottle loads natively: the
    /// conflicting bottle and per-executable setting from #266.
    private func makeConflictingProgram(in bottle: Bottle) throws -> Program {
        let program = try Program(url: makeExecutable("Games/Aegis/Game.exe", in: bottle), bottle: bottle)
        var overrides = ProgramOverrides()
        overrides.dllOverrides = [DLLOverrideEntry(dllName: "d2d1", mode: .disabled)]
        program.settings.overrides = overrides
        program.settings.environment = ["PROGRAM_SETTING": "kept"]
        return program
    }

    /// Runs `launch`'s printed command through `sh` in a terminal that exports
    /// `inherited`, with a stub standing in for `wine64` that prints the
    /// environment it was started with.
    private func environmentOfPrintedCommand(
        for launch: Wine.PreparedLaunch, inherited: [String: String]
    ) throws -> [String: String] {
        let stub = tempRoot.appending(path: "wine64")
        try "#!/bin/sh\nexec /usr/bin/env\n".write(to: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)

        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", Wine.generateRunCommand(for: launch, wineBinary: stub)]
        process.environment = inherited.merging(["PATH": "/usr/bin:/bin"]) { _, path in path }
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        var environment: [String: String] = [:]
        for line in (String(bytes: data, encoding: .utf8) ?? "").split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 {
                environment[String(parts[0])] = String(parts[1])
            }
        }
        return environment
    }

    @Test("Every run mode gets the program's DLL overrides from the registry, not the environment")
    func launchWritesOverridesToTheRegistry() async throws {
        let bottle = try makeBottle()
        let program = try makeConflictingProgram(in: bottle)
        let recorder = RegistryRecorder()
        #expect(AudioRegistryState.load(from: bottle.url) == nil)

        let launch = try await program.prepareLaunch(args: ["-windowed"], overrideWriter: recorder.writer)

        // The audio settings are synced too. Factory settings only stamp the
        // marker, so no Wine runs here.
        #expect(AudioRegistryState.load(from: bottle.url) == .factoryDefault)
        // In the environment, the variable would shadow every per-executable
        // registry entry for the launched program and everything it spawns.
        #expect(launch.environment["WINEDLLOVERRIDES"] == nil)
        #expect(launch.environment["PROGRAM_SETTING"] == "kept")
        #expect(launch.arguments == ["start", "/unix", program.url.path(percentEncoded: false), "-windowed"])

        #expect(recorder.writes.count == 1)
        #expect(recorder.overrides(for: .bottle)?["d2d1"] == "n,b")
        #expect(recorder.overrides(for: .bottle)?["d3d11"] == "n,b")
        // The program's own override wins in its AppDefaults entry, next to
        // the bottle's DXVK set.
        #expect(recorder.overrides(for: .program("Game.exe"))?["d2d1"] == "")
        #expect(recorder.overrides(for: .program("Game.exe"))?["d3d11"] == "n,b")
    }

    @Test("Every run mode carries the program's diagnostic WINEDEBUG preset")
    func launchCarriesProgramSettings() async throws {
        let bottle = try makeBottle()
        let program = try makeConflictingProgram(in: bottle)
        program.settings.activeWineDebugPreset = .dllLoad

        let launch = try await program.prepareLaunch(args: [], overrideWriter: RegistryRecorder().writer)

        #expect(launch.environment["WINEDEBUG"] == WineDebugPreset.dllLoad.winedebugValue)
    }

    @Test("A printed command runs the prepared launch")
    func printedCommandRunsThePreparedLaunch() async throws {
        let bottle = try makeBottle()
        let program = try makeConflictingProgram(in: bottle)
        program.settings.activeWineDebugPreset = .dllLoad

        let command = try await Wine.generateRunCommand(
            for: program.prepareLaunch(args: ["-windowed"], overrideWriter: RegistryRecorder().writer)
        )

        #expect(!command.contains("WINEDLLOVERRIDES="))
        #expect(command.contains("PROGRAM_SETTING=kept"))
        #expect(command.contains("WINEDEBUG=\(WineDebugPreset.dllLoad.winedebugValue.esc)"))
        #expect(command.hasSuffix(
            "env -u WINEDLLOVERRIDES \(Wine.wineBinary.esc) start /unix \(program.url.esc) -windowed"
        ))
    }

    @Test("Overrides meant for a descendant stay in the environment and off the launcher's entry")
    func descendantOverridesStayInTheEnvironment() async throws {
        let bottle = try makeBottle()
        let steam = try makeExecutable("Program Files (x86)/Steam/steam.exe", in: bottle)
        let recorder = RegistryRecorder()

        let launch = try await Wine.prepareProgramLaunch(
            at: steam, args: ["-applaunch", "1174180"], bottle: bottle,
            overridesApplyToDescendants: true, overrideWriter: recorder.writer
        )

        #expect(launch.environment["WINEDLLOVERRIDES"] != nil)
        #expect(launch.arguments == ["start", "/unix", steam.path(percentEncoded: false), "-applaunch", "1174180"])
        #expect(recorder.overrides(for: .program("steam.exe")) == nil)
        #expect(recorder.overrides(for: .program("steamwebhelper.exe"))?["nvapi64"] == "")
    }

    @Test("A program set to a virtual desktop is prepared to run in one")
    func virtualDesktopArguments() async throws {
        let bottle = try makeBottle()
        let program = try Program(url: makeExecutable("Games/My Game.exe", in: bottle), bottle: bottle)
        var overrides = ProgramOverrides()
        overrides.virtualDesktopEnabled = true
        overrides.resolutionPreset = .r1280x720

        let launch = try await Wine.prepareProgramLaunch(
            at: program.url, args: ["-x"], bottle: bottle, programOverrides: overrides,
            overrideWriter: RegistryRecorder().writer
        )

        #expect(launch.arguments == [
            "explorer", "/desktop=My_Game.exe,1280x720", program.url.path(percentEncoded: false), "-x"
        ])
    }

    @Test("A prepared launch prints exactly as prepared, without rebuilding its environment")
    func preparedLaunchPrintsVerbatim() {
        let launch = Wine.PreparedLaunch(
            environment: ["WINEPREFIX": "/tmp/My Bottle", "DXVK_HUD": "fps"],
            arguments: ["start", "/unix", "/tmp/My Bottle/drive_c/Game.exe", "--name", "Player One"]
        )

        let command = Wine.generateRunCommand(for: launch)

        #expect(command.contains(#"WINEPREFIX=/tmp/My\ Bottle "#))
        #expect(command.contains("DXVK_HUD=fps "))
        #expect(!command.contains("WINEDLLOVERRIDES="))
        #expect(command.hasSuffix(
            "env -u WINEDLLOVERRIDES \(Wine.wineBinary.esc) "
                + #"start /unix /tmp/My\ Bottle/drive_c/Game.exe --name Player\ One"#
        ))
    }

    @Test("A printed command runs Wine without the WINEDLLOVERRIDES its terminal exports")
    func printedCommandClearsInheritedOverrides() throws {
        let launch = Wine.PreparedLaunch(
            environment: ["WINEPREFIX": "/tmp/My Bottle"],
            arguments: ["start", "/unix", "/tmp/My Bottle/drive_c/Game.exe"]
        )

        // What `WhiskyCmd shellenv` and Open in Terminal export: the bottle's
        // set, which would shadow the entries preparation wrote for the program.
        let environment = try environmentOfPrintedCommand(
            for: launch, inherited: ["WINEDLLOVERRIDES": "d2d1=n,b;d3d11=n,b", "KEPT": "yes"]
        )

        #expect(environment["WINEDLLOVERRIDES"] == nil)
        #expect(environment["WINEPREFIX"] == "/tmp/My Bottle")
        #expect(environment["KEPT"] == "yes")
    }

    @Test("A printed command sets the overrides a launch keeps for a descendant over the terminal's")
    func printedCommandSetsDescendantOverrides() throws {
        let launch = Wine.PreparedLaunch(
            environment: ["WINEPREFIX": "/tmp/My Bottle", "WINEDLLOVERRIDES": "d3d11=n,b;nvapi64="],
            arguments: ["start", "/unix", "/tmp/My Bottle/drive_c/steam.exe", "-applaunch", "1174180"]
        )

        let command = Wine.generateRunCommand(for: launch)
        let environment = try environmentOfPrintedCommand(
            for: launch, inherited: ["WINEDLLOVERRIDES": "d2d1=n,b"]
        )

        #expect(!command.contains("env -u"))
        #expect(environment["WINEDLLOVERRIDES"] == "d3d11=n,b;nvapi64=")
    }
}
