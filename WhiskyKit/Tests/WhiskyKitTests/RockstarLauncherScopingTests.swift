//
//  RockstarLauncherScopingTests.swift
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

extension ScopeRecorder {
    /// Rockstar's chain as `layout` gives it: `Launcher.exe` on Wine's own
    /// Direct3D with the OpenGL renderer, from the runtime or from `system32`,
    /// or on DXVK where neither can be reached, and Social Club's Chromium
    /// helper on DXVK. Neither reaches `d3d12` or NVIDIA's bridges.
    func expectRockstarChain(layout: RockstarD3DLayout, sourceLocation: SourceLocation = #_sourceLocation) {
        let launcher = overrides(for: .program("Launcher.exe"))
        let helper = overrides(for: .program("SocialClubHelper.exe"))
        let onWineD3D = layout.usesWineDirect3D
        for dll in ["d3d10core", "d3d11", "dxgi"] {
            let expected = switch layout {
            case .builtin: "b"
            case .swapped: dll == "d3d10core" ? "b" : "n,b"
            case .degraded: "n,b"
            }
            #expect(launcher?[dll] == expected, "Launcher.exe: \(dll)", sourceLocation: sourceLocation)
            #expect(helper?[dll] == "n,b", "SocialClubHelper.exe: \(dll)", sourceLocation: sourceLocation)
        }
        for dll in ["d3d12", "nvapi", "nvapi64", "nvngx"] {
            #expect(launcher?[dll] == "", "Launcher.exe: \(dll)", sourceLocation: sourceLocation)
            #expect(helper?[dll] == "", "SocialClubHelper.exe: \(dll)", sourceLocation: sourceLocation)
        }
        let renderer = overrides(for: .direct3D("Launcher.exe"))
        #expect(renderer == (onWineD3D ? ["renderer": "gl"] : [:]), sourceLocation: sourceLocation)
    }
}

/// The entries Rockstar's own processes get (#382): `Launcher.exe` draws with
/// Direct2D on a D3D10.1 device, which only Wine's own Direct3D on its OpenGL
/// renderer makes, and `SocialClubHelper.exe` is Chromium on DXVK.
@Suite("Rockstar Games Launcher entries")
@MainActor
final class RockstarLauncherScopingTests {
    private let tempRoot: URL

