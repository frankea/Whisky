//
//  SteamProcessWatchTests.swift
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

/// Scripts the process-list responses, returning each set once and the last
/// set forever after.
private actor ProcessScript {
    private var responses: [Set<String>]

    init(_ responses: [Set<String>]) {
        self.responses = responses
    }

    func next() -> Set<String> {
        responses.count > 1 ? responses.removeFirst() : responses.first ?? []
    }
}

@Suite("SteamProcessWatch Tests")
struct SteamProcessWatchTests {
    private func makeWatch(
        responses: [Set<String>],
        pollInterval: Duration = .milliseconds(5)
    ) -> SteamProcessWatch {
        let script = ProcessScript(responses)
        return SteamProcessWatch(pollInterval: pollInterval) {
            await script.next()
        }
    }

    @Test("Reports true when the process appears before the timeout")
    func appearsBeforeTimeout() async {
        // The wait returns on the third poll, so the timeout only bounds a failure.
        // Keep it generous: a loaded CI runner can delay the 5 ms sleeps for
        // over a second, which ran a 1 s deadline out before the third poll.
        let watch = makeWatch(responses: [[], [], ["steam.exe", "svchost.exe"]])

        let found = await watch.waitForAny(of: ["steam.exe"], timeout: 30)

        #expect(found)
    }

    @Test("Times out when the process never appears")
    func timesOut() async {
        let watch = makeWatch(responses: [["svchost.exe"]])

        let found = await watch.waitForAny(of: ["game.exe"], timeout: 0.05)

        #expect(!found)
    }

    @Test("Empty name set has nothing to wait for")
    func emptyNames() async {
        let watch = makeWatch(responses: [[]])

        #expect(await watch.waitForAny(of: [], timeout: 0))
    }

    @Test("Checks at least once even with a zero timeout")
    func zeroTimeoutStillChecks() async {
        let watch = makeWatch(responses: [["game.exe"]])

        #expect(await watch.waitForAny(of: ["game.exe"], timeout: 0))
    }

    @Test("Cancellation ends the wait instead of running the timeout out")
    func cancellationEndsTheWait() async {
        let watch = makeWatch(responses: [["svchost.exe"]], pollInterval: .milliseconds(20))
        let timeout: TimeInterval = 60

        let started = Date()
        let task = Task { await watch.waitForAny(of: ["game.exe"], timeout: timeout) }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()

        #expect(await task.value == false)
        // A wait that ignored the cancel would run to the timeout, so any bound short
        // of it proves the cancel ended the wait. Half of it leaves room for a loaded
        // runner, which can hold this test's continuation for several seconds.
        #expect(Date().timeIntervalSince(started) < timeout / 2)
    }

    @Test("Maps running processes back to their keys")
    func mapsRunningKeys() async {
        let watch = makeWatch(responses: [["casualtiesunknown.exe", "steam.exe"]])

        let running = await watch.runningKeys(byExecutables: [
            4_576_510: ["casualtiesunknown.exe"],
            1_245_620: ["eldenring.exe"]
        ])

        #expect(running == [4_576_510])
    }
}
