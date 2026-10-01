//
//  SteamLauncherTests.swift
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

@Suite("SteamLauncher Routing Tests")
struct SteamLauncherTests {
    private let tempRoot: URL

    init() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "steamlaunch_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    /// A bottle holding a Steam install with each of `appIds` fully installed
    /// and each of `updatingAppIds` present on disk but still downloading.
    private func makeSteamBottle(
        _ label: String, appIds: [Int], updatingAppIds: [Int] = []
    ) throws -> URL {
        let bottle = tempRoot.appending(path: "\(label)-\(UUID().uuidString)")
        let steamRoot = bottle.appending(path: "drive_c")
            .appending(path: "Program Files (x86)").appending(path: "Steam")
        let steamApps = steamRoot.appending(path: "steamapps")
        try FileManager.default.createDirectory(at: steamApps, withIntermediateDirectories: true)
        try Data().write(to: steamRoot.appending(path: "steam.exe"))

        for appId in appIds {
            try writeGame(appId: appId, stateFlags: 4, steamApps: steamApps)
        }
        for appId in updatingAppIds {
            try writeGame(appId: appId, stateFlags: 2, steamApps: steamApps)
        }
        return bottle
    }

    /// Writes a manifest and install directory for `appId`. StateFlags 4 marks
    /// the game fully installed; 2 marks an update still running.
    private func writeGame(appId: Int, stateFlags: Int, steamApps: URL) throws {
        let installDir = "Game\(appId)"
        try FileManager.default.createDirectory(
            at: steamApps.appending(path: "common").appending(path: installDir),
            withIntermediateDirectories: true
        )
        let manifest = """
        "AppState"
        {
            "appid"        "\(appId)"
            "name"        "Game \(appId)"
            "installdir"        "\(installDir)"
            "StateFlags"        "\(stateFlags)"
        }
        """
        try Data(manifest.utf8)
            .write(to: steamApps.appending(path: "appmanifest_\(appId).acf"))
    }

    private func makeRouting() -> GameRouting {
        GameRouting(url: tempRoot.appending(path: "GameRouting-\(UUID().uuidString).plist"))
    }

    @Test("The remembered bottle wins over another that also has the game")
    @MainActor func routeWins() throws {
        let first = try Bottle(bottleUrl: makeSteamBottle("first", appIds: [1_245_620]))
        let second = try Bottle(bottleUrl: makeSteamBottle("second", appIds: [1_245_620]))
        let routing = makeRouting()
        routing.record(appId: 1_245_620, bottleURL: second.url)

        let resolved = try SteamLauncher.resolveBottle(
            appId: 1_245_620, in: [first, second], routing: routing
        )

        #expect(resolved.url == second.url)
    }

    @Test("A route to a bottle that lost the game falls through to one that has it")
    @MainActor func staleRouteFallsThrough() throws {
        let stale = try Bottle(bottleUrl: makeSteamBottle("stale", appIds: [4_576_510]))
        let real = try Bottle(bottleUrl: makeSteamBottle("real", appIds: [1_245_620]))
        let routing = makeRouting()
        routing.record(appId: 1_245_620, bottleURL: stale.url)

        let resolved = try SteamLauncher.resolveBottle(
            appId: 1_245_620, in: [stale, real], routing: routing
        )

        #expect(resolved.url == real.url)
    }

    @Test("A route to a bottle Whisky no longer knows falls through")
    @MainActor func routeToUnknownBottleFallsThrough() throws {
        let deleted = try makeSteamBottle("deleted", appIds: [1_245_620])
        let real = try Bottle(bottleUrl: makeSteamBottle("real", appIds: [1_245_620]))
        let routing = makeRouting()
        routing.record(appId: 1_245_620, bottleURL: deleted)

        let resolved = try SteamLauncher.resolveBottle(
            appId: 1_245_620, in: [real], routing: routing
        )

        #expect(resolved.url == real.url)
    }

    @Test("Without a route the first bottle holding the game wins")
    @MainActor func firstInstallWinsWithoutRoute() throws {
        let empty = try Bottle(bottleUrl: makeSteamBottle("empty", appIds: []))
        let holder = try Bottle(bottleUrl: makeSteamBottle("holder", appIds: [1_245_620]))

        let resolved = try SteamLauncher.resolveBottle(
            appId: 1_245_620, in: [empty, holder], routing: makeRouting()
        )

        #expect(resolved.url == holder.url)
    }

