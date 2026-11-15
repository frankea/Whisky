//
//  SteamDXMTGameFolderLifecycleTests.swift
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

/// The DXMT copies beside a Steam game over its life (#378): what
/// `SteamLauncher` hands the launch, a game spanning folders, and a plan that
/// moves off DXMT while Steam's own Play is what starts the game.
@Suite("Steam DXMT game folder lifecycle")
@MainActor
final class SteamDXMTGameFolderLifecycleTests {
    private let fixture: DXMTGameFolderFixture
    private typealias Fixture = DXMTGameFolderFixture
    /// An App ID no GameDB entry has, so the bottle's backend decides the plan.
    private let appId = 999_999_901

    init() throws {
        fixture = try DXMTGameFolderFixture(prefix: "steam_dxmt_lifecycle")
    }

    deinit {
        fixture.cleanUp()
    }

    private func installURL(_ bottle: Bottle) -> URL {
        bottle.url.appending(path: "drive_c").appending(path: Fixture.gameFolder)
    }

    /// Prepares the `-applaunch` invocation from the request `SteamLauncher.launch` builds.
    private func prepareAppLaunch(_ bottle: Bottle, recommendedBackend: GraphicsBackend) async throws {
        let scan = SteamLibrary.scanExecutables(under: installURL(bottle))
        let plan = SteamLauncher.launchPlan(appId: appId, scan: scan, bottle: bottle)
        let recorder = ScopeRecorder()
        _ = try await Wine.prepareProgramLaunch(
            at: fixture.steam(in: bottle), bottle: bottle,
            request: SteamLauncher.appLaunchRequest(appId: appId, scan: scan, plan: plan),
            recommendedBackend: recommendedBackend, builtinD3D12IsD3DMetal: recommendedBackend == .d3dMetal,
            overrideWriter: recorder.writer, importer: recorder.importer,
            dxvkFolder: fixture.makeDXVKPayload(), dxmtFolder: fixture.makeDXMTPayload()
        )
    }

    private func prepareLaunch(
        at url: URL, args: [String] = [], _ bottle: Bottle, recommendedBackend: GraphicsBackend
    ) async throws {
        let recorder = ScopeRecorder()
        _ = try await Wine.prepareProgramLaunch(
            at: url, args: args, bottle: bottle,
            recommendedBackend: recommendedBackend, builtinD3D12IsD3DMetal: recommendedBackend == .d3dMetal,
            overrideWriter: recorder.writer, importer: recorder.importer,
            dxvkFolder: fixture.makeDXVKPayload(), dxmtFolder: fixture.makeDXMTPayload()
        )
    }

    @Test("The -applaunch request carries the scan's executables, and a DXMT plan lands beside them")
    func appLaunchRequestCarriesTheGameExecutableURLs() async throws {
        let bottle = try fixture.makeBottle(.recommended)
        let game = try fixture.makeGame(in: bottle)
        let scan = SteamLibrary.scanExecutables(under: installURL(bottle))
        let plan = SteamLauncher.launchPlan(appId: appId, scan: scan, bottle: bottle)

        let request = SteamLauncher.appLaunchRequest(appId: appId, scan: scan, plan: plan)

        #expect(request.overridesApplyToDescendants)
        #expect(request.descendantExecutableURLs == scan.planExecutables)
        #expect(request.descendantExecutableURLs.map(\.lastPathComponent) == ["Game.exe"])
        #expect(Array(request.args.prefix(2)) == ["-applaunch", String(appId)])

        try await prepareAppLaunch(bottle, recommendedBackend: .dxmt)
        #expect(Fixture.holdsDXMT(game.deletingLastPathComponent()))
    }

    @Test("A direct D3DMetal launch of an Unreal stub takes back the copies in Binaries/Win64 too")
    func directLaunchOfTheStubCleansTheWholeGame() async throws {
        let bottle = try fixture.makeBottle(.recommended)
        let stub = try fixture.makeGame(in: bottle)
        let shipping = try fixture.makeGame(
            in: bottle, folder: "\(Fixture.gameFolder)/Game/Binaries/Win64", name: "Game-Win64-Shipping.exe"
        )
        try await prepareAppLaunch(bottle, recommendedBackend: .dxmt)
        #expect(Fixture.holdsDXMT(stub.deletingLastPathComponent()))
        #expect(Fixture.holdsDXMT(shipping.deletingLastPathComponent()))

        try await prepareLaunch(at: stub, bottle, recommendedBackend: .d3dMetal)

        #expect(Fixture.holdsNoTrio(stub.deletingLastPathComponent()))
        #expect(Fixture.holdsNoTrio(shipping.deletingLastPathComponent()))
        #expect(DXMTGameFolderRecord.load(from: bottle.url).copies.isEmpty)
    }

    @Test("Starting Steam takes back the copies of a library game whose plan moved off DXMT")
    func clientStartRetractsAStalePlan() async throws {
        let bottle = try fixture.makeBottle(.recommended)
        let game = try fixture.makeGame(in: bottle)
        let steam = try fixture.steam(in: bottle)
        try fixture.registerSteamGame(in: bottle, appId: appId)
        try await prepareAppLaunch(bottle, recommendedBackend: .dxmt)
        #expect(Fixture.holdsDXMT(game.deletingLastPathComponent()))

        // The user moves the bottle to D3DMetal, then plays from Steam's own window.
        bottle.settings.graphicsBackend = .d3dMetal
        try await prepareLaunch(at: steam, args: ["-silent"], bottle, recommendedBackend: .dxmt)

        #expect(Fixture.holdsNoTrio(game.deletingLastPathComponent()))
        #expect(DXMTGameFolderRecord.load(from: bottle.url).copies.isEmpty)
    }

    @Test("Starting Steam keeps the copies of a library game whose plan is still DXMT")
    func clientStartKeepsACurrentPlan() async throws {
        let bottle = try fixture.makeBottle(.recommended)
        let game = try fixture.makeGame(in: bottle)
        let steam = try fixture.steam(in: bottle)
        try fixture.registerSteamGame(in: bottle, appId: appId)
        try await prepareAppLaunch(bottle, recommendedBackend: .dxmt)

        try await prepareLaunch(at: steam, args: ["-silent"], bottle, recommendedBackend: .dxmt)

        #expect(Fixture.holdsDXMT(game.deletingLastPathComponent()))
        #expect(DXMTGameFolderRecord.load(from: bottle.url).copies.count == 3)
    }
}
