//
//  TroubleshootingChecksTests.swift
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

/// A check stub whose outcome is driven entirely by its params, so registry
/// and engine tests never touch a real diagnostic.
struct StubCheck: TroubleshootingCheck {
    let checkId: String

    func run(params: [String: String], context _: CheckContext) async -> CheckResult {
        CheckResult(
            outcome: CheckOutcome(rawValue: params["outcome"] ?? "pass") ?? .pass,
            evidence: ["stub": "true"],
            summary: "stub result"
        )
    }
}

/// Builds a hermetic check context: all inputs injected, nothing read from
/// the machine running the tests.
func makeCheckContext(
    graphicsBackend: String = "dxmt",
    launcherType: String? = nil,
    programName: String? = nil
) -> CheckContext {
    let bottleURL = URL(filePath: "/tmp/test-bottle-\(UUID().uuidString)")
    let preflight = PreflightData(
        bottleURL: bottleURL,
        bottleName: "Test Bottle",
        programName: programName,
        launcherType: launcherType,
        isWineserverRunning: false,
        processCount: 0,
        graphicsBackend: graphicsBackend
    )
    return CheckContext(
        bottleURL: bottleURL,
        bottleName: "Test Bottle",
        programName: programName,
        preflight: preflight,
        session: TroubleshootingSession(bottleURL: bottleURL)
    )
}

final class TroubleshootingChecksTests: XCTestCase {
    // MARK: - CheckRegistry

    func testUnknownCheckIdReturnsErrorResultInsteadOfCrashing() async {
        let registry = CheckRegistry()

        let result = await registry.run(checkId: "no.such_check", params: [:], context: makeCheckContext())

        XCTAssertEqual(result.outcome, .error)
        XCTAssertTrue(result.summary.contains("no.such_check"))
    }

    func testRegisteredCheckRuns() async {
        let registry = CheckRegistry()
        registry.register(StubCheck(checkId: "stub.custom"))

        let result = await registry.run(
            checkId: "stub.custom",
            params: ["outcome": "fail"],
            context: makeCheckContext()
        )

        XCTAssertEqual(result.outcome, .fail)
        XCTAssertEqual(result.evidence["stub"], "true")
    }

    func testReRegisteringSameIdReplacesSilently() async {
        struct FixedCheck: TroubleshootingCheck {
            let checkId = "stub.replace"
            let outcome: CheckOutcome
            func run(params _: [String: String], context _: CheckContext) async -> CheckResult {
                CheckResult(outcome: outcome, summary: "fixed")
            }
        }
        let registry = CheckRegistry()
        registry.register(FixedCheck(outcome: .pass))
        registry.register(FixedCheck(outcome: .unknown))

        let result = await registry.run(checkId: "stub.replace", params: [:], context: makeCheckContext())

        XCTAssertEqual(result.outcome, .unknown)
    }

    // MARK: - GraphicsBackendCheck

    func testGraphicsBackendCheckMissingParamIsError() async {
        let result = await GraphicsBackendCheck().run(params: [:], context: makeCheckContext())

        XCTAssertEqual(result.outcome, .error)
    }

    func testGraphicsBackendCheckMatchIsAlreadyConfigured() async {
        let result = await GraphicsBackendCheck().run(
            params: ["expected": "dxmt"],
            context: makeCheckContext(graphicsBackend: "dxmt")
        )

        XCTAssertEqual(result.outcome, .alreadyConfigured)
        XCTAssertEqual(result.evidence["current"], "dxmt")
        XCTAssertEqual(result.confidence, .high)
    }

    func testGraphicsBackendCheckMismatchIsFail() async {
        let result = await GraphicsBackendCheck().run(
            params: ["expected": "dxvk"],
            context: makeCheckContext(graphicsBackend: "wined3d")
        )

        XCTAssertEqual(result.outcome, .fail)
        XCTAssertEqual(result.evidence["current"], "wined3d")
        XCTAssertEqual(result.evidence["expected"], "dxvk")
    }

    // MARK: - LauncherTypeCheck

    func testLauncherTypeCheckNoLauncherIsUnknown() async {
        let result = await LauncherTypeCheck().run(params: [:], context: makeCheckContext(launcherType: nil))

        XCTAssertEqual(result.outcome, .unknown)
        XCTAssertEqual(result.confidence, .low)
    }

    func testLauncherTypeCheckDetectedWithoutExpectationIsPass() async {
        let result = await LauncherTypeCheck().run(params: [:], context: makeCheckContext(launcherType: "steam"))

        XCTAssertEqual(result.outcome, .pass)
        XCTAssertEqual(result.evidence["detectedLauncher"], "steam")
    }

    func testLauncherTypeCheckExpectationMatchesCaseInsensitively() async {
        let result = await LauncherTypeCheck().run(
            params: ["expected": "Steam"],
            context: makeCheckContext(launcherType: "steam")
        )

        XCTAssertEqual(result.outcome, .pass)
    }

    func testLauncherTypeCheckExpectationMismatchIsFail() async {
        let result = await LauncherTypeCheck().run(
            params: ["expected": "epic"],
            context: makeCheckContext(launcherType: "steam")
        )

        XCTAssertEqual(result.outcome, .fail)
        XCTAssertEqual(result.evidence["expected"], "epic")
    }

    // MARK: - ProcessRunningCheck

    func testProcessRunningCheckNoProcessesIsFail() async {
        // The context's bottle URL is unique per test, so the shared process
        // registry has no entries for it.
        let result = await ProcessRunningCheck().run(params: [:], context: makeCheckContext())

        XCTAssertEqual(result.outcome, .fail)
        XCTAssertEqual(result.evidence["count"], "0")
    }

    // MARK: - GameConfigAvailableCheck

    func testGameConfigCheckWithoutProgramIsUnknown() async {
        let result = await GameConfigAvailableCheck().run(params: [:], context: makeCheckContext())

        XCTAssertEqual(result.outcome, .unknown)
    }

    func testGameConfigCheckUnknownProgramIsFail() async {
        let result = await GameConfigAvailableCheck().run(
            params: [:],
            context: makeCheckContext(programName: "definitely-not-a-real-game-zzz.exe")
        )

        XCTAssertEqual(result.outcome, .fail)
        XCTAssertEqual(result.evidence["programName"], "definitely-not-a-real-game-zzz.exe")
    }
}
