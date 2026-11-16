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
        let orchestrator = SteamClientOrchestrator(bottle: bottle, driver: driver, timing: Fixture.patient)

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
        let orchestrator = SteamClientOrchestrator(bottle: bottle, driver: driver, timing: Fixture.patient)
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

    @Test("Waiting for a client it started lists the bottle once, after steam.exe appears")
    func clientWaitStaysOnHostDuringBoot() async throws {
        let (bottle, games) = try Fixture.makeBottle()
        let driver = FakeSteamClientDriver(script: [[]])
        let orchestrator = SteamClientOrchestrator(bottle: bottle, driver: driver, timing: Fixture.patient)
        var listsAtStart = 0
        var listsAtLaunch = 0
        driver.onStartClient = {
            listsAtStart = driver.listCalls
            // Booting: Wine is up on the host, the client not yet.
            driver.hostOverride = ["wineboot.exe", "services.exe"]
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                driver.hostOverride = nil
                driver.script = [["steam.exe"]]
            }
        }
        driver.onLaunchGame = { _ in
            listsAtLaunch = driver.listCalls
            driver.script = [["steam.exe", "game1.exe"]]
        }

        orchestrator.launch(games[0])
        await Fixture.awaitIdle(orchestrator)

        #expect(orchestrator.launchError == nil)
        #expect(driver.launched == [games[0].appId])
        #expect(listsAtLaunch == listsAtStart + 1)
    }

    @Test("Another bottle's steam.exe doesn't end the wait for this bottle's client")
    func otherBottlesClientIsNotThisOne() async throws {
        let (bottle, games) = try Fixture.makeBottle()
        let driver = FakeSteamClientDriver(script: [[]])
        // The host has a steam.exe from the start; this bottle never does.
        driver.hostOverride = ["steam.exe"]
        let orchestrator = SteamClientOrchestrator(bottle: bottle, driver: driver, timing: Fixture.fast)

        orchestrator.launch(games[0])
        await Fixture.awaitIdle(orchestrator)

        #expect(orchestrator.launchError == SteamOrchestratorError.clientTimeout.errorDescription)
        #expect(driver.startClientCalls == 1)
        #expect(driver.launched.isEmpty)
        // Only the running check before the start: that client was already
        // up, so the wait never had a new one to ask the bottle about.
        #expect(driver.listCalls == 1)
    }

    @Test("With Steam running in another bottle, the wait lists this bottle once")
    func otherBottlesClientKeepsWaitOnHost() async throws {
        let (bottle, games) = try Fixture.makeBottle()
        let driver = FakeSteamClientDriver(script: [[]])
        // Another bottle's client is up before Play; this one's comes later.
        driver.hostOverride = ["steam.exe"]
        driver.hostSteamPIDOverride = [7]
        let orchestrator = SteamClientOrchestrator(bottle: bottle, driver: driver, timing: Fixture.patient)
        var listsAtStart = 0
        var listsAtLaunch = 0
        driver.onStartClient = {
            listsAtStart = driver.listCalls
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                driver.hostSteamPIDOverride = [7, 8]
                driver.script = [["steam.exe"]]
            }
        }
        driver.onLaunchGame = { _ in
            listsAtLaunch = driver.listCalls
            driver.script = [["steam.exe", "game1.exe"]]
        }

        orchestrator.launch(games[0])
        await Fixture.awaitIdle(orchestrator)

        #expect(orchestrator.launchError == nil)
        #expect(driver.launched == [games[0].appId])
        #expect(listsAtLaunch == listsAtStart + 1)
    }

    @Test("A bottle list that misses the new client is read again until it shows up")
    func clientWaitRetriesAfterAMissedList() async throws {
        let (bottle, games) = try Fixture.makeBottle()
        let driver = FakeSteamClientDriver(script: [[]])
        let orchestrator = SteamClientOrchestrator(bottle: bottle, driver: driver, timing: Fixture.patient)
        driver.onStartClient = {
            // The host sees the client before the bottle's list does: the
            // first two reads after it appears still come back without it.
            driver.hostOverride = ["steam.exe"]
            driver.script = [[], [], ["steam.exe"]]
        }
        driver.onLaunchGame = { _ in
            driver.script = [["steam.exe", "game1.exe"]]
        }

        orchestrator.launch(games[0])
        await Fixture.awaitIdle(orchestrator)

        #expect(orchestrator.launchError == nil)
        #expect(driver.launched == [games[0].appId])
    }

    @Test("A new client that exits before the bottle lists it stops the bottle reads")
    func clientWaitStopsReadingWhenTheNewClientExits() async throws {
        let (bottle, games) = try Fixture.makeBottle()
        let driver = FakeSteamClientDriver(script: [[]])
        // The wait is ended by stop() below, never by its budget: counted in
        // passes rather than seconds, so a loaded runner that holds the main
        // actor for a while can't run the budget out before the reads happen.
        var timing = Fixture.fast
        timing.clientReadyTimeout = 60
        let orchestrator = SteamClientOrchestrator(bottle: bottle, driver: driver, timing: timing)
        var listsAtExit: Int?
        var passesAtExit: Int?
        driver.onStartClient = {
            let listsAtStart = driver.listCalls
            driver.hostOverride = ["steam.exe"]
            // A second read shows the wait is retrying; the client goes during
            // that read, so the result doesn't depend on how fast the runner is.
            driver.onProcessList = { call in
                guard call == listsAtStart + 2 else { return }
                driver.hostOverride = ["services.exe"]
                listsAtExit = call
                passesAtExit = driver.hostPIDCalls
            }
        }

        orchestrator.launch(games[0])
        // Several more passes of the wait after the client went, each of
        // which could have read the bottle again.
        await Fixture.eventually("the wait should keep polling the host") {
            passesAtExit.map { driver.hostPIDCalls >= $0 + 5 } ?? false
        }
        let exit = try #require(listsAtExit)
        // At most the read already under way when the client went.
        #expect(driver.listCalls <= exit + 1)

        orchestrator.stop()
        await Fixture.awaitIdle(orchestrator)
        #expect(orchestrator.launchError == SteamOrchestratorError.clientTimeout.errorDescription)
        #expect(driver.launched.isEmpty)
    }

    @Test("Concurrent launches share one client startup")
    func singleFlightStartup() async throws {
        let (bottle, games) = try Fixture.makeBottle(games: [1_086_940, 1_245_620])
        let driver = FakeSteamClientDriver(script: [[]])
        let orchestrator = SteamClientOrchestrator(bottle: bottle, driver: driver, timing: Fixture.patient)
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
        let orchestrator = SteamClientOrchestrator(bottle: bottle, driver: driver, timing: Fixture.patient)

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
        let orchestrator = SteamClientOrchestrator(bottle: bottle, driver: driver, timing: Fixture.patient)

        orchestrator.launch(games[0])
        await Fixture.awaitIdle(orchestrator)

        #expect(orchestrator.launchError == SteamLaunchError.gameNotFound(appId: games[0].appId).localizedDescription)
    }

    @Test("A client already running is used as is, without fixes or a start")
    func clientAlreadyRunning() async throws {
        let (bottle, games) = try Fixture.makeBottle()
        let driver = FakeSteamClientDriver(script: [["steam.exe", "game1.exe"]])
        let orchestrator = SteamClientOrchestrator(bottle: bottle, driver: driver, timing: Fixture.patient)

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
        let orchestrator = SteamClientOrchestrator(bottle: bottle, driver: driver, timing: Fixture.patient)

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
