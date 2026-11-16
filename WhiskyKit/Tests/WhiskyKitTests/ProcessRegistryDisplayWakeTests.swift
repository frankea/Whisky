//
//  ProcessRegistryDisplayWakeTests.swift
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

@testable import WhiskyKit
import XCTest

/// The display-sleep assertion follows the launcher process, not the session:
/// an entry outlives its `wine start` process, and a launcher left idling in
/// the tray must not keep the display awake.
@MainActor
final class ProcessRegistryDisplayWakeTests: XCTestCase {
    private var bottleURL: URL!
    private var bottle: Bottle!
    private let registry = ProcessRegistry.shared

    override func setUp() async throws {
        try await super.setUp()
        bottleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("display-wake-bottle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)
        bottle = Bottle(bottleUrl: bottleURL, isAvailable: true)
        registry.reset()
    }

    override func tearDown() async throws {
        registry.reset()
        try? FileManager.default.removeItem(at: bottleURL)
        try await super.tearDown()
    }

    func testRegisteringAloneTakesNoAssertion() {
        registry.register(process: Process(), bottle: bottle, programName: "game.exe")

        XCTAssertFalse(registry.holdsDisplayWakeAssertion)
    }

    func testAssertionIsHeldWhileTheLauncherRuns() {
        let launcher = Process()
        registry.register(process: launcher, bottle: bottle, programName: "game.exe")

        registry.updatePID(pid: 424_242, for: launcher)

        XCTAssertTrue(registry.holdsDisplayWakeAssertion)
    }

    /// `launcherDidExit` keeps the entry with PID 0 after a clean `wine start` exit.
    func testAssertionIsReleasedOnceTheLauncherExitsThoughTheEntryStays() {
        let launcher = Process()
        registry.register(process: launcher, bottle: bottle, programName: "steam.exe")
        registry.updatePID(pid: 424_242, for: launcher)

        Wine.launcherDidExit(launcher, exitCode: 0)

        XCTAssertFalse(registry.holdsDisplayWakeAssertion)
        XCTAssertEqual(registry.getProcessCount(for: bottleURL), 1)
    }

    func testAssertionIsKeptWhileAnotherLauncherRuns() {
        let first = Process()
        let second = Process()
        registry.register(process: first, bottle: bottle, programName: "launcher.exe")
        registry.register(process: second, bottle: bottle, programName: "game.exe")
        registry.updatePID(pid: 424_242, for: first)
        registry.updatePID(pid: 424_243, for: second)

        registry.updatePID(pid: 0, for: first)
        XCTAssertTrue(registry.holdsDisplayWakeAssertion)

        registry.unregister(pid: 424_243)
        XCTAssertFalse(registry.holdsDisplayWakeAssertion)
    }

    func testEndingTheSessionReleasesTheAssertion() {
        let launcher = Process()
        registry.register(process: launcher, bottle: bottle, programName: "game.exe")
        registry.updatePID(pid: 424_242, for: launcher)

        registry.endSession(for: bottleURL)

        XCTAssertFalse(registry.holdsDisplayWakeAssertion)
    }
}
