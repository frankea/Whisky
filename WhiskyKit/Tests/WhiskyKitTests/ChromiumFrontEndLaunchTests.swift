//
//  ChromiumFrontEndLaunchTests.swift
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

/// What a launch writes for 3DMark's front end (#372): DXVK's set in its own
/// entry under Recommended, on a direct launch, on a Steam launch, and ahead
/// of time, while its benchmarks and the bottle keep the games' backend.
/// The runtime is pinned to D3DMetal unless a test says otherwise.
@Suite("Chromium front end launches")
@MainActor
final class ChromiumFrontEndLaunchTests {
    let tempRoot: URL
    let bottleURL: URL
    let dxvkFolder: URL

    init() throws {
        tempRoot = FileManager.default.temporaryDirectory.appending(path: "chromium_front_end_\(UUID().uuidString)")
        bottleURL = tempRoot.appending(path: "Bottle")
        dxvkFolder = tempRoot.appending(path: "DXVK")
        // The prefix holds the builtin's files, which a DXVK deploy replaces.
        try touch(
            ["windows/system32/d3d11.dll", "windows/syswow64/d3d11.dll"],
            in: bottleURL.appending(path: "drive_c")
        )
        for arch in ["x64", "x32"] {
            let folder = dxvkFolder.appending(path: arch)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("DXVK".utf8).write(to: folder.appending(path: "d3d11.dll"))
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func touch(_ paths: [String], in base: URL) throws {
        for relative in paths {
            let url = base.appending(path: relative)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("MZ".utf8).write(to: url)
        }
    }

    func makeBottle(_ backend: GraphicsBackend = .recommended) -> Bottle {
        let bottle = Bottle(bottleUrl: bottleURL)
        bottle.settings.graphicsBackend = backend
        return bottle
    }

    var steamExe: URL {
        bottleURL.appending(path: "drive_c/Program Files (x86)/Steam/steam.exe")
    }

    /// Steam with 3DMark in its own library, the Steam layout of the row.
    func installSteam3DMark() throws -> URL {
        try touch(["Program Files (x86)/Steam/steam.exe"], in: bottleURL.appending(path: "drive_c"))
        let install = bottleURL.appending(path: "drive_c/Program Files (x86)/Steam/steamapps/common/3DMark")
        try touch(
            ["bin/x64/3DMark.exe", "bin/x64/libcef.dll", "bin/x64/workloads/TimeSpy.exe", "3DMarkDemo.exe"],
            in: install
        )
        return install
    }

    var dxvkDeployed: Bool {
        let dll = bottleURL.appending(path: "drive_c/windows/system32/d3d11.dll")
        return (try? Data(contentsOf: dll)) == Data("DXVK".utf8)
    }

    func expectDXVK(_ overrides: [String: String]?, _ label: String) {
        #expect(overrides?["dxgi"] == "n,b", "\(label): dxgi")
        #expect(overrides?["d3d11"] == "n,b", "\(label): d3d11")
        #expect(overrides?["d3d10core"] == "n,b", "\(label): d3d10core")
    }

    func expectNotDXVK(_ overrides: [String: String]?, _ label: String) {
        #expect(overrides?["d3d11"] != "n,b", "\(label): d3d11")
    }

    func prepare(
        _ url: URL, in bottle: Bottle, programOverrides: ProgramOverrides? = nil,
        recommendedBackend: GraphicsBackend = .d3dMetal, recorder: ScopeRecorder
    ) async throws -> Wine.PreparedLaunch {
        try await Wine.prepareProgramLaunch(
            at: url, bottle: bottle, programOverrides: programOverrides,
            recommendedBackend: recommendedBackend, builtinD3D12IsD3DMetal: recommendedBackend == .d3dMetal,
            overrideWriter: recorder.writer, importer: recorder.importer, dxvkFolder: dxvkFolder
        )
    }

    func backend(_ backend: GraphicsBackend) -> ProgramOverrides {
        var overrides = ProgramOverrides()
        overrides.graphicsBackend = backend
        return overrides
    }

    // MARK: - Direct launch

    @Test("Launched on Recommended, 3DMark gets DXVK in its own entry and the bottle keeps D3DMetal")
    func directLaunchSteersTheFrontEnd() async throws {
        let install = try installSteam3DMark()
        let bottle = makeBottle()
        let recorder = ScopeRecorder()

        let launch = try await prepare(install.appending(path: "bin/x64/3DMark.exe"), in: bottle, recorder: recorder)

        expectDXVK(recorder.overrides(for: .program("3DMark.exe")), "3DMark.exe")
        #expect(recorder.overrides(for: .program("3DMark.exe"))?["nvapi64"] == nil, "nvapi stays reachable")
        let bottleScope = recorder.overrides(for: .bottle)
        #expect(bottleScope != nil)
        expectNotDXVK(bottleScope, "the bottle scope")
        #expect(launch.environment["WINEDLLOVERRIDES"] == nil)
        #expect(dxvkDeployed, "DXVK's files are copied in for the front end")
        #expect(bottle.settings.graphicsBackend == .recommended)
    }

    @Test("A program set to D3DMetal keeps D3DMetal")
    func explicitProgramBackendWins() async throws {
        let install = try installSteam3DMark()
        let bottle = makeBottle()
        let recorder = ScopeRecorder()

        _ = try await prepare(
            install.appending(path: "bin/x64/3DMark.exe"), in: bottle,
            programOverrides: backend(.d3dMetal), recorder: recorder
        )

        let entry = recorder.overrides(for: .program("3DMark.exe"))
        #expect(entry != nil)
        expectNotDXVK(entry, "3DMark.exe")
        #expect(!dxvkDeployed)
    }

    @Test("A bottle set to D3DMetal is not steered")
    func explicitBottleBackendIsNotSteered() async throws {
        let install = try installSteam3DMark()
        let bottle = makeBottle(.d3dMetal)
        let recorder = ScopeRecorder()

        _ = try await prepare(install.appending(path: "bin/x64/3DMark.exe"), in: bottle, recorder: recorder)

        expectNotDXVK(recorder.overrides(for: .program("3DMark.exe")), "3DMark.exe")
        #expect(!dxvkDeployed)
    }

    @Test("Overrides meant for a descendant leave the front end unsteered")
    func descendantOverridesAreNotSteered() async throws {
        let install = try installSteam3DMark()
        let bottle = makeBottle()
        let recorder = ScopeRecorder()

        _ = try await Wine.prepareProgramLaunch(
            at: install.appending(path: "bin/x64/3DMark.exe"), bottle: bottle, overridesApplyToDescendants: true,
            recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: true,
            overrideWriter: recorder.writer, importer: recorder.importer, dxvkFolder: dxvkFolder
        )

        #expect(!dxvkDeployed)
    }

    // MARK: - Steam launch

    /// What SteamLauncher.launch hands Wine for `-applaunch 223850`.
    func steamLaunch(_ bottle: Bottle, install: URL, recorder: ScopeRecorder) async throws {
        let scan = SteamLibrary.scanExecutables(under: install)
        let plan = LaunchResolver.plan(
            steamAppId: 223_850,
            userOverrides: SteamLauncher.userOverrides(forExecutables: scan.planExecutables, bottle: bottle),
            appliedConfiguration: nil, entries: []
        )
        _ = try await Wine.prepareProgramLaunch(
            at: steamExe, args: ["-applaunch", "223850"], bottle: bottle,
            programOverrides: plan.overrides, overridesApplyToDescendants: true,
            descendantExecutables: SteamLauncher.gameExecutables(scanned: scan.planExecutables, plan: plan),
            ownSettingsExecutables: scan.ownSettingsExecutables,
            recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: true,
            overrideWriter: recorder.writer, importer: recorder.importer, dxvkFolder: dxvkFolder
        )
    }

    @Test("On a Steam launch the front end gets DXVK and the workloads keep the game's plan")
    func steamLaunchSteersOnlyTheFrontEnd() async throws {
        let install = try installSteam3DMark()
        let bottle = makeBottle()
        let recorder = ScopeRecorder()

        try await steamLaunch(bottle, install: install, recorder: recorder)

        expectDXVK(recorder.overrides(for: .program("3DMark.exe")), "3DMark.exe")
        for workload in ["TimeSpy.exe", "3DMarkDemo.exe"] {
            let entry = recorder.overrides(for: .program(workload))
            #expect(entry != nil, "\(workload) gets the plan")
            expectNotDXVK(entry, workload)
        }
    }

    @Test("A front end's own DXVK override stays on the front end and never becomes the plan")
    func frontEndOverrideIsNotThePlan() async throws {
        let install = try installSteam3DMark()
        let bottle = makeBottle()
        Program(url: install.appending(path: "bin/x64/3DMark.exe"), bottle: bottle, peFile: nil)
            .settings.overrides = backend(.dxvk)
        let recorder = ScopeRecorder()

        try await steamLaunch(bottle, install: install, recorder: recorder)

        #expect(SteamLauncher.userOverrides(forInstallURL: install, bottle: bottle) == nil)
        expectDXVK(recorder.overrides(for: .program("3DMark.exe")), "3DMark.exe")
        expectNotDXVK(recorder.overrides(for: .program("TimeSpy.exe")), "TimeSpy.exe")
    }

    @Test("A front end set to D3DMetal keeps its own choice on a Steam launch")
    func frontEndExplicitBackendIsKept() async throws {
        let install = try installSteam3DMark()
        let bottle = makeBottle()
        Program(url: install.appending(path: "bin/x64/3DMark.exe"), bottle: bottle, peFile: nil)
            .settings.overrides = backend(.d3dMetal)
        let recorder = ScopeRecorder()

        try await steamLaunch(bottle, install: install, recorder: recorder)

        let entry = recorder.overrides(for: .program("3DMark.exe"))
        #expect(entry != nil, "its own settings are written")
        expectNotDXVK(entry, "3DMark.exe")
    }

    // MARK: - Ahead of time

    @Test("Any launch in a bottle with 3DMark installed writes its entry ahead of time, registry only")
    func aheadOfTimeEntry() async throws {
        _ = try installSteam3DMark()
        let notepad = bottleURL.appending(path: "drive_c/windows/notepad.exe")
        try touch(["windows/notepad.exe"], in: bottleURL.appending(path: "drive_c"))
        let recorder = ScopeRecorder()

        _ = try await prepare(notepad, in: makeBottle(), recorder: recorder)

        expectDXVK(recorder.overrides(for: .program("3DMark.exe")), "3DMark.exe")
        expectNotDXVK(recorder.overrides(for: .program("notepad.exe")), "notepad.exe")
        #expect(!dxvkDeployed, "the entry never deploys DXVK")
    }

    @Test("The standalone install's location counts too")
    func aheadOfTimeStandalone() async throws {
        try touch(
            ["Program Files/UL/3DMark/3DMark.exe", "windows/notepad.exe"],
            in: bottleURL.appending(path: "drive_c")
        )
        let recorder = ScopeRecorder()

        _ = try await prepare(
            bottleURL.appending(path: "drive_c/windows/notepad.exe"), in: makeBottle(), recorder: recorder
        )

        expectDXVK(recorder.overrides(for: .program("3DMark.exe")), "3DMark.exe")
    }

    @Test("No entry without 3DMark, on an explicit bottle, or when the games already resolve to DXVK")
    func aheadOfTimeIsGated() async throws {
        try touch(["windows/notepad.exe"], in: bottleURL.appending(path: "drive_c"))
        let notepad = bottleURL.appending(path: "drive_c/windows/notepad.exe")

        let without = ScopeRecorder()
        _ = try await prepare(notepad, in: makeBottle(), recorder: without)
        #expect(!without.programScopes.contains("3DMark.exe"))

        _ = try installSteam3DMark()
        let explicit = ScopeRecorder()
        _ = try await prepare(notepad, in: makeBottle(.d3dMetal), recorder: explicit)
        #expect(!explicit.programScopes.contains("3DMark.exe"))

        let onDXVK = ScopeRecorder()
        _ = try await prepare(notepad, in: makeBottle(), recommendedBackend: .dxvk, recorder: onDXVK)
        #expect(!onDXVK.programScopes.contains("3DMark.exe"))
    }

    // MARK: - Embedded CEF

    @Test("A game with embedded CEF gets no DXVK set for any of its executables")
    func embeddedCEFKeepsTheGamesBackend() async throws {
        try touch(["Program Files (x86)/Steam/steam.exe"], in: bottleURL.appending(path: "drive_c"))
        let install = bottleURL.appending(path: "drive_c/Program Files (x86)/Steam/steamapps/common/Game")
        try touch([
            "Game.exe",
            "Game/Binaries/Win64/Game-Win64-Shipping.exe",
            "Engine/Binaries/ThirdParty/CEF3/Win64/libcef.dll",
            "Engine/Binaries/Win64/UnrealCEFSubProcess.exe"
        ], in: install)
        let bottle = makeBottle()
        let scan = SteamLibrary.scanExecutables(under: install)
        let recorder = ScopeRecorder()

        _ = try await Wine.prepareProgramLaunch(
            at: steamExe, args: ["-applaunch", "1"], bottle: bottle, overridesApplyToDescendants: true,
            descendantExecutables: SteamLauncher.gameExecutables(
                scanned: scan.planExecutables,
                plan: LaunchPlan(overrides: ProgramOverrides(), gameProfileEnvironment: [:], provenance: [])
            ),
            ownSettingsExecutables: scan.ownSettingsExecutables,
            recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: true,
            overrideWriter: recorder.writer, importer: recorder.importer, dxvkFolder: dxvkFolder
        )

        for game in ["Game.exe", "Game-Win64-Shipping.exe"] {
            let entry = recorder.overrides(for: .program(game))
            #expect(entry != nil, "\(game) gets the plan")
            expectNotDXVK(entry, game)
        }
        #expect(!recorder.programScopes.contains("UnrealCEFSubProcess.exe"))
    }
}
