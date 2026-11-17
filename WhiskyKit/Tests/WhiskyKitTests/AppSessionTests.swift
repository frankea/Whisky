//
//  AppSessionTests.swift
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

@Suite("Startup sweep of what the last run left running")
struct StartupOrphanSweepTests {
    private let bottle = URL(fileURLWithPath: "/Users/test/Library/Containers/Whisky/Bottles/A")
    private let otherBottle = URL(fileURLWithPath: "/Users/test/Library/Containers/Whisky/Bottles/B")
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func crashedRun(launchedIn bottles: [URL]) -> AppSessionRecord {
        AppSessionRecord(
            startedAt: start, endedCleanly: false, bottlePaths: Set(bottles.map(AppSessionRecord.key(for:)))
        )
    }

    private func action(
        for url: URL? = nil,
        running: Bool = true,
        stopsOnQuit: Bool = true,
        previous: AppSessionRecord?,
        launchedThisSession: Bool = false
    ) -> StartupOrphanSweep.Action {
        StartupOrphanSweep.action(
            for: url ?? bottle,
            wineserverRunning: running,
            stopsOnQuit: stopsOnQuit,
            previousSession: previous,
            launchedThisSession: launchedThisSession
        )
    }

    @Test("A bottle a crashed run launched in is stopped, as its quit would have")
    func crashedRunsBottleIsStopped() {
        #expect(action(previous: crashedRun(launchedIn: [bottle])) == .stop)
    }

    @Test("A bottle the crashed run never launched in is left running (whisky run, shortcuts, Terminal)")
    func bottleStartedOutsideTheAppIsLeft() {
        #expect(action(previous: crashedRun(launchedIn: [otherBottle])) == .leave)
        #expect(action(previous: crashedRun(launchedIn: [])) == .leave)
    }

    @Test("Nothing is stopped after a clean quit, which already applied the policy")
    func cleanQuitStopsNothing() {
        var record = crashedRun(launchedIn: [bottle])
        record.endedCleanly = true
        #expect(action(previous: record) == .leave)
    }

    @Test("Nothing is stopped on the first run, with no record of a previous one")
    func firstRunStopsNothing() {
        #expect(action(previous: nil) == .leave)
    }

    @Test("A bottle whose policy keeps it running on quit is left running")
    func neverKillPolicyIsRespected() {
        #expect(action(stopsOnQuit: false, previous: crashedRun(launchedIn: [bottle])) == .leave)
    }

    @Test("A bottle without a running wineserver needs nothing")
    func idleBottleIsLeft() {
        #expect(action(running: false, previous: crashedRun(launchedIn: [bottle])) == .leave)
    }

    @Test("A game this run already launched (whisky:// link, Dock pin) is left running")
    func thisRunsLaunchIsLeft() {
        #expect(action(previous: crashedRun(launchedIn: [bottle]), launchedThisSession: true) == .leave)
    }

    @Test("Bottle paths match however the URL is spelled")
    func pathsAreStandardized() {
        let spelled = URL(fileURLWithPath: "/Users/test/Library/Containers/Whisky/Bottles/x/../A/")
        #expect(action(for: spelled, previous: crashedRun(launchedIn: [bottle])) == .stop)
    }

    @Test("Each kill-on-quit policy applies the global setting the way quit does")
    func policyStopsOnQuit() {
        #expect(KillOnQuitPolicy.inherit.stopsOnQuit(globalKill: true))
        #expect(!KillOnQuitPolicy.inherit.stopsOnQuit(globalKill: false))
        #expect(KillOnQuitPolicy.alwaysKill.stopsOnQuit(globalKill: false))
        #expect(!KillOnQuitPolicy.neverKill.stopsOnQuit(globalKill: true))
    }
}

@Suite("App session record store")
struct AppSessionStoreTests {
    private let bottle = URL(fileURLWithPath: "/tmp/Bottles/A")
    private let otherBottle = URL(fileURLWithPath: "/tmp/Bottles/B")

    private func makeDefaults() throws -> UserDefaults {
        let suite = "AppSessionStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("The first run has no previous record")
    func firstRunHasNoPrevious() throws {
        let store = try AppSessionStore(defaults: makeDefaults())
        #expect(store.begin() == nil)
    }

    @Test("A run that never reached the end of quit reads back as not ended cleanly, with its bottles")
    func crashedRunIsRecorded() throws {
        let defaults = try makeDefaults()
        let first = AppSessionStore(defaults: defaults)
        first.begin(at: Date(timeIntervalSince1970: 100))
        first.setLaunchSession(true, for: bottle)
        first.setLaunchSession(true, for: otherBottle)
        // No endCleanly(): the app died.

        let previous = try #require(AppSessionStore(defaults: defaults).begin())
        #expect(!previous.endedCleanly)
        #expect(previous.startedAt == Date(timeIntervalSince1970: 100))
        #expect(previous.contains(bottle))
        #expect(previous.contains(otherBottle))
    }

    @Test("A bottle whose launch session ended is dropped from the record")
    func endedSessionIsDropped() throws {
        let defaults = try makeDefaults()
        let first = AppSessionStore(defaults: defaults)
        first.begin()
        first.setLaunchSession(true, for: bottle)
        first.setLaunchSession(false, for: bottle)

        let previous = try #require(AppSessionStore(defaults: defaults).begin())
        #expect(!previous.contains(bottle))
    }

    @Test("A clean quit is recorded, and the next run starts its own record")
    func cleanQuitIsRecorded() throws {
        let defaults = try makeDefaults()
        let first = AppSessionStore(defaults: defaults)
        first.begin()
        first.setLaunchSession(true, for: bottle)
        first.endCleanly()

        let second = AppSessionStore(defaults: defaults)
        let previous = try #require(second.begin())
        #expect(previous.endedCleanly)

        // The second run crashes without launching anything: its record is fresh.
        let third = try #require(AppSessionStore(defaults: defaults).begin())
        #expect(!third.endedCleanly)
        #expect(third.bottlePaths.isEmpty)
    }

    @Test("Updates before begin() are ignored")
    func updatesBeforeBeginAreIgnored() throws {
        let defaults = try makeDefaults()
        let store = AppSessionStore(defaults: defaults)
        store.setLaunchSession(true, for: bottle)
        store.endCleanly()
        #expect(defaults.data(forKey: AppSessionStore.defaultsKey) == nil)
    }

    @Test("An unreadable record counts as no previous run")
    func unreadableRecordIsIgnored() throws {
        let defaults = try makeDefaults()
        defaults.set(Data("not a plist".utf8), forKey: AppSessionStore.defaultsKey)
        #expect(AppSessionStore(defaults: defaults).begin() == nil)
    }
}