    init() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "rockstar_scoping_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func makeBottle() throws -> Bottle {
        let bottleURL = tempRoot.appending(path: "Bottle")
        try FileManager.default.createDirectory(
            at: bottleURL.appending(path: "drive_c/windows/system32"), withIntermediateDirectories: true
        )
        return Bottle(bottleUrl: bottleURL)
    }

    private func makeExecutable(_ relativePath: String, in bottle: Bottle) throws -> URL {
        let url = bottle.url.appending(path: "drive_c").appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("MZ".utf8).write(to: url)
        return url
    }

    private func rockstarLauncher(in bottle: Bottle) throws -> URL {
        try makeExecutable("Program Files/Rockstar Games/Launcher/Launcher.exe", in: bottle)
    }

    private func steam(in bottle: Bottle) throws -> URL {
        try makeExecutable("Program Files (x86)/Steam/steam.exe", in: bottle)
    }

    /// Runs only the DLL override step of a Steam start, with the layout pinned.
    private func applySteamOverrides(
        _ bottle: Bottle, layout: RockstarD3DLayout, recorder: ScopeRecorder
    ) async throws {
        var environment = Wine.constructWineEnvironment(
            for: bottle, recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: true
        )
        try await Wine.applyDLLOverrides(
            for: steam(in: bottle), bottle: bottle, wineEnvironment: &environment, applyToDescendants: false,
            recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: true, rockstarLayout: layout,
            writer: recorder.writer
        )
    }

    @Test("Rockstar's chain gets these exact sets on each layout")
    func exactSetsOnEachLayout() async throws {
        let bottle = try makeBottle()
        _ = try rockstarLauncher(in: bottle)
        let chromium = "d3d10core=n,b;d3d11=n,b;d3d12=;d3d9=n,b;dxgi=n,b;nvapi=;nvapi64=;nvngx="

        let builtin = ScopeRecorder()
        try await applySteamOverrides(bottle, layout: .builtin, recorder: builtin)
        let builtinEntries = try #require(builtin.writes.first)
        #expect(builtinEntries.first { $0.scope == .program("Launcher.exe") }?.overrides
            == "d3d10core=b;d3d11=b;d3d12=;d3d9=n,b;dxgi=b;nvapi=;nvapi64=;nvngx=")
        #expect(builtinEntries.first { $0.scope == .program("SocialClubHelper.exe") }?.overrides == chromium)
        #expect(builtinEntries.first { $0.scope == .direct3D("Launcher.exe") }?.overrides == "renderer=gl")

        let degraded = ScopeRecorder()
        try await applySteamOverrides(bottle, layout: .degraded(.gptkForwarders), recorder: degraded)
        let degradedEntries = try #require(degraded.writes.first)
        #expect(degradedEntries.first { $0.scope == .program("Launcher.exe") }?.overrides == chromium)
        #expect(degradedEntries.first { $0.scope == .program("SocialClubHelper.exe") }?.overrides == chromium)
        // Asks for no renderer, which takes back one Whisky wrote before.
        #expect(degradedEntries.first { $0.scope == .direct3D("Launcher.exe") }?.overrides == "")

        // Wine's d3d11 and dxgi native from system32, d3d10core still the runtime's builtin.
        let swapped = ScopeRecorder()
        try await applySteamOverrides(
            bottle, layout: .swapped(source: URL(filePath: "/originals/d3d11.dll")), recorder: swapped
        )
        let swappedEntries = try #require(swapped.writes.first)
        #expect(swappedEntries.first { $0.scope == .program("Launcher.exe") }?.overrides
            == "d3d10core=b;d3d11=n,b;d3d12=;d3d9=n,b;dxgi=n,b;nvapi=;nvapi64=;nvngx=")
        #expect(swappedEntries.first { $0.scope == .program("SocialClubHelper.exe") }?.overrides == chromium)
        #expect(swappedEntries.first { $0.scope == .direct3D("Launcher.exe") }?.overrides == "renderer=gl")
    }

    @Test("Every degraded reason writes Launcher.exe the same set", arguments: [
        RockstarD3DLayout.Reason.disabledByUser, .sourceUnavailable("x"), .bottleUsesNativeD3D11,
        .dxvkPlanGames(["Game"]), .unservedConsumers(["EADesktop.exe"]), .swapFailed("x")
    ])
    func everyDegradedReasonWritesTheSameSet(_ reason: RockstarD3DLayout.Reason) {
        let launcherSet = "d3d10core=n,b;d3d11=n,b;d3d9=n,b;dxgi=n,b"
        #expect(Wine.rockstarChainOverrides(role: .wineDirect3D, layout: .degraded(reason), launcherSet: launcherSet)
            == Wine.rockstarChainOverrides(
                role: .wineDirect3D, layout: .degraded(.gptkForwarders), launcherSet: launcherSet
            ))
    }

    @Test("A bottle without Rockstar writes what it wrote before, and no Direct3D key")
    func noDirect3DKeyWithoutRockstar() async throws {
        let bottle = try makeBottle()
        let recorder = ScopeRecorder()

        try await applySteamOverrides(bottle, layout: .builtin, recorder: recorder)

        let entries = try #require(recorder.writes.first)
        #expect(!entries.contains { $0.scope.ownedValueNames != nil })
        #expect(recorder.programScopes == LauncherType.steam.helperExecutables + ["steam.exe"])
    }

    @Test("Rockstar's launcher from the Programs tab gets the chain's entry, not the generic launcher set")
    func directLaunchGetsTheChainEntry() async throws {
        let bottle = try makeBottle()
        let launcher = try rockstarLauncher(in: bottle)
        let recorder = ScopeRecorder()

        let launch = try await Wine.prepareProgramLaunch(
            at: launcher, bottle: bottle, recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: false,
            overrideWriter: recorder.writer, importer: recorder.importer,
            rockstarRuntime: .unavailable(in: tempRoot)
        )

        recorder.expectRockstarChain(layout: .builtin)
        #expect(recorder.programScopes.filter { $0.lowercased() == "launcher.exe" }.count == 1)
        // Nothing left in the environment to outvote the registry entry.
        #expect(launch.environment["WINEDLLOVERRIDES"] == nil)
    }

    @Test("Another program called launcher.exe keeps its own launch set in a bottle with Rockstar")
    func otherLauncherExeIsNotRockstars() async throws {
        let bottle = try makeBottle()
        _ = try rockstarLauncher(in: bottle)
        let other = try makeExecutable("Games/Other Game/launcher.exe", in: bottle)
        let recorder = ScopeRecorder()

        _ = try await Wine.prepareProgramLaunch(
            at: other, bottle: bottle, recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: false,
            overrideWriter: recorder.writer, importer: recorder.importer,
            rockstarRuntime: .unavailable(in: tempRoot)
        )

        #expect(recorder.programScopes == ["launcher.exe"])
        #expect(recorder.overrides(for: .program("launcher.exe"))?["d3d11"] != "b")
        #expect(recorder.writes.first?.contains { $0.scope.ownedValueNames != nil } == false)
        #expect(!Wine.isRockstarLauncher(other))
    }

    @Test("Only Rockstar's launcher folder and file name make a launch Rockstar's launcher", arguments: [
        // Detects as Rockstar, but a game's own Launcher.exe, not the launcher's.
        "Program Files/Rockstar Games/Red Dead Redemption 2/Launcher.exe",
        // The launcher's folder, another file.
        "Program Files/Rockstar Games/Launcher/LauncherPatcher.exe"
    ])
    func onlyTheLaunchersOwnExecutableCounts(_ relativePath: String) async throws {
        let bottle = try makeBottle()
        _ = try rockstarLauncher(in: bottle)
        let program = try makeExecutable(relativePath, in: bottle)
        let recorder = ScopeRecorder()
        #expect(LauncherType.detect(from: program) == .rockstar)

        _ = try await Wine.prepareProgramLaunch(
            at: program, bottle: bottle, recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: false,
            overrideWriter: recorder.writer, importer: recorder.importer,
            rockstarRuntime: .unavailable(in: tempRoot)
        )

        #expect(!Wine.isRockstarLauncher(program))
        // The program keeps its own launch set: none of Wine's own Direct3D.
        let own = recorder.overrides(for: .program(program.lastPathComponent))
        #expect(own != nil)
        #expect(own?["d3d11"] != "b")
        if program.lastPathComponent == "Launcher.exe" {
            // The game's Launcher.exe holds the entry, so no renderer is asked for.
            #expect(recorder.overrides(for: .direct3D("Launcher.exe")) == nil)
        }
    }

    @Test("A Launcher.exe another launcher's detection claims first is not Rockstar's")
    func detectionMustSayRockstar() {
        let url = URL(filePath: "/Bottle/drive_c/Program Files/Roberts Space Industries/RSI Launcher")
            .appending(path: "Rockstar Games/Launcher/Launcher.exe")

        #expect(LauncherType.detect(from: url) == .rsiLauncher)
        #expect(!Wine.isRockstarLauncher(url))
    }

    /// Records that Whisky wrote `renderer=gl` for `Launcher.exe` earlier.
    private func recordRenderer(in bottle: Bottle) throws {
        let key = Wine.DLLOverrideScope.direct3D("Launcher.exe").registryKey
        try DLLOverrideRecord()
            .updated(with: [OwnedRegistryValueEdit(key: key, name: "renderer", line: .set("gl"), owned: "gl")])
            .save(to: bottle.url)
    }

    @Test("Another launcher.exe from the Programs tab asks for no renderer once Whisky wrote one")
    func otherLauncherExeReleasesTheRenderer() async throws {
        let bottle = try makeBottle()
        _ = try rockstarLauncher(in: bottle)
        try recordRenderer(in: bottle)
        let other = try makeExecutable("Games/Other Game/launcher.exe", in: bottle)
        let recorder = ScopeRecorder()

        _ = try await Wine.prepareProgramLaunch(
            at: other, bottle: bottle, recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: false,
            overrideWriter: recorder.writer, importer: recorder.importer,
            rockstarRuntime: .unavailable(in: tempRoot)
        )

        let entries = try #require(recorder.writes.first)
        #expect(entries.first { $0.scope == .direct3D("Launcher.exe") }?.overrides == "")
        #expect(recorder.overrides(for: .program("launcher.exe"))?["d3d11"] != "b")
    }

    @Test("A game's own Launcher.exe in its Steam launch asks for no renderer once Whisky wrote one")
    func gamesOwnLauncherExeReleasesTheRenderer() async throws {
        let bottle = try makeBottle()
        _ = try rockstarLauncher(in: bottle)
        try recordRenderer(in: bottle)
        let recorder = ScopeRecorder()
        var environment = ["WINEDLLOVERRIDES": "d3d11=n,b;dxgi=n,b"]

        try await Wine.applyDLLOverrides(
            for: steam(in: bottle), bottle: bottle, wineEnvironment: &environment, applyToDescendants: true,
            descendantExecutables: ["Launcher.exe"], descendantLaunchers: [.rockstar],
            recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: true, rockstarLayout: .builtin,
            writer: recorder.writer
        )

        let entries = try #require(recorder.writes.first)
        #expect(entries.first { $0.scope == .program("Launcher.exe") }?.overrides == "d3d11=n,b;dxgi=n,b")
        #expect(entries.first { $0.scope == .direct3D("Launcher.exe") }?.overrides == "")
        #expect(entries.filter { $0.scope.ownedValueNames != nil }.count == 1)
    }

    @Test("A Steam launch of a Rockstar title writes each of Rockstar's chain its role's entry", arguments: [
        1_174_180, 271_590, 3_240_220, 204_100, 12_210
    ])
    func rockstarAppIdsWriteThePerRoleChain(_ appId: Int) async throws {
        let bottle = try makeBottle()
        let recorder = ScopeRecorder()
        let plan = LaunchResolver.plan(steamAppId: appId)
        #expect(LauncherType.rockstarSteamAppIds.contains(appId))

        // Without the payload, so the runtime holds Wine's own d3d11 and dxgi.
        _ = try await Wine.prepareProgramLaunch(
            at: steam(in: bottle), args: ["-applaunch", "\(appId)"], bottle: bottle,
            overridesApplyToDescendants: true, descendantExecutables: ["Game.exe"],
            descendantLaunchers: plan.startsLaunchers,
            recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: false,
            overrideWriter: recorder.writer, importer: recorder.importer,
            rockstarRuntime: .unavailable(in: tempRoot)
        )

        recorder.expectRockstarChain(layout: .builtin)
    }

    @Test("Every chain executable has a role, in the order of the list")
    func chainRolesMatchTheList() {
        for launcher in LauncherType.allCases {
            #expect(launcher.chainRoles.map(\.executable) == launcher.chainExecutables, "\(launcher)")
        }
        let roles = Dictionary(uniqueKeysWithValues: LauncherType.rockstar.chainRoles.map { ($0.executable, $0.role) })
        #expect(roles["Launcher.exe"] == .wineDirect3D)
        #expect(roles["SocialClubHelper.exe"] == .chromium)
    }
}
