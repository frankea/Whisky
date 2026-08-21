//
//  MacOSFixScopingTests.swift
//  WhiskyKit
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

/// Sequoia-era workarounds had a lower version bound and no upper one, so they kept firing on
/// every later release. These pin the scoping down in both directions.
final class MacOSFixScopingTests: XCTestCase {
    private let sequoia = MacOSVersion(major: 15, minor: 5, patch: 0)
    private let tahoe = MacOSVersion(major: 26, minor: 0, patch: 0)
    private let goldenGate = MacOSVersion(major: 27, minor: 0, patch: 0)

    private func keys(on version: MacOSVersion) -> Set<String> {
        Set(MacOSCompatibilityFixes.activeFixes(for: version).map(\.key))
    }

    /// The five workarounds written for specific 15.x bugs.
    private static let sequoiaScoped = [
        "MTL_DEBUG_LAYER",
        "D3DM_VALIDATION",
        "WINE_DISABLE_NTDLL_THREAD_REGS",
        "WINEFSYNC",
        "WINE_ENABLE_PIPE_SYNC_FOR_APP"
    ]

    func testSequoiaStillGetsItsWorkarounds() {
        let active = keys(on: sequoia)
        for key in Self.sequoiaScoped {
            XCTAssertTrue(active.contains(key), "\(key) should still apply on macOS 15.x")
        }
    }

    /// The regression this scoping exists to prevent: disabling fsync and Metal validation on a
    /// release that never had the bug, which costs performance for nothing.
    func testTahoeAndLaterDoNotGetSequoiaWorkarounds() {
        for version in [tahoe, goldenGate] {
            let active = keys(on: version)
            for key in Self.sequoiaScoped {
                XCTAssertFalse(
                    active.contains(key),
                    "\(key) is a Sequoia workaround and must not apply on macOS \(version.description)"
                )
            }
        }
    }

    /// The CEF sandbox cannot work under Wine on any release, so those two are genuinely
    /// universal and must survive the scoping change.
    func testUniversalFixesStillApplyEverywhere() {
        for version in [sequoia, tahoe, goldenGate] {
            let active = keys(on: version)
            XCTAssertTrue(active.contains("CEF_DISABLE_SANDBOX"), "on \(version.description)")
            XCTAssertTrue(active.contains("STEAM_DISABLE_CEF_SANDBOX"), "on \(version.description)")
        }
    }

    // MARK: - Bounds

    func testFixAppliesFromItsLowerBoundInclusive() {
        let fix = MacOSFix(
            key: "K", value: "1", reason: "r",
            appliesFrom: .sequoia15_4, appliesUntil: nil, category: .graphics
        )
        XCTAssertFalse(fix.applies(to: .sequoia15_3))
        XCTAssertTrue(fix.applies(to: .sequoia15_4))
        XCTAssertTrue(fix.applies(to: goldenGate), "no upper bound means it never expires")
    }

    func testUpperBoundIsExclusive() {
        let boundary = MacOSVersion(major: 16, minor: 0, patch: 0)
        let fix = MacOSFix(
            key: "K", value: "1", reason: "r",
            appliesFrom: .sequoia15_3, appliesUntil: boundary, category: .graphics
        )
        XCTAssertTrue(fix.applies(to: sequoia))
        XCTAssertFalse(fix.applies(to: boundary), "the upper bound itself must not apply")
        XCTAssertFalse(fix.applies(to: tahoe))
    }

    // MARK: - Version helper

    func testSequoiaDetectionSpansTheVersionJump() {
        // macOS went 15 -> 26, so nothing exists between; the boundary is still major < 16.
        XCTAssertTrue(MacOSVersion(major: 15, minor: 0, patch: 0).isSequoiaOrEarlier)
        XCTAssertTrue(MacOSVersion(major: 14, minor: 7, patch: 2).isSequoiaOrEarlier)
        XCTAssertFalse(tahoe.isSequoiaOrEarlier)
        XCTAssertFalse(goldenGate.isSequoiaOrEarlier)
    }
}
