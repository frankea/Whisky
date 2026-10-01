//
//  LauncherScopingTests.swift
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

/// Captures the scopes a launch writes, in place of the `reg import` that needs Wine.
@MainActor
final class ScopeRecorder {
    private(set) var writes: [[(scope: Wine.DLLOverrideScope, overrides: String)]] = []
    private(set) var imports: [String] = []

    var writer: Wine.DLLOverrideWriter {
        { _, scopes in self.writes.append(scopes) }
    }

    var importer: Wine.RegistryImporter {
        { document, _ in self.imports.append(document) }
    }

    /// The overrides the only write gave `scope`, parsed; `nil` when there was
    /// no single write or it left `scope` out.
    func overrides(for scope: Wine.DLLOverrideScope) -> [String: String]? {
        guard writes.count == 1, let entry = writes[0].first(where: { $0.scope == scope }) else {
            return nil
        }
        return Wine.parseDLLOverrides(entry.overrides)
    }

    /// The program scopes the only write named, in order.
    var programScopes: [String] {
        guard writes.count == 1 else { return [] }
        return writes[0].compactMap { entry in
            guard case let .program(executable) = entry.scope else { return nil }
            return executable
        }
    }
}

/// The DLL override layout of a Steam launch once DXVK is scoped to the
/// launcher's processes instead of the bottle (#276). The runtime is pinned
/// in every case, so the suite answers the same on any machine.
@Suite("Launcher DLL override scoping")
@MainActor
final class LauncherScopingTests {
    private let tempRoot: URL

    init() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "launcher_scoping_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func makeBottle(_ backend: GraphicsBackend) throws -> Bottle {
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

    /// Prepares a Steam launch, `-silent` or `-applaunch`, against a pinned runtime.
    private func prepareSteam(
        _ bottle: Bottle, applaunch: Bool, plan: ProgramOverrides? = nil,
        recommended: GraphicsBackend = .d3dMetal, payload: Bool = true, recorder: ScopeRecorder
    ) async throws -> Wine.PreparedLaunch {
        try await Wine.prepareProgramLaunch(
            at: steam(in: bottle), args: applaunch ? ["-applaunch", "1174180"] : ["-silent"], bottle: bottle,
            programOverrides: plan, overridesApplyToDescendants: applaunch,
            recommendedBackend: recommended, builtinD3D12IsD3DMetal: payload,
            overrideWriter: recorder.writer, importer: recorder.importer
        )
    }

    /// The DXVK set a launcher has to draw with over D3DMetal's builtins.
    private func expectDXVK(_ overrides: [String: String]?, _ label: String) {
        #expect(overrides?["dxgi"] == "n,b", "\(label): dxgi")
        #expect(overrides?["d3d11"] == "n,b", "\(label): d3d11")
        #expect(overrides?["d3d10core"] == "n,b", "\(label): d3d10core")
    }

    /// No translation layer in the prefix default: D3DMetal's builtins serve the games.
    private func expectNoTranslationLayer(_ overrides: [String: String]?) {
        for dll in ["dxgi", "d3d9", "d3d10core", "d3d11", "d3d12"] {
            #expect(overrides?[dll] == nil, "the bottle scope must not mention \(dll)")
        }
    }

    // MARK: - Matrix row 1: recommended over D3DMetal, steam.exe -silent

    @Test("Starting Steam on a Recommended bottle keeps DXVK out of the prefix default")
    func silentLaunchScopesDXVK() async throws {
        let bottle = try makeBottle(.recommended)
        let recorder = ScopeRecorder()

        let launch = try await prepareSteam(bottle, applaunch: false, recorder: recorder)

        expectNoTranslationLayer(recorder.overrides(for: .bottle))
        expectDXVK(recorder.overrides(for: .program("steam.exe")), "steam.exe")
        expectDXVK(recorder.overrides(for: .program("steamwebhelper.exe")), "steamwebhelper.exe")
        #expect(recorder.overrides(for: .program("steamwebhelper.exe"))?["nvapi64"] == "")
        #expect(launch.environment["WINEDLLOVERRIDES"] == nil)
    }

    // MARK: - Matrix row 2: recommended, -applaunch with the client up

