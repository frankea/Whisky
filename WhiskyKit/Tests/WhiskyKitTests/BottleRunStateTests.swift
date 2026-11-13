//
//  BottleRunStateTests.swift
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

@Suite("Bottle run state")
struct BottleRunStateTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("A wineserver nothing Whisky launched accounts for is orphaned")
    func wineserverWithoutSessionIsOrphaned() {
        let state = BottleRunState.resolve(trackedCount: 0, lastLaunch: nil, wineserverRunning: true, now: now)
        #expect(state == .orphaned)
        #expect(!state.isRunning)
        #expect(state.badgeCount == 0)
    }

    @Test("A game Whisky launched is running, not orphaned, after its launcher process exited")
    func launchedGameIsRunning() {
        // Minutes after the launch: `wine start` is long gone, the wineserver is up.
        let state = BottleRunState.resolve(
            trackedCount: 1, lastLaunch: now.addingTimeInterval(-600), wineserverRunning: true, now: now
        )
        #expect(state == .running(trackedCount: 1))
        #expect(state.isRunning)
        #expect(state.badgeCount == 1)
    }

    @Test("A session with no tracked launches left still runs, and still shows a badge")
    func sessionWithoutTrackedLaunchesIsRunning() {
        let state = BottleRunState.resolve(
            trackedCount: 0, lastLaunch: now.addingTimeInterval(-3_600), wineserverRunning: true, now: now
        )
        #expect(state == .running(trackedCount: 0))
        #expect(state.badgeCount == 1)
    }

    @Test("Tracked launches count even without a recorded session")
    func trackedLaunchesWithoutSessionAreRunning() {
        let state = BottleRunState.resolve(trackedCount: 3, lastLaunch: nil, wineserverRunning: true, now: now)
        #expect(state == .running(trackedCount: 3))
        #expect(state.badgeCount == 3)
    }

    @Test("A launch still starting runs before its wineserver is up")
    func freshLaunchWithoutWineserverIsRunning() {
        let state = BottleRunState.resolve(
            trackedCount: 1, lastLaunch: now.addingTimeInterval(-2), wineserverRunning: false, now: now
        )
        #expect(state == .running(trackedCount: 1))
    }

    @Test("Once the startup window has passed, an idle wineserver ends the session")
    func staleLaunchWithoutWineserverIsIdle() {
        let atBoundary = BottleRunState.resolve(
            trackedCount: 1,
            lastLaunch: now.addingTimeInterval(-BottleRunState.startupGrace),
            wineserverRunning: false,
            now: now
        )
        #expect(atBoundary == .idle)

        let later = BottleRunState.resolve(
            trackedCount: 2, lastLaunch: now.addingTimeInterval(-600), wineserverRunning: false, now: now
        )
        #expect(later == .idle)
        #expect(!later.isRunning)
        #expect(later.badgeCount == 0)
    }

    @Test("Nothing launched and no wineserver is idle")
    func nothingIsIdle() {
        #expect(BottleRunState.resolve(trackedCount: 0, lastLaunch: nil, wineserverRunning: false) == .idle)
    }

    @Test("The startup window can be narrowed")
    func customGrace() {
        let state = BottleRunState.resolve(
            trackedCount: 0, lastLaunch: now.addingTimeInterval(-5), wineserverRunning: false, now: now, grace: 3
        )
        #expect(state == .idle)
    }
}
