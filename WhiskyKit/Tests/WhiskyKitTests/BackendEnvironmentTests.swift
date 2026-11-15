//
//  BackendEnvironmentTests.swift
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

/// The variables a setting has to set for the translation layer that is
/// actually running to read it (Dunn-Kim/Whisky).
@Suite("Backend environment variables")
struct BackendEnvironmentTests {
    /// The environment a program sees: the bottle layer with the program's
    /// overrides applied on top.
    private func environment(
        _ settings: BottleSettings, _ overrides: ProgramOverrides = ProgramOverrides(),
        programEnvironment: [String: String] = [:]
    ) -> [String: String] {
        var builder = EnvironmentBuilder()
        var dllResolver = DLLOverrideResolver(managed: [], bottleCustom: [], programCustom: [])
        _ = settings.populateBottleManagedLayer(
            builder: &builder, resolvedBackend: .d3dMetal, builtinD3D12IsD3DMetal: false
        )
        // As constructWineEnvironment does: the program's own environment
        // goes into its layer first, then its overrides.
        for (key, value) in programEnvironment {
            builder.set(key, value, layer: .programUser)
        }
        Wine.applyProgramOverrides(
            overrides, dxvkAsync: settings.dxvkAsync, programEnvironmentKeys: Set(programEnvironment.keys),
            recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: false,
            builder: &builder, dllResolver: &dllResolver
        )
        return builder.resolve().environment
    }

    // MARK: - Shader cache

    @Test("Turning the shader cache off reaches DXMT as well as DXVK", arguments: GraphicsBackend.allCases)
    func disabledShaderCacheSetsBothVariables(backend: GraphicsBackend) {
        var settings = BottleSettings()
        settings.graphicsBackend = backend
        settings.shaderCacheEnabled = false

        let env = environment(settings)
        #expect(env["DXVK_STATE_CACHE"] == "0")
        #expect(env["DXMT_SHADER_CACHE"] == "0")
    }

    @Test("The shader cache left on sets neither variable")
    func enabledShaderCacheSetsNothing() {
        var settings = BottleSettings()
        settings.graphicsBackend = .dxmt

        let env = environment(settings)
        #expect(env["DXVK_STATE_CACHE"] == nil)
        #expect(env["DXMT_SHADER_CACHE"] == nil)
    }

    @Test("A program can turn DXMT's shader cache off, or back on over the bottle")
    func programShaderCacheOverride() {
        var settings = BottleSettings()
        settings.graphicsBackend = .dxmt
        var disabled = ProgramOverrides()
        disabled.shaderCacheEnabled = false
        #expect(environment(settings, disabled)["DXMT_SHADER_CACHE"] == "0")

        settings.shaderCacheEnabled = false
        var enabled = ProgramOverrides()
        enabled.shaderCacheEnabled = true
        let env = environment(settings, enabled)
        #expect(env["DXMT_SHADER_CACHE"] == nil)
        #expect(env["DXVK_STATE_CACHE"] == nil)
    }

    @Test("A program moved onto DXMT keeps the bottle's disabled cache")
    func programMovedOntoDXMTKeepsDisabledCache() {
        var settings = BottleSettings()
        settings.graphicsBackend = .dxvk
        settings.shaderCacheEnabled = false
        var overrides = ProgramOverrides()
        overrides.graphicsBackend = .dxmt

        #expect(environment(settings, overrides)["DXMT_SHADER_CACHE"] == "0")
    }

    // MARK: - Metal capture

    @Test("Metal trace sets the documented capture variable and the older one")
    func metalTraceSetsBothCaptureVariables() {
        var settings = BottleSettings()
        settings.metalTrace = true
        let env = environment(settings)
        #expect(env["MTL_CAPTURE_ENABLED"] == "1")
        #expect(env["METAL_CAPTURE_ENABLED"] == "1")

        settings.metalTrace = false
        #expect(environment(settings)["MTL_CAPTURE_ENABLED"] == nil)
    }

