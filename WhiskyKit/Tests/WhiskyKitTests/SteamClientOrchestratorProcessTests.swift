//
//  SteamClientOrchestratorProcessTests.swift
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

@Suite("Steam client orchestrator: processes, stopping, tracking")
@MainActor
struct SteamClientOrchestratorProcessTests {
    private typealias Fixture = SteamOrchestratorFixture

    @Test("Reads inside the snapshot lifetime share one process list")
    func snapshotIsShared() async throws {
        let (bottle, _) = try Fixture.makeBottle()
        var timing = Fixture.fast
        timing.snapshotLifetime = 1
        let driver = FakeSteamClientDriver(script: [["steam.exe"]])
        let orchestrator = SteamClientOrchestrator(bottle: bottle, driver: driver, timing: Fixture.fast)

        _ = await orchestrator.runningProcesses()
        _ = await orchestrator.runningProcesses()
        #expect(driver.listCalls == 1)
    }

    @Test("A snapshot past its lifetime is re-read")
    func snapshotExpires() async throws {
        let (bottle, _) = try Fixture.makeBottle()
        let driver = FakeSteamClientDriver(script: [["steam.exe"]])
        var timing = Fixture.fast
        timing.snapshotLifetime = 0.02
        let orchestrator = SteamClientOrchestrator(bottle: bottle, driver: driver, timing: timing)

        _ = await orchestrator.runningProcesses()
        try await Task.sleep(for: .milliseconds(40))
        _ = await orchestrator.runningProcesses()
        #expect(driver.listCalls == 2)
    }

    @Test("Concurrent reads coalesce into one process list")
    func concurrentReadsCoalesce() async throws {
        let (bottle, _) = try Fixture.makeBottle()
        let driver = FakeSteamClientDriver(script: [["steam.exe"]])
        driver.listDelay = .milliseconds(30)
        let orchestrator = SteamClientOrchestrator(bottle: bottle, driver: driver, timing: Fixture.fast)

        async let first = orchestrator.runningProcesses()
        async let second = orchestrator.runningProcesses()
        let (one, two) = await (first, second)

        #expect(driver.listCalls == 1)
        #expect(one.map(\.imageName) == two.map(\.imageName))
    }

    @Test("An empty host process list skips tasklist entirely")
    func hostShortCircuit() async throws {
        let (bottle, _) = try Fixture.makeBottle()
        let driver = FakeSteamClientDriver(script: [["steam.exe"]])
        driver.hostOverride = []
        let orchestrator = SteamClientOrchestrator(bottle: bottle, driver: driver, timing: Fixture.fast)

        let names = await orchestrator.runningImageNames()

        #expect(names.isEmpty)
        #expect(driver.hostCalls == 1)
        #expect(driver.listCalls == 0)
    }

    @Test("Stopping a game kills only its processes and drops the snapshot")
    func stopGame() async throws {
        let (bottle, games) = try Fixture.makeBottle()
        var timing = Fixture.fast
        timing.snapshotLifetime = 1
        let driver = FakeSteamClientDriver(script: [["steam.exe", "game1.exe"]])
        let orchestrator = SteamClientOrchestrator(bottle: bottle, driver: driver, timing: timing)
        _ = await orchestrator.runningProcesses()
        #expect(driver.listCalls == 1)

        await orchestrator.stop(games[0])

        #expect(driver.killed == [101])
        #expect(driver.listCalls == 2, "the refresh after a kill must not answer from the stale snapshot")
    }

    @Test("Stop cancels an in-flight launch and hands the driver its shutdown")
    func stopAll() async throws {
        let (bottle, games) = try Fixture.makeBottle()
        let driver = FakeSteamClientDriver(script: [[]])
        var timing = Fixture.fast
        timing.clientReadyTimeout = 5
        let orchestrator = SteamClientOrchestrator(bottle: bottle, driver: driver, timing: timing)

        orchestrator.launch(games[0])
        try await Task.sleep(for: .milliseconds(20))
        orchestrator.stop()

        #expect(driver.shutdownCalls == 1)
        await Fixture.eventually("the cancelled launch should clear its phase") { orchestrator.phases.isEmpty }
        #expect(driver.launched.isEmpty)
    }

    @Test("Tracking reports the games whose executables are running")
    func trackingReflectsProcessList() async throws {
        let (bottle, games) = try Fixture.makeBottle(games: [1_086_940, 1_245_620])
        let driver = FakeSteamClientDriver(script: [["steam.exe", "game2.exe"]])
        let orchestrator = SteamClientOrchestrator(bottle: bottle, driver: driver, timing: Fixture.fast)

        orchestrator.startTracking(games: games)
        await Fixture.eventually("game 2 should show as running") { orchestrator.runningAppIds == [games[1].appId] }

        driver.script = [["steam.exe"]]
        orchestrator.processSnapshot = nil
        await Fixture.eventually("game 2 should stop showing as running") { orchestrator.runningAppIds.isEmpty }
        orchestrator.stop()
    }
}

@Suite("Wine Steam client driver: process listing")
struct WineSteamClientDriverTests {
    @Test("Only .exe entries survive, lower-cased, by their last path component")
    func exeNamesFromListing() {
        let listing = """
        /sbin/launchd
        C:\\Program Files (x86)\\Steam\\steam.exe
        C:\\Program Files (x86)\\Steam\\steamwebhelper.EXE
        Z:\\Users\\me\\Games\\Deep Rock Galactic\\FSD\\Binaries\\Win64\\FSD-Win64-Shipping.exe
        wineserver
        /usr/bin/ps
        """
        let names = WineSteamClientDriver.exeImageNames(inProcessListing: listing)
        #expect(names == ["steam.exe", "steamwebhelper.exe", "fsd-win64-shipping.exe"])
    }

    @Test("A listing without Wine processes yields nothing to check")
    func emptyWhenNoExe() {
        #expect(WineSteamClientDriver.exeImageNames(inProcessListing: "/sbin/launchd\nwineserver\n").isEmpty)
        #expect(WineSteamClientDriver.exeImageNames(inProcessListing: "").isEmpty)
    }

    @Test("A bare image name without a path is kept as is")
    func bareName() {
        #expect(WineSteamClientDriver.exeImageNames(inProcessListing: "explorer.exe") == ["explorer.exe"])
    }

    @Test("The real driver reads the host process list without Wine")
    @MainActor func readsHostProcessList() async throws {
        let (bottle, _) = try SteamOrchestratorFixture.makeBottle()
        let driver = WineSteamClientDriver(bottle: bottle)

        let names = await driver.hostWineImageNames()

        // Whatever Wine processes the host happens to have, the answer is
        // only ever .exe image names; on a quiet machine it is empty.
        #expect(names.allSatisfy { $0.hasSuffix(".exe") && $0 == $0.lowercased() })
    }
}
