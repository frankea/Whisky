//
//  CrashLogCheckTests.swift
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

final class CrashLogCheckTests: XCTestCase {
    private let dllLine =
        "0024:err:module:import_dll Library MSVCR100.dll (which is needed by L\"game.exe\") not found"

    private func runCheck(
        log: String,
        params: [String: String] = [:],
        runStartedAt: Date? = nil,
        fixAttempts: [FixAttempt] = []
    ) async throws -> CheckResult {
        let logURL = FileManager.default.temporaryDirectory
            .appending(path: "crash-log-check-\(UUID().uuidString).log")
        try log.write(to: logURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: logURL) }

        let bottleURL = URL(filePath: "/tmp/test-bottle-\(UUID().uuidString)")
        let preflight = PreflightData(
            bottleURL: bottleURL,
            bottleName: "Test Bottle",
            isWineserverRunning: false,
            processCount: 0,
            recentLogURL: logURL,
            recentRunStartTime: runStartedAt,
            graphicsBackend: "dxmt"
        )
        var session = TroubleshootingSession(bottleURL: bottleURL)
        session.fixAttempts = fixAttempts
        let context = CheckContext(
            bottleURL: bottleURL,
            bottleName: "Test Bottle",
            programName: nil,
            preflight: preflight,
            session: session
        )
        return await CrashLogCheck().run(params: params, context: context)
    }

    // MARK: - A launch after a fix

    private let afterEnhanced = ["newerThanFix": "run-enhanced-diagnostics"]

    private func enhancedDiagnostics(appliedAt date: Date) -> FixAttempt {
        var attempt = FixAttempt(fixId: "run-enhanced-diagnostics", timestamp: date, result: .applied)
        attempt.wasApplied = true
        return attempt
    }

    func testLogFromBeforeTheFixIsNotAnalyzed() async throws {
        let appliedAt = Date()
        let result = try await runCheck(
            log: dllLine,
            params: afterEnhanced,
            runStartedAt: appliedAt.addingTimeInterval(-60),
            fixAttempts: [enhancedDiagnostics(appliedAt: appliedAt)]
        )

        XCTAssertEqual(result.outcome, .unknown, "the old log has no enhanced output to report on")
        XCTAssertEqual(result.summary, CrashLogCheck.noNewRunSummary)
        XCTAssertEqual(
            CrashLogCheck.localizedSummary(for: result),
            String(localized: "troubleshooting.check.crashLog.noNewRun")
        )
    }

    func testLogFromALaunchAfterTheFixIsAnalyzed() async throws {
        let appliedAt = Date()
        let result = try await runCheck(
            log: dllLine,
            params: afterEnhanced,
            runStartedAt: appliedAt.addingTimeInterval(60),
            fixAttempts: [enhancedDiagnostics(appliedAt: appliedAt)]
        )

        XCTAssertEqual(result.outcome, .fail)
    }

    func testRunOfUnknownStartOrWithoutTheFixIsNotAnalyzed() async throws {
        let unknownStart = try await runCheck(
            log: dllLine, params: afterEnhanced, fixAttempts: [enhancedDiagnostics(appliedAt: Date())]
        )
        XCTAssertEqual(unknownStart.outcome, .unknown)

        let neverApplied = try await runCheck(log: dllLine, params: afterEnhanced, runStartedAt: Date())
        XCTAssertEqual(neverApplied.outcome, .unknown)
    }

    func testFailStoresLanguageNeutralEvidence() async throws {
        let result = try await runCheck(log: dllLine)
        let diagnosis = CrashClassifier().classify(log: dllLine)

        XCTAssertEqual(result.outcome, .fail)
        XCTAssertEqual(result.evidence["primaryCategory"], CrashCategory.dependenciesLoading.rawValue)
        XCTAssertEqual(result.evidence["confidence"], diagnosis.primaryConfidence?.rawValue)
        XCTAssertEqual(result.evidence["captures"], "MSVCR100.dll")
        // The summary and headline stay English for history and exports.
        XCTAssertEqual(result.summary, diagnosis.headline)
        XCTAssertEqual(result.evidence["headline"], diagnosis.headline)
        XCTAssertTrue(result.summary.hasPrefix(CrashCategory.dependenciesLoading.exportName))
    }

    func testLocalizedSummaryRebuildsTheHeadline() async throws {
        let result = try await runCheck(log: dllLine)
        let diagnosis = CrashClassifier().classify(log: dllLine)

        let summary = try XCTUnwrap(CrashLogCheck.localizedSummary(for: result))
        XCTAssertEqual(summary, diagnosis.displayHeadline)
        XCTAssertTrue(summary.contains("MSVCR100.dll"))
    }

    func testLocalizedEvidenceMapsRawValuesAndDropsCaptures() async throws {
        let result = try await runCheck(log: dllLine)
        let diagnosis = CrashClassifier().classify(log: dllLine)

        let evidence = CrashLogCheck.localizedEvidence(for: result)
        XCTAssertEqual(evidence["primaryCategory"], CrashCategory.dependenciesLoading.displayName)
        XCTAssertEqual(evidence["confidence"], diagnosis.primaryConfidence?.localizedName)
        XCTAssertEqual(evidence["headline"], diagnosis.displayHeadline)
        XCTAssertNil(evidence["captures"])
        XCTAssertEqual(evidence["matchCount"], result.evidence["matchCount"])
    }

    func testFailWithUnreadableEvidenceFallsBack() {
        let headlineOnly = CheckResult(
            outcome: .fail,
            evidence: ["headline": "Graphics (High confidence)"],
            summary: "Graphics (High confidence)"
        )
        XCTAssertNil(CrashLogCheck.localizedSummary(for: headlineOnly))

        let bare = CheckResult(outcome: .fail, evidence: [:], summary: "Crash patterns detected")
        XCTAssertEqual(
            CrashLogCheck.localizedSummary(for: bare),
            String(localized: "troubleshooting.check.crashLog.detected")
        )
    }
}