    @Test("DXMT is told the launched executable, without its extension")
    func captureNamesTheLaunchedExecutable() {
        let url = URL(filePath: "/Bottle/drive_c/Games/Game/Game.EXE")
        #expect(Wine.dxmtCaptureExecutable(for: url, descendantExecutables: nil) == "Game")
        #expect(Wine.dxmtCaptureExecutable(for: URL(filePath: "/B/tool.com"), descendantExecutables: nil) == "tool.com")
    }

    @Test("On a Steam launch DXMT is told the game, not steam.exe, once it is the only candidate")
    func captureNamesTheGameOnApplaunch() {
        let steam = URL(filePath: "/Bottle/drive_c/Program Files (x86)/Steam/steam.exe")
        func named(_ executables: [String]) -> String? {
            Wine.dxmtCaptureExecutable(for: steam, descendantExecutables: executables)
        }
        #expect(named(["UnityCrashHandler64.exe", "Game.exe"]) == "Game")
        #expect(named(["unins000.exe", "Game.exe", "GameLauncher.exe", "CrashReportClient.exe"]) == "Game")
        #expect(named(["Game.exe", "game.exe"]) == "Game", "the scan and the GameDB name the same file")
        #expect(named(["Game.exe", "Editor.exe"]) == nil, "no guess between two games")
        #expect(named(["UnityCrashHandler64.exe"]) == nil)
        #expect(named([]) == nil)
    }

