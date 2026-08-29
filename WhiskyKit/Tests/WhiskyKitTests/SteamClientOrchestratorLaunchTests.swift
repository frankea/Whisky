//
//  SteamClientOrchestratorLaunchTests.swift
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

@Suite("Steam client orchestrator: launch sequence")
@MainActor
struct SteamClientOrchestratorLaunchTests {
    private typealias Fixture = SteamOrchestratorFixture

    @Test("A bottle without Steam fails before touching the client")
    func steamNotInstalled() async throws {
        let (bottle, games) = try Fixture.makeBottle(steamInstalled: false)
        let driver = FakeSteamClientDriver(script: [[]])
        let orchestrator = SteamClientOrchestrator(bottle: bottle, driver: driver, timing: Fixture.fast)

        orchestrator.launch(games[0])
        await Fixture.awaitIdle(orchestrator)

        #expect(orchestrator.launchError == SteamOrchestratorError.steamNotInstalled.errorDescription)
        #expect(driver.startClientCalls == 0)
        #expect(driver.launched.isEmpty)
    }

    @Test("Cold start: client comes up, game launches, game appears")
    func coldStartHappyPath() async throws {
        let (bottle, games) = try Fixture.makeBottle()
        let driver = FakeSteamClientDriver(script: [[]])
        let orchestrator = SteamClientOrchestrator(bottle: bottle, driver: driver, timing: Fixture.fast)
        var phaseAtLaunch: SteamClientOrchestrator.Phase?
        driver.onStartClient = { driver.script = [["steam.exe"]] }
        driver.onLaunchGame = { game in
            phaseAtLaunch = orchestrator.phases[game.appId]
            driver.script = [["steam.exe", "game1.exe"]]
        }

        orchestrator.launch(games[0])
        #expect(orchestrator.phases[games[0].appId] == .startingClient)
        await Fixture.awaitIdle(orchestrator)

        #expect(orchestrator.launchError == nil)
        #expect(driver.startClientCalls == 1)
        #expect(driver.fixesCalls == 1)
        #expect(driver.launched == [games[0].appId])
        #expect(phaseAtLaunch == .launching)
        #expect(driver.readyCalls == 1)
    }

    @Test("Concurrent launches share one client startup")
    func singleFlightStartup() async throws {
        let (bottle, games) = try Fixture.makeBottle(games: [1_086_940, 1_245_620])
        let driver = FakeSteamClientDriver(script: [[]])
        let orchestrator = SteamClientOrchestrator(bottle: bottle, driver: driver, timing: Fixture.fast)
        driver.onStartClient = {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(30))
                driver.script = [["steam.exe", "game1.exe", "game2.exe"]]
            }
        }

        orchestrator.launch(games[0])
        orchestrator.launch(games[1])
        await Fixture.awaitIdle(orchestrator)

        #expect(driver.startClientCalls == 1)
        #expect(driver.readyCalls == 1)
        #expect(Set(driver.launched) == Set(games.map(\.appId)))
        #expect(orchestrator.launchError == nil)
    }

    @Test("A second launch of the same game while one is in flight is ignored")
    func duplicateLaunchIgnored() async throws {
        let (bottle, games) = try Fixture.makeBottle()
        let driver = FakeSteamClientDriver(script: [["steam.exe", "game1.exe"]])
        let orchestrator = SteamClientOrchestrator(bottle: bottle, driver: driver, timing: Fixture.fast)

        orchestrator.launch(games[0])
        orchestrator.launch(games[0])
        await Fixture.awaitIdle(orchestrator)

        #expect(driver.launched == [games[0].appId])
    }

    @Test("The client never appearing is reported as a client timeout")
    func clientTimeout() async throws {
        let (bottle, games) = try Fixture.makeBottle()
        let driver = FakeSteamClientDriver(script: [[]])
        let orchestrator = SteamClientOrchestrator(bottle: bottle, driver: driver, timing: Fixture.fast)

        orchestrator.launch(games[0])
        await Fixture.awaitIdle(orchestrator)

        #expect(orchestrator.launchError == SteamOrchestratorError.clientTimeout.errorDescription)
        #expect(driver.startClientCalls == 1)
        #expect(driver.launched.isEmpty)
        #expect(driver.readyCalls == 0)
    }

    @Test("The game never appearing is reported as a launch timeout")
    func launchGraceTimeout() async throws {
        let (bottle, games) = try Fixture.makeBottle()
        let driver = FakeSteamClientDriver(script: [["steam.exe"]])
        let orchestrator = SteamClientOrchestrator(bottle: bottle, driver: driver, timing: Fixture.fast)

        orchestrator.launch(games[0])
        await Fixture.awaitIdle(orchestrator)

        #expect(driver.launched == [games[0].appId])
        #expect(orchestrator.launchError == String(localized: "steam.launch.timeout"))
    }

    @Test("A launch failure from the client surfaces as the error")
    func launchFailure() async throws {
        let (bottle, games) = try Fixture.makeBottle()
        let driver = FakeSteamClientDriver(script: [["steam.exe"]])
        driver.launchFailure = SteamLaunchError.gameNotFound(appId: games[0].appId)
        let orchestrator = SteamClientOrchestrator(bottle: bottle, driver: driver, timing: Fixture.fast)

        orchestrator.launch(games[0])
        await Fixture.awaitIdle(orchestrator)

        #expect(orchestrator.launchError == SteamLaunchError.gameNotFound(appId: games[0].appId).localizedDescription)
    }

    @Test("A client already running is used as is, without fixes or a start")
    func clientAlreadyRunning() async throws {
        let (bottle, games) = try Fixture.makeBottle()
        let driver = FakeSteamClientDriver(script: [["steam.exe", "game1.exe"]])
        let orchestrator = SteamClientOrchestrator(bottle: bottle, driver: driver, timing: Fixture.fast)

        orchestrator.launch(games[0])
        await Fixture.awaitIdle(orchestrator)

        #expect(driver.startClientCalls == 0)
        #expect(driver.fixesCalls == 0)
        #expect(driver.readyCalls == 1)
        #expect(driver.launched == [games[0].appId])
    }

    @Test("Manual launcher mode never has fixes applied")
    func manualModeSkipsFixes() async throws {
        let (bottle, games) = try Fixture.makeBottle()
        bottle.settings.launcherMode = .manual
        let driver = FakeSteamClientDriver(script: [[]])
        driver.onStartClient = { driver.script = [["steam.exe", "game1.exe"]] }
        let orchestrator = SteamClientOrchestrator(bottle: bottle, driver: driver, timing: Fixture.fast)

        orchestrator.launch(games[0])
        await Fixture.awaitIdle(orchestrator)

        #expect(driver.startClientCalls == 1)
        #expect(driver.fixesCalls == 0)
    }

    @Test("The gate: auto applies, manual and already-configured do not")
    func fixGate() {
        var settings = BottleSettings()
        settings.launcherMode = .auto
        settings.launcherCompatibilityMode = false
        #expect(SteamClientOrchestrator.shouldApplyLauncherFixes(settings: settings))

        settings.launcherCompatibilityMode = true
        settings.detectedLauncher = .steam
        #expect(!SteamClientOrchestrator.shouldApplyLauncherFixes(settings: settings))

        settings.detectedLauncher = .epicGames
        #expect(SteamClientOrchestrator.shouldApplyLauncherFixes(settings: settings))

        settings.launcherMode = .manual
        #expect(!SteamClientOrchestrator.shouldApplyLauncherFixes(settings: settings))
    }
}
