//
//  LocalizedLauncherBackendSummaryTests.swift
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

/// The on-screen summaries of the launcher and graphics backend checks.
///
/// Both checks read the preflight snapshot, so ``makeCheckContext`` drives them
/// hermetically. In the test runner a lookup returns its key with the
/// arguments substituted.
final class LocalizedLauncherBackendSummaryTests: XCTestCase {
    // MARK: - LauncherTypeCheck

    func testLauncherNoneWhenNothingWasDetected() async throws {
        let result = await LauncherTypeCheck().run(params: [:], context: makeCheckContext(launcherType: nil))
        let localized = try XCTUnwrap(LauncherTypeCheck.localizedSummary(for: result))

        XCTAssertEqual(result.outcome, .unknown)
        XCTAssertEqual(localized, "troubleshooting.check.launcher.none")
        assertCatalogKey(localized)
    }

    func testLauncherDetectedWithoutAnExpectation() async throws {
        let result = await LauncherTypeCheck().run(params: [:], context: makeCheckContext(launcherType: "steam"))
        let localized = try XCTUnwrap(LauncherTypeCheck.localizedSummary(for: result))

        XCTAssertEqual(result.outcome, .pass)
        XCTAssertEqual(localized, "troubleshooting.check.launcher.detected steam")
        assertCatalogKey(localized)
    }

    /// A match carries the same evidence as a plain detection; only the
    /// English summary tells them apart, so the two must still map to
    /// different keys.
    func testLauncherMatchingTheExpectationUsesItsOwnKey() async throws {
        let matched = await LauncherTypeCheck().run(
            params: ["expected": "Steam"],
            context: makeCheckContext(launcherType: "steam")
        )
        let detected = await LauncherTypeCheck().run(params: [:], context: makeCheckContext(launcherType: "steam"))
        let localized = try XCTUnwrap(LauncherTypeCheck.localizedSummary(for: matched))

        XCTAssertEqual(matched.outcome, .pass)
        XCTAssertEqual(matched.evidence, detected.evidence)
        XCTAssertEqual(localized, "troubleshooting.check.launcher.matches steam")
        assertCatalogKey(localized)
        XCTAssertNotEqual(
            StringCatalog.stem(localized),
            LauncherTypeCheck.localizedSummary(for: detected).map(StringCatalog.stem)
        )
        XCTAssertEqual(matched.summary, "Launcher detected: steam (matches expected)")
    }

    func testLauncherMismatchNamesTheDetectedAndTheExpectedLauncher() async throws {
        let result = await LauncherTypeCheck().run(
            params: ["expected": "epic"],
            context: makeCheckContext(launcherType: "steam")
        )
        let localized = try XCTUnwrap(LauncherTypeCheck.localizedSummary(for: result))

        XCTAssertEqual(result.outcome, .fail)
        XCTAssertEqual(localized, "troubleshooting.check.launcher.mismatch steam epic")
        assertCatalogKey(localized)
        XCTAssertEqual(result.summary, "Launcher is steam, expected epic")
    }

    func testLauncherHasNoLocalizedSummaryForResultsItDoesNotProduce() {
        let launcher = ["detectedLauncher": "steam"]

        XCTAssertNil(LauncherTypeCheck.localizedSummary(for: CheckResult(outcome: .pass, summary: "")))
        XCTAssertNil(LauncherTypeCheck.localizedSummary(for: CheckResult(outcome: .fail, summary: "")))
        XCTAssertNil(LauncherTypeCheck.localizedSummary(
            for: CheckResult(outcome: .fail, evidence: launcher, summary: "")
        ))
        for outcome in [CheckOutcome.alreadyConfigured, .error, .unknown] {
            XCTAssertNil(
                LauncherTypeCheck.localizedSummary(for: CheckResult(outcome: outcome, evidence: launcher, summary: "")),
                "\(outcome)"
            )
        }
    }

    // MARK: - GraphicsBackendCheck

    func testBackendMatchNamesEveryBackendByItsDisplayName() async throws {
        for backend in GraphicsBackend.allCases {
            let result = await GraphicsBackendCheck().run(
                params: ["expected": backend.rawValue],
                context: makeCheckContext(graphicsBackend: backend.rawValue)
            )
            let localized = try XCTUnwrap(GraphicsBackendCheck.localizedSummary(for: result), "\(backend)")

            XCTAssertEqual(result.outcome, .alreadyConfigured, "\(backend)")
            XCTAssertEqual(localized, "troubleshooting.check.backend.matches \(backend.displayName)")
            assertCatalogKey(localized)
            // Exports keep the raw identifier.
            XCTAssertEqual(result.summary, "Backend is already set to \(backend.rawValue)")
        }
    }

    func testBackendMismatchNamesBothBackendsByDisplayName() async throws {
        let result = await GraphicsBackendCheck().run(
            params: ["expected": "dxvk"],
            context: makeCheckContext(graphicsBackend: "wined3d")
        )
        let localized = try XCTUnwrap(GraphicsBackendCheck.localizedSummary(for: result))

        XCTAssertEqual(result.outcome, .fail)
        XCTAssertEqual(localized, "troubleshooting.check.backend.mismatch WineD3D DXVK")
        assertCatalogKey(localized)
        XCTAssertEqual(result.summary, "Backend is wined3d, expected dxvk")
    }

    func testBackendKeepsAnUnrecognizedIdentifierAsIs() async throws {
        let result = await GraphicsBackendCheck().run(
            params: ["expected": "metalfx"],
            context: makeCheckContext(graphicsBackend: "d3dMetal")
        )

        XCTAssertEqual(
            GraphicsBackendCheck.localizedSummary(for: result),
            "troubleshooting.check.backend.mismatch D3DMetal metalfx"
        )
    }

    func testBackendHasNoLocalizedSummaryForResultsItDoesNotProduce() async {
        let error = await GraphicsBackendCheck().run(params: [:], context: makeCheckContext())
        let expected = ["expected": "dxmt"]

        XCTAssertEqual(error.outcome, .error)
        XCTAssertNil(GraphicsBackendCheck.localizedSummary(for: error))
        XCTAssertNil(GraphicsBackendCheck.localizedSummary(for: CheckResult(outcome: .fail, summary: "")))
        XCTAssertNil(GraphicsBackendCheck.localizedSummary(
            for: CheckResult(outcome: .fail, evidence: expected, summary: "")
        ))
        for outcome in [CheckOutcome.pass, .error, .unknown] {
            let result = CheckResult(outcome: outcome, evidence: expected, summary: "")
            XCTAssertNil(GraphicsBackendCheck.localizedSummary(for: result), "\(outcome)")
        }
    }
}
