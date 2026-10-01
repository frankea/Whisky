//
//  SteamGameLaunchScopingTests.swift
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

/// Where a Steam game launch puts the game's plan and Steam's own set (#276):
/// the game's plan in its executables' `AppDefaults` entries, Steam's DXVK set
/// in Steam's, and nothing in the `-applaunch` environment, so whichever
/// process starts the client lands on DXVK. The runtime is pinned in every case.
@Suite("Steam game launch scoping")
@MainActor
final class SteamGameLaunchScopingTests {
    private let tempRoot: URL
    private let games = ["PlayRDR2.exe", "RDR2.exe"]

    init() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "steam_game_scoping_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func makeBottle(_ backend: GraphicsBackend = .recommended) throws -> Bottle {
        let bottleURL = tempRoot.appending(path: "Bottle")
        try FileManager.default.createDirectory(
            at: bottleURL.appending(path: "drive_c/windows/system32"), withIntermediateDirectories: true
        )
        let bottle = Bottle(bottleUrl: bottleURL)
        bottle.settings.graphicsBackend = backend
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

    private func steam(in bottle: Bottle) throws -> URL {
        try makeExecutable("Program Files (x86)/Steam/steam.exe", in: bottle)
    }

    /// Prepares `steam.exe -applaunch` for RDR2 against a runtime with the payload.
    private func prepareGameLaunch(
        _ bottle: Bottle, plan: ProgramOverrides? = nil, launchers: [LauncherType] = [],
        recorder: ScopeRecorder
    ) async throws -> Wine.PreparedLaunch {
        try await Wine.prepareProgramLaunch(
            at: steam(in: bottle), args: ["-applaunch", "1174180"], bottle: bottle,
            programOverrides: plan, overridesApplyToDescendants: true,
            descendantExecutables: games, descendantLaunchers: launchers,
            recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: true,
            overrideWriter: recorder.writer, importer: recorder.importer
        )
    }

    private func prepareDirectLaunch(_ url: URL, _ bottle: Bottle, recorder: ScopeRecorder) async throws {
        _ = try await Wine.prepareProgramLaunch(
            at: url, bottle: bottle, recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: true,
            overrideWriter: recorder.writer, importer: recorder.importer
        )
    }

    private func expectDXVK(_ overrides: [String: String]?, _ label: String) {
        #expect(overrides?["dxgi"] == "n,b", "\(label): dxgi")
        #expect(overrides?["d3d11"] == "n,b", "\(label): d3d11")
        #expect(overrides?["d3d10core"] == "n,b", "\(label): d3d10core")
    }

    /// Steam's own processes all on DXVK, the helpers without the NVIDIA bridge.
    private func expectSteamOnDXVK(_ recorder: ScopeRecorder) {
        expectDXVK(recorder.overrides(for: .program("steam.exe")), "steam.exe")
        for helper in ["steamwebhelper.exe", "steamservice.exe", "GameOverlayUI.exe"] {
            expectDXVK(recorder.overrides(for: .program(helper)), helper)
            #expect(recorder.overrides(for: .program(helper))?["nvapi64"] == "", "\(helper): nvapi64")
        }
    }

    // MARK: - The game's plan reaches the game, Steam stays on DXVK

    @Test("A game launch puts the game's DXVK plan in the game's entries and none in the environment")
    func gamesPlanGoesToItsOwnEntries() async throws {
        let bottle = try makeBottle()
        let recorder = ScopeRecorder()
        var plan = ProgramOverrides()
        plan.graphicsBackend = .dxvk

        let launch = try await prepareGameLaunch(bottle, plan: plan, recorder: recorder)

        // Inherited by whatever the invocation starts, the client included.
        #expect(launch.environment["WINEDLLOVERRIDES"] == nil)
        for game in games {
            let entry = recorder.overrides(for: .program(game))
            expectDXVK(entry, game)
            #expect(entry?["d3d12"] == "", "\(game): DXVK's adapter must not reach D3DMetal's d3d12")
        }
        expectSteamOnDXVK(recorder)
        #expect(recorder.overrides(for: .bottle)?["d3d11"] == nil)
    }

    @Test("A game on the bottle's D3DMetal gets an entry with no translation layer, Steam keeps DXVK")
    func defaultPlanLeavesTheGameOnD3DMetal() async throws {
        let bottle = try makeBottle()
        let recorder = ScopeRecorder()

        let launch = try await prepareGameLaunch(bottle, recorder: recorder)

        #expect(launch.environment["WINEDLLOVERRIDES"] == nil)
        for game in games {
            let entry = recorder.overrides(for: .program(game))
            #expect(entry != nil, "\(game) gets its own entry")
            for dll in ["dxgi", "d3d10core", "d3d11", "d3d12"] {
                #expect(entry?[dll] == nil, "\(game): \(dll)")
            }
        }
        // A client this invocation starts reads steam.exe's entry, and inherits nothing.
        expectSteamOnDXVK(recorder)
    }