    @Test("A Steam launch's install scan with two root executables names the game, whatever the order")
    func captureNamesTheGameFromAnInstallScan() throws {
        let install = FileManager.default.temporaryDirectory.appending(path: "capture_scan_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: install, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: install) }
        for name in ["UnityCrashHandler64.exe", "Game.exe"] {
            try Data("MZ".utf8).write(to: install.appending(path: name))
        }
        let steam = URL(filePath: "/Bottle/drive_c/Program Files (x86)/Steam/steam.exe")

        let plan = LaunchPlan(overrides: ProgramOverrides(), gameProfileEnvironment: [:], provenance: [])
        let scanned = SteamLauncher.gameExecutables(installURL: install, plan: plan)
        #expect(Set(scanned) == ["UnityCrashHandler64.exe", "Game.exe"])
        for order in [scanned, scanned.reversed()] {
            #expect(Wine.dxmtCaptureExecutable(for: steam, descendantExecutables: order) == "Game")
        }
    }

    @Test("The executable is named only for DXMT with Metal trace on, and never over the user's value")
    func captureIsNamedOnlyWhenItApplies() {
        let url = URL(filePath: "/Bottle/drive_c/Games/Game/Game.exe")
        func named(_ backend: GraphicsBackend, trace: Bool, env: [String: String] = [:]) -> String? {
            var environment = env
            Wine.nameDXMTCaptureExecutable(
                in: &environment, backend: backend, metalTrace: trace, url: url, descendantExecutables: nil
            )
            return environment["DXMT_CAPTURE_EXECUTABLE"]
        }
        #expect(named(.dxmt, trace: true) == "Game")
        #expect(named(.dxmt, trace: false) == nil)
        #expect(named(.dxvk, trace: true) == nil)
        #expect(named(.d3dMetal, trace: true) == nil)
        #expect(named(.dxmt, trace: true, env: ["DXMT_CAPTURE_EXECUTABLE": "Launcher"]) == "Launcher")
    }

    // MARK: - Shader compilation under DXVK

    private static let concurrentCompile = "MVK_CONFIG_SHOULD_MAXIMIZE_CONCURRENT_COMPILATION"

    @Test("A DXVK bottle compiles Metal shaders concurrently, and no other backend sets it")
    func dxvkBottleCompilesConcurrently() {
        var settings = BottleSettings()
        settings.graphicsBackend = .dxvk
        #expect(environment(settings)[Self.concurrentCompile] == "1")

        for backend in [GraphicsBackend.d3dMetal, .dxmt, .wined3d] {
            settings.graphicsBackend = backend
            #expect(environment(settings)[Self.concurrentCompile] == nil, "\(backend)")
        }
    }

    @Test(
        "A program moved onto DXVK gets the bottle's DXVK compile settings",
        arguments: [(true, false), (false, false), (true, true)]
    )
    func programMovedOntoDXVKGetsCompileSettings(dxvkAsync: Bool, legacyFlag: Bool) {
        var settings = BottleSettings()
        settings.graphicsBackend = .dxmt
        settings.dxvkAsync = dxvkAsync
        var overrides = ProgramOverrides()
        if legacyFlag {
            overrides.dxvk = true
        } else {
            overrides.graphicsBackend = .dxvk
        }

        let env = environment(settings, overrides)
        #expect(env["DXVK_ASYNC"] == (dxvkAsync ? "1" : nil))
        #expect(env[Self.concurrentCompile] == "1")
    }

    @Test("A program's own async setting still beats the bottle's")
    func programAsyncOverrideWins() {
        var settings = BottleSettings()
        settings.graphicsBackend = .d3dMetal
        var overrides = ProgramOverrides()
        overrides.graphicsBackend = .dxvk
        overrides.dxvkAsync = false

        #expect(environment(settings, overrides)["DXVK_ASYNC"] == "0")
    }

    @Test("A program's own environment values for the DXVK compile settings are kept", arguments: [false, true])
    func programEnvironmentBeatsDXVKCompileSettings(legacyFlag: Bool) {
        var settings = BottleSettings()
        settings.graphicsBackend = .d3dMetal
        var overrides = ProgramOverrides()
        if legacyFlag {
            overrides.dxvk = true
        } else {
            overrides.graphicsBackend = .dxvk
        }
        let own = ["DXVK_ASYNC": "0", Self.concurrentCompile: "0"]

        let env = environment(settings, overrides, programEnvironment: own)
        #expect(env["DXVK_ASYNC"] == "0")
        #expect(env[Self.concurrentCompile] == "0")
    }

    @Test("A launch keeps a program's own DXVK_ASYNC=0 when its override moves it onto DXVK")
    @MainActor
    func launchEnvironmentKeepsProgramAsync() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "backend_env_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        let bottle = Bottle(bottleUrl: url, inFlight: false, isAvailable: true)
        bottle.settings.graphicsBackend = .d3dMetal
        var overrides = ProgramOverrides()
        overrides.graphicsBackend = .dxvk

        let env = Wine.constructWineEnvironment(
            for: bottle, environment: ["DXVK_ASYNC": "0"], programOverrides: overrides,
            recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: false
        )
        #expect(env["DXVK_ASYNC"] == "0")
        #expect(env[Self.concurrentCompile] == "1")
    }

    @Test("A program moved off DXVK keeps its own compile setting")
    func programMovedOffDXVKKeepsOwnCompileSetting() {
        var settings = BottleSettings()
        settings.graphicsBackend = .dxvk
        var overrides = ProgramOverrides()
        overrides.graphicsBackend = .dxmt

        let env = environment(settings, overrides, programEnvironment: [Self.concurrentCompile: "0"])
        #expect(env[Self.concurrentCompile] == "0")
    }

    @Test("A program moved off DXVK loses the compile setting with DXVK_ASYNC", arguments: [
        GraphicsBackend.d3dMetal, .dxmt
    ])
    func programMovedOffDXVKLosesCompileSettings(backend: GraphicsBackend) {
        var settings = BottleSettings()
        settings.graphicsBackend = .dxvk
        var overrides = ProgramOverrides()
        overrides.graphicsBackend = backend

        let env = environment(settings, overrides)
        #expect(env["DXVK_ASYNC"] == nil)
        #expect(env[Self.concurrentCompile] == nil)
    }
}