    @Test("A game launch keeps the helpers on DXVK and gives the game its own plan")
    func applaunchKeepsHelpersOnDXVK() async throws {
        let bottle = try makeBottle(.recommended)
        let recorder = ScopeRecorder()

        let launch = try await prepareSteam(bottle, applaunch: true, recorder: recorder)

        expectNoTranslationLayer(recorder.overrides(for: .bottle))
        // A helper restarting after this launch reads the entry written here.
        expectDXVK(recorder.overrides(for: .program("steamwebhelper.exe")), "steamwebhelper.exe")
        expectDXVK(recorder.overrides(for: .program("steamservice.exe")), "steamservice.exe")
        #expect(recorder.overrides(for: .program("steamwebhelper.exe"))?["nvapi64"] == "")
        expectDXVK(recorder.overrides(for: .program("steam.exe")), "steam.exe")
        // The game resolves the way the bottle's games do, not steered to DXVK,
        // and the environment carries no overrides for anything to inherit.
        #expect(launch.environment["WINEDLLOVERRIDES"] == nil)
    }

    // MARK: - Matrix row 3: -applaunch whose game plan says DXVK

    @Test("A game whose own plan is DXVK keeps it out of the environment and the prefix default")
    func applaunchKeepsTheGamesDXVKPlanScoped() async throws {
        let bottle = try makeBottle(.recommended)
        let recorder = ScopeRecorder()
        var plan = ProgramOverrides()
        plan.graphicsBackend = .dxvk

        let launch = try await prepareSteam(bottle, applaunch: true, plan: plan, recorder: recorder)

        expectNoTranslationLayer(recorder.overrides(for: .bottle))
        expectDXVK(recorder.overrides(for: .program("steamwebhelper.exe")), "steamwebhelper.exe")
        // The plan goes to the game's own entries (SteamGameLaunchScopingTests).
        #expect(launch.environment["WINEDLLOVERRIDES"] == nil)
    }

    // MARK: - Matrix row 4: DXVK chosen for the bottle

    @Test("A bottle set to DXVK keeps DXVK in the prefix default")
    func dxvkBottleKeepsDXVKBottleWide() async throws {
        let bottle = try makeBottle(.dxvk)
        let recorder = ScopeRecorder()

        let launch = try await prepareSteam(bottle, applaunch: false, recorder: recorder)

        expectDXVK(recorder.overrides(for: .bottle), "bottle")
        expectDXVK(recorder.overrides(for: .program("steam.exe")), "steam.exe")
        expectDXVK(recorder.overrides(for: .program("steamwebhelper.exe")), "steamwebhelper.exe")
        #expect(launch.environment["WINEDLLOVERRIDES"] == nil)
    }

    // MARK: - Matrix row 6: any bottle backend on -applaunch

    @Test("Helpers keep DXVK on a game launch whatever the bottle's own backend", arguments: [
        GraphicsBackend.recommended, .d3dMetal, .dxmt, .wined3d, .dxvk
    ])
    func helpersKeepDXVKOnAnyBackend(_ backend: GraphicsBackend) async throws {
        let bottle = try makeBottle(backend)
        bottle.settings.launcherMode = .manual
        bottle.settings.detectedLauncher = .steam
        let recorder = ScopeRecorder()

        _ = try await prepareSteam(bottle, applaunch: true, recorder: recorder)

        expectDXVK(recorder.overrides(for: .program("steamwebhelper.exe")), "steamwebhelper.exe on \(backend)")
        expectDXVK(recorder.overrides(for: .program("steam.exe")), "steam.exe on \(backend)")
    }

    // MARK: - Matrix row 7: payload-less runtime, DXMT recommended

    @Test("Without the payload, Steam's entries are DXVK and d3d12 stays loadable")
    func payloadlessRuntimeScopesDXVKWithoutD3D12() async throws {
        let bottle = try makeBottle(.recommended)
        let recorder = ScopeRecorder()

        let launch = try await prepareSteam(
            bottle, applaunch: false, recommended: .dxmt, payload: false, recorder: recorder
        )

        // The prefix default is the games', DXMT, and no part of it is DXVK's d3d9.
        let bottleScope = recorder.overrides(for: .bottle)
        #expect(bottleScope?["winemetal"] == "b")
        #expect(bottleScope?["d3d9"] == nil)
        let steamScope = recorder.overrides(for: .program("steam.exe"))
        expectDXVK(steamScope, "steam.exe")
        #expect(steamScope?["d3d9"] == "n,b")
        #expect(steamScope?["d3d12"] == nil)
        expectDXVK(recorder.overrides(for: .program("steamwebhelper.exe")), "steamwebhelper.exe")
        #expect(launch.environment["WINEDLLOVERRIDES"] == nil)
    }

