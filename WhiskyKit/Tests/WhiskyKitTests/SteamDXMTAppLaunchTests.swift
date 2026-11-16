//
//  SteamDXMTAppLaunchTests.swift
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

/// A `steam.exe -applaunch` launch whose game plan resolves to DXMT (#378).
///
/// One `system32` cannot hold both layers, since both ship `d3d11.dll`, and
/// Steam's client needs DXVK's. So `system32` keeps DXVK for the launcher and
/// the game gets DXMT's trio beside its executable, which Wine's loader
/// searches before `system32` for a native DLL. The game's `AppDefaults`
/// entry says `n,b` for all three, so it loads the copies in its folder.
@Suite("Steam -applaunch over a DXMT plan")
@MainActor
final class SteamDXMTAppLaunchTests {
    private let fixture: DXMTGameFolderFixture
    private typealias Fixture = DXMTGameFolderFixture
    private let game = "Game.exe"

    init() throws {
        fixture = try DXMTGameFolderFixture(prefix: "steam_dxmt_applaunch")
    }

    deinit {
        fixture.cleanUp()
    }

    private func prepareAppLaunch(
        _ bottle: Bottle, gameURL: URL, plan: ProgramOverrides? = nil, recommendedBackend: GraphicsBackend,
        builtinD3D12IsD3DMetal: Bool, recorder: ScopeRecorder = ScopeRecorder()
    ) async throws {
        _ = try await Wine.prepareProgramLaunch(
            at: fixture.steam(in: bottle), args: ["-applaunch", "480"], bottle: bottle,
            programOverrides: plan, overridesApplyToDescendants: true, descendantExecutables: [game],
            descendantExecutableURLs: [gameURL],
            recommendedBackend: recommendedBackend, builtinD3D12IsD3DMetal: builtinD3D12IsD3DMetal,
            overrideWriter: recorder.writer, importer: recorder.importer,
            dxvkFolder: fixture.makeDXVKPayload(), dxmtFolder: fixture.makeDXMTPayload()
        )
    }

    private func prepareDirectLaunch(
        _ bottle: Bottle, gameURL: URL, recommendedBackend: GraphicsBackend = .d3dMetal,
        recorder: ScopeRecorder = ScopeRecorder()
    ) async throws {
        _ = try await Wine.prepareProgramLaunch(
            at: gameURL, bottle: bottle, recommendedBackend: recommendedBackend, builtinD3D12IsD3DMetal: true,
            overrideWriter: recorder.writer, importer: recorder.importer,
            dxvkFolder: fixture.makeDXVKPayload(), dxmtFolder: fixture.makeDXMTPayload()
        )
    }

