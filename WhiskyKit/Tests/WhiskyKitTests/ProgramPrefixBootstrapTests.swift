//
//  ProgramPrefixBootstrapTests.swift
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

@Suite("Program prefix bootstrap and terminal runs")
@MainActor
final class ProgramPrefixBootstrapTests {
    private let tempRoot: URL

    init() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "prefix_bootstrap_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    /// A DXVK bottle whose program disables a DLL the bottle loads natively,
    /// so a launch has per-executable overrides to write.
    private func makeProgram(bootstrapped: Bool) throws -> Program {
        let bottleURL = tempRoot.appending(path: "Bottle")
        try FileManager.default.createDirectory(
            at: bottleURL.appending(path: bootstrapped ? "drive_c/windows/system32" : "drive_c"),
            withIntermediateDirectories: true
        )
        let bottle = Bottle(bottleUrl: bottleURL)
        bottle.settings.graphicsBackend = .dxvk
        bottle.settings.dllOverrides = [DLLOverrideEntry(dllName: "d2d1", mode: .nativeThenBuiltin)]

        let exe = bottleURL.appending(path: "drive_c/Games/Game.exe")
        try FileManager.default.createDirectory(at: exe.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("MZ".utf8).write(to: exe)
        let program = Program(url: exe, bottle: bottle)
        var overrides = ProgramOverrides()
        overrides.dllOverrides = [DLLOverrideEntry(dllName: "d2d1", mode: .disabled)]
        program.settings.overrides = overrides
        return program
    }

    @Test("A launch creates a missing Wine prefix before it writes anything into it")
    func launchBootstrapsAMissingPrefix() async throws {
        let program = try makeProgram(bootstrapped: false)
        var events: [String] = []
        let bootstrapper: Wine.PrefixBootstrapper = { bottle in
            events.append("bootstrap")
            try FileManager.default.createDirectory(
                at: bottle.url.appending(path: "drive_c/windows/system32"), withIntermediateDirectories: true
            )
        }

        // What both `WhiskyCmd run` and `run --command` go through.
        _ = try await program.prepareLaunch(
            args: [], overrideWriter: { _, _ in events.append("overrides") }, bootstrapper: bootstrapper
        )

        #expect(events == ["bootstrap", "overrides"])
        #expect(Wine.isPrefixBootstrapped(program.bottle))
    }

    @Test("A launch leaves an existing Wine prefix alone")
    func launchKeepsAnExistingPrefix() async throws {
        let program = try makeProgram(bootstrapped: true)
        var bootstraps = 0

        _ = try await program.prepareLaunch(
            args: [],
            overrideWriter: { _, _ in },
            bootstrapper: { _ in bootstraps += 1 }
        )

        #expect(bootstraps == 0)
    }

    @Test("A launch stops with a prefix error when the prefix is still missing after bootstrapping")
    func launchStopsWhenBootstrapLeavesNoPrefix() async throws {
        let program = try makeProgram(bootstrapped: false)
        var writes = 0

        await #expect(throws: WinePrefixBootstrapError.incomplete) {
            _ = try await program.prepareLaunch(
                args: [],
                overrideWriter: { _, _ in writes += 1 },
                bootstrapper: { _ in }
            )
        }
        // Nothing is written into the prefix that isn't there.
        #expect(writes == 0)
    }

    @Test("Run in Terminal prepares the bottle before it writes the command")
    func terminalScriptIsPrepared() async throws {
        let program = try makeProgram(bootstrapped: true)
        var writes: [[(scope: Wine.DLLOverrideScope, overrides: String)]] = []

        let script = try await program.writeTerminalScript(
            args: ["-windowed"], overrideWriter: { _, scopes in writes.append(scopes) }, bootstrapper: { _ in }
        )
        defer { try? FileManager.default.removeItem(at: script) }

        // The program's overrides went into the registry, where the printed
        // command's `env -u WINEDLLOVERRIDES` leaves them in charge.
        #expect(writes.count == 1)
        #expect(writes.first?.contains { $0.scope == .program("Game.exe") } == true)
        let contents = try String(contentsOf: script, encoding: .utf8)
        #expect(contents.hasPrefix("#!/bin/bash\n"))
        #expect(contents.contains(
            "env -u WINEDLLOVERRIDES \(Wine.wineBinary.esc) start /unix \(program.url.esc) -windowed"
        ))
        let permissions = try FileManager.default.attributesOfItem(atPath: script.path)[.posixPermissions] as? Int
        #expect(permissions == 0o755)
    }

    @Test("Run in Terminal creates a missing Wine prefix first")
    func terminalScriptBootstrapsTheBottle() async throws {
        let program = try makeProgram(bootstrapped: false)
        var bootstraps = 0

        let script = try await program.writeTerminalScript(
            args: [], overrideWriter: { _, _ in }, bootstrapper: { bottle in
                bootstraps += 1
                try FileManager.default.createDirectory(
                    at: bottle.url.appending(path: "drive_c/windows/system32"), withIntermediateDirectories: true
                )
            }
        )
        defer { try? FileManager.default.removeItem(at: script) }

        #expect(bootstraps == 1)
    }

    @Test("Run in Terminal writes no script when the bottle can't be prepared")
    func terminalScriptFailsWithoutPrefix() async throws {
        let program = try makeProgram(bootstrapped: false)

        await #expect(throws: WinePrefixBootstrapError.incomplete) {
            _ = try await program.writeTerminalScript(args: [], overrideWriter: { _, _ in }, bootstrapper: { _ in })
        }
    }
}
