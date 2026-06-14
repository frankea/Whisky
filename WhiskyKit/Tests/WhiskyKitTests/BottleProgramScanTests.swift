//
//  BottleProgramScanTests.swift
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
@testable import WhiskyKit
import XCTest

/// Shared mutable state for the coalescing tests. `@MainActor` because every
/// access happens from a main-actor test closure, which keeps the mutable
/// captures legal under strict concurrency without a `var` capture dance.
@MainActor
private final class ScanProbe {
    var runCount = 0
    var published: String?
    var resume: CheckedContinuation<Void, Never>?
}

/// Tests for ``Bottle/coalesceProgramScan(_:)`` — the wrapper that makes
/// `updateInstalledPrograms()` coalesce concurrent rescans instead of dropping
/// them. These pin the contract so a future "simplification" back to an
/// early-return guard (which reintroduces the stale-`programs` bug behind the
/// Start Menu auto-pin) fails loudly.
final class BottleProgramScanTests: XCTestCase {
    var tempDir: URL!
    var bottleURL: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appending(path: "bottle_scan_test_\(UUID().uuidString)")
        bottleURL = tempDir.appending(path: "TestBottle")
        let driveCURL = bottleURL.appending(path: "drive_c")
        try? FileManager.default.createDirectory(at: driveCURL, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    /// Spins (yielding the main actor) until `predicate` holds, with a bounded
    /// ceiling so a broken implementation fails the test instead of hanging CI.
    @MainActor
    private func spinUntil(
        _ predicate: () -> Bool,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        var spins = 0
        while !predicate() {
            await Task.yield()
            spins += 1
            if spins > 10_000 {
                XCTFail(message, file: file, line: line)
                return
            }
        }
    }

    /// Two callers overlapping in time share a single scan run.
    @MainActor
    func testConcurrentCallersCoalesceToSingleScan() async {
        let bottle = Bottle(bottleUrl: bottleURL)
        let probe = ScanProbe()

        // Owner: runs the body, then parks so its scan is still in flight when
        // the second caller arrives.
        let owner = Task { @MainActor in
            await bottle.coalesceProgramScan {
                probe.runCount += 1
                await withCheckedContinuation { probe.resume = $0 }
            }
        }
        await spinUntil({ probe.resume != nil }, "Owning scan never started")
        XCTAssertEqual(probe.runCount, 1)

        // Second caller arrives mid-scan; it must coalesce, not start a new body.
        let coalesced = Task { @MainActor in
            await bottle.coalesceProgramScan {
                probe.runCount += 1
            }
        }
        await Task.yield()

        // Release the owner; both tasks finish.
        probe.resume?.resume()
        await owner.value
        await coalesced.value

        XCTAssertEqual(probe.runCount, 1, "Concurrent callers must share one scan run")
    }

    /// A coalesced caller observes the in-flight scan's published result rather
    /// than the value that predated it — the exact guarantee the Start Menu
    /// auto-pin relies on.
    @MainActor
    func testCoalescedCallerObservesScanResult() async {
        let bottle = Bottle(bottleUrl: bottleURL)
        let probe = ScanProbe()

        let owner = Task { @MainActor in
            await bottle.coalesceProgramScan {
                await withCheckedContinuation { probe.resume = $0 }
                probe.published = "fresh" // published only as the scan completes
            }
        }
        await spinUntil({ probe.resume != nil }, "Owning scan never started")

        let coalesced = Task { @MainActor in
            await bottle.coalesceProgramScan {}
            return probe.published
        }
        await Task.yield()

        probe.resume?.resume()
        await owner.value
        let observed = await coalesced.value

        XCTAssertEqual(observed, "fresh", "Coalesced caller must see the scan's published result, not a stale value")
    }

    /// Once a scan completes the handle is cleared, so a later call runs a fresh
    /// scan rather than being permanently suppressed.
    @MainActor
    func testSequentialCallsEachRunScan() async {
        let bottle = Bottle(bottleUrl: bottleURL)
        let probe = ScanProbe()

        await bottle.coalesceProgramScan { probe.runCount += 1 }
        await bottle.coalesceProgramScan { probe.runCount += 1 }

        XCTAssertEqual(probe.runCount, 2, "Each sequential call runs its own scan once the handle clears")
    }
}
