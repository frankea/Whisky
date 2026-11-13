//
//  WineHelperActivityTests.swift
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

/// Whisky's own Wine helpers bring up a bottle's wineserver; that must read
/// neither as an orphan nor, once a game has exited, as the game still running.
/// Nothing here starts Wine.
@MainActor
final class WineHelperActivityTests: XCTestCase {
    private var bottleURL: URL!
    private var bottle: Bottle!
    private let registry = ProcessRegistry.shared
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() async throws {
        try await super.setUp()
        bottleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("helper-bottle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)
        bottle = Bottle(bottleUrl: bottleURL, isAvailable: true)
        registry.reset()
        WineHelperActivity.shared.reset()
    }

    override func tearDown() async throws {
        registry.reset()
        WineHelperActivity.shared.reset()
        try? FileManager.default.removeItem(at: bottleURL)
        try await super.tearDown()
    }

    private func listed(_ names: String...) -> [WineProcess] {
        names.enumerated().map { index, name in
            WineProcess(
                imageName: name, winePID: Int32(index + 32), memoryUsage: "1 K", kind: ProcessKind.classify(name)
            )
        }
    }

    // MARK: - Helpers

    func testNothingAccountsForAnUntouchedBottle() {
        XCTAssertFalse(WineHelperActivity().accountsForWineserver(bottleURL: bottleURL, now: now))
    }

    func testARunningHelperAccountsForTheWineserver() {
        let activity = WineHelperActivity()

        activity.begin(bottleURL: bottleURL)

        XCTAssertTrue(activity.accountsForWineserver(bottleURL: bottleURL, now: now.addingTimeInterval(3_600)))
    }

    /// The wineserver outlives its last client by a few seconds.
    func testAFinishedHelperAccountsForTheWineserverUntilItSettles() {
        let activity = WineHelperActivity()
        activity.begin(bottleURL: bottleURL)
        activity.end(bottleURL: bottleURL, at: now)

        let settling = now.addingTimeInterval(WineHelperActivity.settleTime - 1)
        XCTAssertTrue(activity.accountsForWineserver(bottleURL: bottleURL, now: settling))
        let settled = now.addingTimeInterval(WineHelperActivity.settleTime)
        XCTAssertFalse(activity.accountsForWineserver(bottleURL: bottleURL, now: settled))
    }

    func testOverlappingHelpersCountUntilTheLastEnds() {
        let activity = WineHelperActivity()
        activity.begin(bottleURL: bottleURL)
        activity.begin(bottleURL: bottleURL)

        activity.end(bottleURL: bottleURL, at: now)

        let later = now.addingTimeInterval(3_600)
        XCTAssertTrue(activity.accountsForWineserver(bottleURL: bottleURL, now: later))
        activity.end(bottleURL: bottleURL, at: now)
        XCTAssertFalse(activity.accountsForWineserver(bottleURL: bottleURL, now: later))
    }

    func testActivityIsPerBottle() {
        let activity = WineHelperActivity()

        activity.begin(bottleURL: bottleURL)

        XCTAssertFalse(activity.accountsForWineserver(bottleURL: bottleURL.appendingPathComponent("other"), now: now))
    }

    // MARK: - Listings

    /// After the game exits, the Processes page's polling keeps the wineserver
    /// up; a listing with only Wine's own processes ends the session.
    func testListingWithNothingRunningEndsAnOldSession() {
        let activity = WineHelperActivity()
        registry.register(process: Process(), bottle: bottle, programName: "game.exe")
        registry.noteLaunch(bottleURL: bottleURL, at: now.addingTimeInterval(-600))

        let quiet = activity.recordListing(
            listed("services.exe", "explorer.exe", "tasklist.exe", "conhost.exe"),
            bottleURL: bottleURL, registry: registry, now: now
        )

        XCTAssertTrue(quiet)
        XCTAssertNil(registry.lastLaunch(for: bottleURL))
        XCTAssertEqual(registry.getProcessCount(for: bottleURL), 0)
        XCTAssertTrue(activity.accountsForWineserver(bottleURL: bottleURL, now: now))
    }

    func testListingWithAProgramKeepsTheSession() {
        let activity = WineHelperActivity()
        registry.noteLaunch(bottleURL: bottleURL, at: now.addingTimeInterval(-600))

        let quiet = activity.recordListing(
            listed("services.exe", "game.exe", "tasklist.exe"), bottleURL: bottleURL, registry: registry, now: now
        )

        XCTAssertFalse(quiet)
        XCTAssertNotNil(registry.lastLaunch(for: bottleURL))
        XCTAssertFalse(activity.accountsForWineserver(bottleURL: bottleURL, now: now))
    }

    /// `wine start` returns before the program shows up in the listing.
    func testListingDuringStartupKeepsTheSession() {
        let activity = WineHelperActivity()
        registry.noteLaunch(bottleURL: bottleURL, at: now.addingTimeInterval(-2))

        let quiet = activity.recordListing(
            listed("services.exe", "start.exe", "tasklist.exe"), bottleURL: bottleURL, registry: registry, now: now
        )

        XCTAssertFalse(quiet)
        XCTAssertNotNil(registry.lastLaunch(for: bottleURL))
    }

    /// A failed listing has no rows; that says nothing about what runs.
    func testEmptyListingChangesNothing() {
        let activity = WineHelperActivity()
        registry.noteLaunch(bottleURL: bottleURL, at: now.addingTimeInterval(-600))

        let quiet = activity.recordListing([], bottleURL: bottleURL, registry: registry, now: now)

        XCTAssertFalse(quiet)
        XCTAssertNotNil(registry.lastLaunch(for: bottleURL))
        XCTAssertFalse(activity.accountsForWineserver(bottleURL: bottleURL, now: now))
    }

    /// A program left over from before a restart stays orphaned while listed.
    func testListingWithAProgramAndNoSessionIsNotAccountedFor() {
        let activity = WineHelperActivity()

        let quiet = activity.recordListing(
            listed("explorer.exe", "game.exe"), bottleURL: bottleURL, registry: registry, now: now
        )

        XCTAssertFalse(quiet)
        XCTAssertFalse(activity.accountsForWineserver(bottleURL: bottleURL, now: now))
    }

    // MARK: - Listing a bottle

    /// A fresh prefix has no wineserver, so a listing never brings one up.
    func testListingAnIdleBottleRunsNothing() async throws {
        let processes = try await Wine.listProcesses(for: bottle)

        XCTAssertEqual(processes, [])
    }
}
