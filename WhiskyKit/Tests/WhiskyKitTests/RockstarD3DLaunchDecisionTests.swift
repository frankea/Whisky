//
//  RockstarD3DLaunchDecisionTests.swift
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
import Testing
@testable import WhiskyKit

/// Which launches keep the Rockstar swap, which suspend it, and how the
/// bottle's consumers make a Steam start refuse it or take it back (#382).
@Suite("Rockstar Direct3D swap launch decisions")
@MainActor
final class RockstarD3DLaunchDecisionTests {
    private let fixture: RockstarD3DFixture
    private let root: URL

    init() throws {
        fixture = try RockstarD3DFixture(prefix: "rockstar_decisions")
        root = fixture.root
        try fixture.installRockstar(socialClub: false)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    private var swapped: RockstarD3DLayout {
        .swapped(source: fixture.d3d11Source)
    }

    private var system32HoldsDXVK: Bool {
        RockstarD3DFixture.contents(fixture.system32("d3d11.dll")) == RockstarD3DFixture.dxvkBytes("x64", "d3d11.dll")
    }

    private func deploy(_ url: URL) throws -> RockstarD3DLayout? {
        try Wine.deployDXVK(bottle: fixture.bottle, from: fixture.dxvk, rockstar: fixture.launch(url))
    }

    /// Nothing of the swap left: DXVK in `system32`, no copy, no record.
    private func expectNoSwap(sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(system32HoldsDXVK, sourceLocation: sourceLocation)
        let folders = (RockstarD3DFixture.steamCopyKeys + [RockstarD3DFixture.socialClubKey]).map {
            fixture.driveC.appending(path: $0)
        }
        #expect(folders.allSatisfy(RockstarD3DFixture.holdsNoCopies), sourceLocation: sourceLocation)
        #expect(!RockstarD3DLayoutRecord.exists(in: fixture.bottle.url), sourceLocation: sourceLocation)
    }

    // MARK: - Launches that keep the layout

    private var launcherPatcher: URL {
        fixture.rockstarLauncher.deletingLastPathComponent().appending(path: "LauncherPatcher.exe")
    }

    @Test("Rockstar's updater keeps the swap, so the Launcher.exe it starts still finds Wine's d3d11")
    func launcherPatcherKeepsTheLayout() throws {
        try fixture.write(PEBuilder.createMinimalPE32Plus(), to: launcherPatcher)
        try fixture.startSteam()

        #expect(try deploy(launcherPatcher) == swapped)

        #expect(Wine.isStrippedCopy(fixture.system32("d3d11.dll"), of: fixture.d3d11Source))
    }

    @Test("Rockstar's updater from the Programs tab writes Launcher.exe the swapped set")
    func launcherPatcherWritesTheSwappedChain() async throws {
        try fixture.write(PEBuilder.createMinimalPE32Plus(), to: launcherPatcher)
        try fixture.startSteam()
        let recorder = ScopeRecorder()

        _ = try await Wine.prepareProgramLaunch(
            at: launcherPatcher, bottle: fixture.bottle, recommendedBackend: .d3dMetal,
            builtinD3D12IsD3DMetal: true, overrideWriter: recorder.writer, importer: recorder.importer,
            dxvkFolder: fixture.dxvk, dxmtFolder: root.appending(path: "DXMT"), rockstarRuntime: fixture.runtime
        )

        recorder.expectRockstarChain(layout: swapped)
        #expect(Wine.isStrippedCopy(fixture.system32("d3d11.dll"), of: fixture.d3d11Source))
    }

    @Test("A program Steam's detection claims by its name, outside Steam's folder, suspends the swap")
    func steamNamedProgramSuspends() throws {
        let game = fixture.driveC.appending(path: "GOG Games/SteamWorld Dig 2/SteamWorldDig2.exe")
        try fixture.write(PEBuilder.createMinimalPE32Plus(), to: game)
        #expect(LauncherType.detect(from: game) == .steam)
        try fixture.startSteam()

        #expect(try deploy(game) == nil)

        #expect(system32HoldsDXVK)
        #expect(try fixture.startSteam() == swapped)
    }

    @Test("A Rockstar-store game started directly needs DXVK in system32 and suspends the swap")
    func rockstarStoreGameSuspends() throws {
        let game = fixture.driveC.appending(path: "Program Files/Rockstar Games/Grand Theft Auto V/GTA5.exe")
        try fixture.write(PEBuilder.createMinimalPE32Plus(), to: game)
        try fixture.startSteam()

        #expect(try deploy(game) == nil)

        #expect(system32HoldsDXVK)
    }

    // MARK: - Consumers that refuse the swap

    @Test("A DXVK-plan game installed after a swap makes the next Steam start take it back")
    func dxvkPlanGameTearsDown() throws {
        #expect(try fixture.startSteam() == swapped)
        // Age of Empires II: Definitive Edition, whose GameDB default variant is DXVK.
        try fixture.addGame(appId: 813_780, name: "Age of Empires II", installDir: "AoE2DE", exe: "AoE2DE.exe")

        #expect(try fixture.startSteam() == .degraded(.dxvkPlanGames(["Age of Empires II"])))

        expectNoSwap()
    }

    @Test("A game whose own overrides ask for native d3d11 refuses the swap, not only one on DXVK", arguments: [
        "legacy", "custom"
    ])
    func nativeFirstPlanGameRefuses(_ kind: String) throws {
        let game = try fixture.addGame(appId: 7, name: "Legacy", installDir: "Legacy", exe: "Legacy.exe")
        var overrides = ProgramOverrides()
        if kind == "legacy" {
            // The switch from before Graphics Backend, with no backend of its own.
            overrides.dxvk = true
        } else {
            overrides.graphicsBackend = .d3dMetal
            overrides.dllOverrides = [DLLOverrideEntry(dllName: "d3d11", mode: .nativeThenBuiltin)]
        }
        try fixture.setOverrides(overrides, for: game)

        #expect(try fixture.startSteam() == .degraded(.dxvkPlanGames(["Legacy"])))

        expectNoSwap()
    }

    @Test("Another launcher's native-first AppDefaults entry refuses the swap")
    func otherLauncherEntryRefuses() throws {
        try fixture.writeUserReg(#"""
        [Software\\Wine\\AppDefaults\\EADesktop.exe\\DllOverrides] 1731628800
        "d3d11"="n,b"

        """#)

        #expect(try fixture.startSteam() == .degraded(.unservedConsumers(["EADesktop.exe"])))

        expectNoSwap()
    }

    @Test("A bottle on DXVK refuses the swap and keeps DXVK in system32")
    func dxvkBottleRefuses() throws {
        fixture.bottle.settings.graphicsBackend = .dxvk

        #expect(try fixture.startSteam() == .degraded(.bottleUsesNativeD3D11))

        expectNoSwap()
    }
}