    @Test("A Programs-tab override on the game reaches the game's entry and not Steam's")
    func userGameOverridesReachTheGame() async throws {
        let bottle = try makeBottle()
        let recorder = ScopeRecorder()
        var plan = ProgramOverrides()
        plan.dllOverrides = [DLLOverrideEntry(dllName: "xinput1_3", mode: .native)]

        _ = try await prepareGameLaunch(bottle, plan: plan, recorder: recorder)

        #expect(recorder.overrides(for: .program("RDR2.exe"))?["xinput1_3"] == "n")
        #expect(recorder.overrides(for: .program("steam.exe"))?["xinput1_3"] == nil)
        #expect(recorder.overrides(for: .program("steamwebhelper.exe"))?["xinput1_3"] == nil)
    }

    @Test("Red Dead Redemption 2's own plan leaves it on D3DMetal with d3d12 loadable")
    func rdr2PlanKeepsTheGameOnD3DMetal() async throws {
        // Its GameDB entry said DXVK, meant for the Rockstar launcher. Now that
        // the plan reaches the game, DXVK would turn d3d12 off for a DX12 title.
        let bottle = try makeBottle()
        let recorder = ScopeRecorder()
        let plan = LaunchResolver.plan(steamAppId: 1_174_180)

        _ = try await prepareGameLaunch(
            bottle,
            plan: plan.overrides,
            launchers: plan.startsLaunchers,
            recorder: recorder
        )

        // Builtin is D3DMetal's: nothing disabled, nothing native in front of it.
        let entry = recorder.overrides(for: .program("RDR2.exe"))
        #expect(entry != nil)
        #expect(entry?["d3d12"] != "")
        #expect(entry?["dxgi"]?.hasPrefix("n") != true)
        #expect(entry?["d3d11"]?.hasPrefix("n") != true)
        expectDXVK(recorder.overrides(for: .program("Launcher.exe")), "Launcher.exe")
    }

    @Test("A game executable never displaces Steam's own entry")
    func steamWinsOverAGameExecutableOfTheSameName() async throws {
        let bottle = try makeBottle()
        let recorder = ScopeRecorder()

        _ = try await Wine.prepareProgramLaunch(
            at: steam(in: bottle), args: ["-applaunch", "1"], bottle: bottle,
            overridesApplyToDescendants: true, descendantExecutables: ["Game.exe", "STEAMWEBHELPER.exe"],
            recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: true,
            overrideWriter: recorder.writer, importer: recorder.importer
        )

        #expect(recorder.programScopes.filter { $0.lowercased() == "steamwebhelper.exe" }.count == 1)
        expectDXVK(recorder.overrides(for: .program("steamwebhelper.exe")), "steamwebhelper.exe")
    }

    // MARK: - The user's own steam.exe overrides (finding 5)

    @Test("Steam's entries keep the user's own steam.exe overrides on a game launch and a client start")
    func steamKeepsTheUsersOwnOverrides() async throws {
        let bottle = try makeBottle()
        let steamExe = try steam(in: bottle)
        var tuned = ProgramOverrides()
        tuned.dllOverrides = [DLLOverrideEntry(dllName: "dinput8", mode: .nativeThenBuiltin)]
        Program(url: steamExe, bottle: bottle, peFile: nil).settings.overrides = tuned

        let gameLaunch = ScopeRecorder()
        _ = try await prepareGameLaunch(bottle, recorder: gameLaunch)
        let clientStart = ScopeRecorder()
        // What SteamLauncher.startClient prepares.
        _ = try await Wine.prepareProgramLaunch(
            at: steamExe, args: ["-silent"], bottle: bottle,
            programOverrides: Program.persistedOverrides(for: steamExe, bottleURL: bottle.url),
            recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: true,
            overrideWriter: clientStart.writer, importer: clientStart.importer
        )

        let steamEntry = gameLaunch.overrides(for: .program("steam.exe"))
        #expect(steamEntry?["dinput8"] == "n,b")
        expectDXVK(steamEntry, "steam.exe")
        #expect(gameLaunch.overrides(for: .program("steamwebhelper.exe"))?["dinput8"] == "n,b")
        // Both paths write the client the same entry, so they never undo each other.
        #expect(clientStart.overrides(for: .program("steam.exe")) == steamEntry)
    }

    // MARK: - Steam's entries without Whisky starting Steam (finding 8)