    /// The launcher's `system32` after the launch: DXVK's d3d11/d3d10core, no
    /// DXMT dxgi, and DXMT's winemetal, which the game folder's trio imports.
    private func expectLauncherKeepsDXVK(_ bottle: Bottle) {
        for dll in ["d3d11.dll", "d3d10core.dll"] {
            #expect(
                Fixture.contents(fixture.system32(bottle, dll)) == Fixture.nativeFake("DXVK x64 \(dll)"),
                "system32 \(dll) is DXVK's"
            )
        }
        #expect(
            Fixture.contents(fixture.system32(bottle, "dxgi.dll")) != Fixture.dxmtFake("x64", "dxgi.dll"),
            "DXMT's dxgi is not in system32"
        )
        #expect(Fixture.contents(fixture.system32(bottle, "winemetal.dll")) == Fixture.dxmtFake("x64", "winemetal.dll"))
    }

    /// The game's entry prefers the native trio, which its own folder now holds.
    private func expectGameEntryPrefersNative(_ recorder: ScopeRecorder) {
        let entry = recorder.overrides(for: .program(game))
        #expect(entry?["d3d11"] == "n,b", "game d3d11")
        #expect(entry?["d3d10core"] == "n,b", "game d3d10core")
        #expect(entry?["dxgi"] == "n,b", "game dxgi")
    }

    @Test("Recommended without GPTK: the game's folder gets DXMT, system32 keeps DXVK for Steam")
    func recommendedDXMTPlanDeploysBesideTheGame() async throws {
        let bottle = try fixture.makeBottle(.recommended)
        let gameURL = try fixture.makeGame(in: bottle)
        let recorder = ScopeRecorder()

        try await prepareAppLaunch(
            bottle, gameURL: gameURL, recommendedBackend: .dxmt, builtinD3D12IsD3DMetal: false, recorder: recorder
        )

        expectLauncherKeepsDXVK(bottle)
        expectGameEntryPrefersNative(recorder)
        #expect(Fixture.holdsDXMT(gameURL.deletingLastPathComponent()))
    }

    @Test("An explicit DXMT bottle: the game's folder gets DXMT, system32 keeps DXVK for Steam")
    func explicitDXMTBottleDeploysBesideTheGame() async throws {
        let bottle = try fixture.makeBottle(.dxmt)
        let gameURL = try fixture.makeGame(in: bottle)
        let recorder = ScopeRecorder()

        try await prepareAppLaunch(
            bottle, gameURL: gameURL, recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: true, recorder: recorder
        )

        expectLauncherKeepsDXVK(bottle)
        expectGameEntryPrefersNative(recorder)
        #expect(Fixture.holdsDXMT(gameURL.deletingLastPathComponent()))
    }

    @Test("A GameDB DXMT plan (Solarpunk, Trine 4) over a D3DMetal bottle deploys beside a 32-bit game")
    func gameDBDXMTPlanOverD3DMetalDeploysBesideTheGame() async throws {
        let bottle = try fixture.makeBottle(.recommended)
        let gameURL = try fixture.makeGame(in: bottle, arch: .x32)
        let recorder = ScopeRecorder()
        var plan = ProgramOverrides()
        plan.graphicsBackend = .dxmt

        try await prepareAppLaunch(
            bottle, gameURL: gameURL, plan: plan, recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: true,
            recorder: recorder
        )

        expectLauncherKeepsDXVK(bottle)
        expectGameEntryPrefersNative(recorder)
        #expect(Fixture.holdsDXMT(gameURL.deletingLastPathComponent(), arch: "x32"))
    }

    @Test("A later D3DMetal plan through Steam takes the copies back")
    func laterD3DMetalAppLaunchRemovesTheCopies() async throws {
        let bottle = try fixture.makeBottle(.recommended)
        let gameURL = try fixture.makeGame(in: bottle)
        try await prepareAppLaunch(bottle, gameURL: gameURL, recommendedBackend: .dxmt, builtinD3D12IsD3DMetal: false)
        #expect(Fixture.holdsDXMT(gameURL.deletingLastPathComponent()))

        try await prepareAppLaunch(
            bottle, gameURL: gameURL, recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: true
        )

        #expect(Fixture.holdsNoTrio(gameURL.deletingLastPathComponent()))
    }

    @Test("A later direct launch of the game on D3DMetal takes the copies back")
    func laterDirectD3DMetalLaunchRemovesTheCopies() async throws {
        let bottle = try fixture.makeBottle(.recommended)
        let gameURL = try fixture.makeGame(in: bottle)
        try await prepareAppLaunch(bottle, gameURL: gameURL, recommendedBackend: .dxmt, builtinD3D12IsD3DMetal: false)

        try await prepareDirectLaunch(bottle, gameURL: gameURL)

        #expect(Fixture.holdsNoTrio(gameURL.deletingLastPathComponent()))
    }

    @Test("A game folder that cannot be written does not fail the launch")
    func failedFolderDeployDoesNotFailTheLaunch() async throws {
        let bottle = try fixture.makeBottle(.dxmt)
        let gameURL = try fixture.makeGame(in: bottle)
        let folder = gameURL.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        let recorder = ScopeRecorder()

        try await prepareAppLaunch(
            bottle, gameURL: gameURL, recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: true, recorder: recorder
        )

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        #expect(Fixture.holdsNoTrio(folder))
        expectLauncherKeepsDXVK(bottle)
        #expect(recorder.writes.count == 1, "the launch went on to write its overrides")
    }

    @Test("A direct DXMT launch of the game keeps DXMT in system32 and places nothing beside it")
    func directDXMTLaunchKeepsDXMT() async throws {
        let bottle = try fixture.makeBottle(.dxmt)
        let gameURL = try fixture.makeGame(in: bottle)

        try await prepareDirectLaunch(bottle, gameURL: gameURL)

        for dll in Fixture.trio {
            #expect(
                Fixture.contents(fixture.system32(bottle, dll)) == Fixture.dxmtFake("x64", dll),
                "system32 \(dll) is DXMT's"
            )
        }
        #expect(Fixture.holdsNoTrio(gameURL.deletingLastPathComponent()))
    }

    @Test("A D3DMetal plan through Steam names no translation DLL and places nothing beside the game")
    func d3dMetalPlanIsUnaffected() async throws {
        let bottle = try fixture.makeBottle(.recommended)
        let gameURL = try fixture.makeGame(in: bottle)
        let recorder = ScopeRecorder()

        try await prepareAppLaunch(
            bottle, gameURL: gameURL, recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: true, recorder: recorder
        )

        let entry = recorder.overrides(for: .program(game))
        #expect(entry != nil, "the game gets an entry")
        for dll in ["dxgi", "d3d10core", "d3d11", "d3d12"] {
            #expect(entry?[dll] == nil, "game \(dll)")
        }
        // No DXMT copy ran, and DXVK's copy only replaces files that already exist,
        // so a fresh prefix gets no d3d11 at all; Wine's default (builtin) order applies.
        #expect(Fixture.contents(fixture.system32(bottle, "d3d11.dll")) == nil)
        #expect(Fixture.holdsNoTrio(gameURL.deletingLastPathComponent()))
    }

    @Test("A DXVK plan through Steam places nothing beside the game")
    func dxvkPlanIsUnaffected() async throws {
        let bottle = try fixture.makeBottle(.dxvk)
        let gameURL = try fixture.makeGame(in: bottle)
        let recorder = ScopeRecorder()

        try await prepareAppLaunch(
            bottle, gameURL: gameURL, recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: true, recorder: recorder
        )

        #expect(recorder.overrides(for: .program(game))?["d3d11"] == "n,b")
        #expect(Fixture.holdsNoTrio(gameURL.deletingLastPathComponent()))
        #expect(DXMTGameFolderRecord.load(from: bottle.url).copies.isEmpty)
    }

    @Test("A plain Steam client start in an explicit DXMT bottle deploys DXMT to system32 only")
    func explicitDXMTClientStartKeepsDXMT() async throws {
        let bottle = try fixture.makeBottle(.dxmt)
        let gameURL = try fixture.makeGame(in: bottle)
        let recorder = ScopeRecorder()

        _ = try await Wine.prepareProgramLaunch(
            at: fixture.steam(in: bottle), args: ["-silent"], bottle: bottle,
            recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: true,
            overrideWriter: recorder.writer, importer: recorder.importer,
            dxvkFolder: fixture.makeDXVKPayload(), dxmtFolder: fixture.makeDXMTPayload()
        )

        // An explicit backend is not steered, and no descendant plan forces DXVK,
        // so Steam's own n,b entry loads DXMT's trio here.
        for dll in Fixture.trio {
            #expect(
                Fixture.contents(fixture.system32(bottle, dll)) == Fixture.dxmtFake("x64", dll),
                "system32 \(dll) is DXMT's"
            )
        }
        #expect(Fixture.holdsNoTrio(gameURL.deletingLastPathComponent()))
    }
}