    @Test("No bottle with the game throws gameNotFound")
    @MainActor func noBottleThrows() throws {
        let bottle = try Bottle(bottleUrl: makeSteamBottle("other", appIds: [4_576_510]))
        let routing = makeRouting()
        routing.record(appId: 1_245_620, bottleURL: bottle.url)

        #expect(throws: SteamLaunchError.gameNotFound(appId: 1_245_620)) {
            try SteamLauncher.resolveBottle(appId: 1_245_620, in: [bottle], routing: routing)
        }
    }

    @Test("With no route, bottle order decides between multiple holders")
    @MainActor func ambiguityFollowsBottleOrder() throws {
        let first = try Bottle(bottleUrl: makeSteamBottle("first", appIds: [1_245_620]))
        let second = try Bottle(bottleUrl: makeSteamBottle("second", appIds: [1_245_620]))
        let routing = makeRouting()

        let forward = try SteamLauncher.resolveBottle(
            appId: 1_245_620, in: [first, second], routing: routing
        )
        let reversed = try SteamLauncher.resolveBottle(
            appId: 1_245_620, in: [second, first], routing: routing
        )

        #expect(forward.url == first.url)
        #expect(reversed.url == second.url)
    }

    @Test("A bypassed stale route stays in the store untouched")
    @MainActor func staleRouteIsBypassedNotPruned() throws {
        let stale = try Bottle(bottleUrl: makeSteamBottle("stale", appIds: []))
        let real = try Bottle(bottleUrl: makeSteamBottle("real", appIds: [1_245_620]))
        let routing = makeRouting()
        routing.record(appId: 1_245_620, bottleURL: stale.url)

        let resolved = try SteamLauncher.resolveBottle(
            appId: 1_245_620, in: [stale, real], routing: routing
        )

        #expect(resolved.url == real.url)
        // Resolution never writes; pruning belongs to bottle deletion.
        let stored = routing.bottleURL(forAppId: 1_245_620)
        #expect(stored?.lastPathComponent == stale.url.lastPathComponent)
    }

    @Test("A route to a bottle still downloading the game is not trusted")
    @MainActor func updatingInstallIsNotTrusted() throws {
        let updating = try Bottle(
            bottleUrl: makeSteamBottle("updating", appIds: [], updatingAppIds: [1_245_620])
        )
        let ready = try Bottle(bottleUrl: makeSteamBottle("ready", appIds: [1_245_620]))
        let routing = makeRouting()
        routing.record(appId: 1_245_620, bottleURL: updating.url)

        let resolved = try SteamLauncher.resolveBottle(
            appId: 1_245_620, in: [updating, ready], routing: routing
        )

        #expect(resolved.url == ready.url)
    }

    @Test("Resolving a game hands back the library entry with the bottle")
    @MainActor func resolveGameCarriesTheEntry() throws {
        let bottle = try Bottle(bottleUrl: makeSteamBottle("library", appIds: [1_245_620]))

        let hit = try SteamLauncher.resolveGame(
            appId: 1_245_620, in: [bottle], routing: makeRouting()
        )

        #expect(hit.bottle.url == bottle.url)
        #expect(hit.game.appId == 1_245_620)
        #expect(hit.game.name == "Game 1245620")
    }

    @Test("Narrowing to one bottle still refuses an App ID it does not have")
    @MainActor func namedBottleWithoutTheGameIsRefused() throws {
        let named = try Bottle(bottleUrl: makeSteamBottle("named", appIds: [4_576_510]))
        let holder = try Bottle(bottleUrl: makeSteamBottle("holder", appIds: [1_245_620]))
        let routing = makeRouting()
        routing.record(appId: 1_245_620, bottleURL: holder.url)

        #expect(throws: SteamLaunchError.gameNotFound(appId: 1_245_620)) {
            try SteamLauncher.resolveGame(appId: 1_245_620, in: [named], routing: routing)
        }
    }

    // MARK: - Bringing the client up before -applaunch (#276)

    @Test("A running client is not started again")
    @MainActor func runningClientIsNotStarted() async {
        var starts = 0

        let running = await SteamLauncher.startClientIfNeeded(
            isRunning: { true }, start: { starts += 1 }, hasStarted: { false },
            timeout: .seconds(5), pollInterval: .milliseconds(10)
        )

        #expect(running)
        #expect(starts == 0)
    }

    @Test("A cold client is started on its own and waited for before the game is handed over")
    @MainActor func coldClientIsStartedAndAwaited() async {
        var starts = 0
        var bottleChecks = 0
        var polls = 0

        let running = await SteamLauncher.startClientIfNeeded(
            isRunning: {
                bottleChecks += 1
                return false
            },
            start: { starts += 1 },
            hasStarted: {
                polls += 1
                // Comes up on the third look after the start.
                return starts > 0 && polls >= 3
            },
            timeout: .seconds(30), pollInterval: .milliseconds(10)
        )

        #expect(running)
        #expect(starts == 1)
        // The bottle is asked once; the wait only looks at the cheap check.
        #expect(bottleChecks == 1)
        #expect(polls == 3)
    }

    @Test("A client that never comes up stops the wait after the timeout")
    @MainActor func clientThatNeverComesUpTimesOut() async {
        var starts = 0

        let running = await SteamLauncher.startClientIfNeeded(
            isRunning: { false }, start: { starts += 1 }, hasStarted: { false },
            timeout: .milliseconds(50), pollInterval: .milliseconds(10)
        )

        #expect(!running)
        #expect(starts == 1)
    }

    @Test("Steam's host processes are found by their Windows image")
    func steamPIDsComeFromTheHostListing() {
        let listing = """
          101 /Users/me/Libraries/Wine/bin/wineserver
          202 C:\\windows\\system32\\winedevice.exe
          303 C:\\Program Files (x86)\\Steam\\steam.exe
          404 C:\\Program Files (x86)\\Steam\\bin\\cef\\cef.win7x64\\steamwebhelper.exe
          505 C:\\Program Files (x86)\\Steam\\STEAM.EXE
        """

        #expect(SteamLauncher.steamPIDs(inProcessListing: listing) == [303, 505])
    }
}