    @Test("Any launch in a bottle with Steam writes Steam's own entries")
    func anyLaunchWritesSteamsEntries() async throws {
        let bottle = try makeBottle()
        _ = try steam(in: bottle)
        let game = try makeExecutable("Games/Some Game/Game.exe", in: bottle)
        let recorder = ScopeRecorder()

        try await prepareDirectLaunch(game, bottle, recorder: recorder)

        expectSteamOnDXVK(recorder)
        #expect(recorder.overrides(for: .program("Game.exe"))?["d3d11"] == nil)
        #expect(recorder.overrides(for: .bottle)?["d3d11"] == nil)
    }

    @Test("The Steam installer's launch writes steam.exe's entry before the client exists")
    func installerWritesTheClientsEntry() async throws {
        let bottle = try makeBottle()
        let installer = try makeExecutable("users/crossover/Downloads/SteamSetup.exe", in: bottle)
        let recorder = ScopeRecorder()

        try await prepareDirectLaunch(installer, bottle, recorder: recorder)

        expectSteamOnDXVK(recorder)
    }

    @Test("A bottle without Steam gets no Steam entries")
    func noSteamNoSteamEntries() async throws {
        let bottle = try makeBottle()
        let game = try makeExecutable("Games/Some Game/Game.exe", in: bottle)
        let recorder = ScopeRecorder()

        try await prepareDirectLaunch(game, bottle, recorder: recorder)

        #expect(recorder.programScopes == ["Game.exe"])
    }

    // MARK: - Rockstar titles (findings 6 and 7)

    @Test("A Rockstar title writes Rockstar's launcher entries before the launcher is installed")
    func rockstarTitleWritesTheChainUpFront() async throws {
        let bottle = try makeBottle()
        let recorder = ScopeRecorder()

        _ = try await prepareGameLaunch(bottle, launchers: [.rockstar], recorder: recorder)

        for executable in ["Launcher.exe", "SocialClubHelper.exe"] {
            let entry = recorder.overrides(for: .program(executable))
            expectDXVK(entry, executable)
            #expect(entry?["d3d12"] == "", "\(executable): d3d12")
        }
    }

    @Test("Another game writes no Launcher.exe entry while Rockstar's launcher is absent")
    func otherGamesLeaveLauncherExeAlone() async throws {
        let bottle = try makeBottle()
        let recorder = ScopeRecorder()

        _ = try await prepareGameLaunch(bottle, recorder: recorder)

        #expect(!recorder.programScopes.contains("Launcher.exe"))
        #expect(!recorder.programScopes.contains("SocialClubHelper.exe"))
    }

    @Test("A game's own Launcher.exe keeps the game's plan on that game's launch")
    func gamesOwnLauncherExeKeepsTheGamesPlan() async throws {
        let bottle = try makeBottle()
        _ = try makeExecutable("Program Files/Rockstar Games/Launcher/Launcher.exe", in: bottle)
        let recorder = ScopeRecorder()

        _ = try await Wine.prepareProgramLaunch(
            at: steam(in: bottle), args: ["-applaunch", "1"], bottle: bottle,
            overridesApplyToDescendants: true, descendantExecutables: ["Launcher.exe", "Game.exe"],
            recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: true,
            overrideWriter: recorder.writer, importer: recorder.importer
        )

        #expect(recorder.programScopes.filter { $0.lowercased() == "launcher.exe" }.count == 1)
        #expect(recorder.overrides(for: .program("Launcher.exe"))?["d3d11"] == nil)
        #expect(recorder.overrides(for: .program("SocialClubHelper.exe"))?["d3d12"] == "")
    }

    @Test("Rockstar titles are known by App ID and by GameDB publisher", arguments: [
        (1_174_180, true), (271_590, true), (3_240_220, true), (204_100, true), (12_210, true),
        (813_780, false), (1_245_620, false)
    ])
    func rockstarTitlesAreRecognised(_ appId: Int, _ rockstar: Bool) {
        let plan = LaunchResolver.plan(steamAppId: appId)
        #expect(plan.startsLaunchers == (rockstar ? [.rockstar] : []), "\(appId)")
    }

    @Test("The game executables are the install folder's plus the GameDB's, each once")
    func gameExecutablesMergeFolderAndGameDB() throws {
        let bottle = try makeBottle()
        let install = bottle.url.appending(path: "drive_c/Games/RDR2")
        _ = try makeExecutable("Games/RDR2/PlayRDR2.exe", in: bottle)
        _ = try makeExecutable("Games/RDR2/rdr2.exe", in: bottle)
        let plan = LaunchResolver.plan(steamAppId: 1_174_180)

        let names = SteamLauncher.gameExecutables(installURL: install, plan: plan)

        #expect(plan.gameExecutables == ["RDR2.exe"])
        #expect(Set(names) == ["PlayRDR2.exe", "rdr2.exe"])
        #expect(SteamLauncher.gameExecutables(installURL: nil, plan: plan) == ["RDR2.exe"])
    }
}