    // MARK: - Matrix row 8: Rockstar's chain inside a Steam session

    @Test(
        "A Steam launch writes Rockstar's launcher and Social Club entries once Rockstar is installed",
        arguments: [false, true]
    )
    func steamLaunchWritesRockstarChain(_ applaunch: Bool) async throws {
        let bottle = try makeBottle(.recommended)
        _ = try makeExecutable("Program Files/Rockstar Games/Launcher/Launcher.exe", in: bottle)
        let recorder = ScopeRecorder()

        _ = try await prepareSteam(bottle, applaunch: applaunch, recorder: recorder)

        for executable in ["Launcher.exe", "SocialClubHelper.exe"] {
            let entry = recorder.overrides(for: .program(executable))
            expectDXVK(entry, executable)
            #expect(entry?["d3d12"] == "", "\(executable) must not reach D3DMetal's d3d12")
        }
        expectNoTranslationLayer(recorder.overrides(for: .bottle))
    }

    @Test("No Rockstar entries in a bottle without Rockstar's launcher")
    func noRockstarChainWithoutRockstar() async throws {
        let bottle = try makeBottle(.recommended)
        let recorder = ScopeRecorder()

        _ = try await prepareSteam(bottle, applaunch: false, recorder: recorder)

        #expect(!recorder.programScopes.contains("Launcher.exe"))
        #expect(!recorder.programScopes.contains("SocialClubHelper.exe"))
    }

    @Test("Launching Rockstar's launcher itself writes its entry once, from its own launch")
    func rockstarLaunchDoesNotDuplicateItsOwnEntry() async throws {
        let bottle = try makeBottle(.recommended)
        let launcher = try makeExecutable("Program Files/Rockstar Games/Launcher/Launcher.exe", in: bottle)
        let recorder = ScopeRecorder()

        _ = try await Wine.prepareProgramLaunch(
            at: launcher, bottle: bottle, recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: true,
            overrideWriter: recorder.writer, importer: recorder.importer
        )

        #expect(recorder.programScopes.filter { $0.lowercased() == "launcher.exe" }.count == 1)
        #expect(recorder.programScopes.contains("SocialClubHelper.exe"))
    }

    // MARK: - Matrix row 9: the MetalFX placeholder

    @Test("Starting Steam leaves the MetalFX placeholder its games need")
    func steamLaunchKeepsMetalFXPlaceholder() async throws {
        let bottle = try makeBottle(.recommended)
        bottle.settings.metalFX = true
        let placeholder = bottle.url.appending(path: "drive_c/windows/system32")
            .appending(path: GPTKImporter.metalFXBridgeName)
        // Builtin-marked, the kind the launch removes when it clears.
        var stub = Data(count: 0x40)
        stub.append(Data("Wine builtin DLL".utf8))
        try stub.write(to: placeholder)

        _ = try await prepareSteam(bottle, applaunch: false, recorder: ScopeRecorder())

        #expect(FileManager.default.fileExists(atPath: placeholder.path(percentEncoded: false)))
    }

    @Test("A game set to DXVK still takes the placeholder away for its launch")
    func dxvkGameStillClearsMetalFXPlaceholder() async throws {
        let bottle = try makeBottle(.recommended)
        bottle.settings.metalFX = true
        let placeholder = bottle.url.appending(path: "drive_c/windows/system32")
            .appending(path: GPTKImporter.metalFXBridgeName)
        var stub = Data(count: 0x40)
        stub.append(Data("Wine builtin DLL".utf8))
        try stub.write(to: placeholder)
        var plan = ProgramOverrides()
        plan.graphicsBackend = .dxvk

        _ = try await prepareSteam(bottle, applaunch: true, plan: plan, recorder: ScopeRecorder())

        #expect(!FileManager.default.fileExists(atPath: placeholder.path(percentEncoded: false)))
    }
}
