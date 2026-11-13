//
//  LocalizedCheckSummaryTestsB.swift
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

/// On-screen summaries of the diagnostics and game config checks.
final class LocalizedDiagnosticsGameSummaryTests: XCTestCase {
    // MARK: - DiagnosticsEnhanceCheck

    func testDiagnosticsDefaultBottleIsTheAvailableKey() async throws {
        let result = try await DiagnosticsEnhanceCheck().run(params: [:], context: CheckSummaryFixture.bottle(self))

        XCTAssertEqual(result.outcome, .pass)
        XCTAssertEqual(result.evidence["currentPreset"], "normal")
        XCTAssertEqual(result.summary, "Enhanced diagnostics available for more detailed logging")
        assertSummaryLookup(
            DiagnosticsEnhanceCheck.localizedSummary(for: result),
            "troubleshooting.check.diagnostics.available"
        )
    }

    func testDiagnosticsUnreadableSettingsIsLocalized() async throws {
        let context = try CheckSummaryFixture.corruptBottle(self)
        let result = await DiagnosticsEnhanceCheck().run(params: [:], context: context)

        XCTAssertEqual(result.outcome, .error)
        assertSummaryLookup(
            DiagnosticsEnhanceCheck.localizedSummary(for: result),
            "troubleshooting.check.settingsUnreadable"
        )
    }

    func testDiagnosticsActivePresetShowsDisplayNameNotExportName() {
        var summaries: Set<String> = []
        for preset in [WineDebugPreset.crash, .dllLoad, .verbose] {
            // The evidence the check writes: the English export name and the WINEDEBUG
            // value. Built by hand because no bottle setting puts WINEDEBUG in the
            // environment this check reads, so `run` can't reach this branch.
            let result = CheckResult(
                outcome: .alreadyConfigured,
                evidence: ["currentPreset": preset.exportName, "winedebug": preset.winedebugValue],
                summary: "Enhanced diagnostics already active: \(preset.exportName)"
            )
            let summary = DiagnosticsEnhanceCheck.localizedSummary(for: result)
            assertSummaryLookup(summary, "troubleshooting.check.diagnostics.active %@", preset.displayName)
            assertCatalogKey(preset.displayName)
            XCTAssertEqual(summary?.contains(preset.exportName), false, String(describing: summary))
            summaries.insert(summary ?? "")
        }
        XCTAssertEqual(summaries.count, 3, "each preset needs its own name")
    }

    func testDiagnosticsUnrecognizedWinedebugFallsBackToStoredPresetName() {
        let custom = CheckResult(
            outcome: .alreadyConfigured,
            evidence: ["currentPreset": "Custom", "winedebug": "+relay"],
            summary: "x"
        )
        let bare = CheckResult(outcome: .alreadyConfigured, evidence: ["winedebug": "+relay"], summary: "x")

        assertSummaryLookup(
            DiagnosticsEnhanceCheck.localizedSummary(for: custom),
            "troubleshooting.check.diagnostics.active %@",
            "Custom"
        )
        XCTAssertNil(DiagnosticsEnhanceCheck.localizedSummary(for: bare))
    }

    func testDiagnosticsFailAndUnknownFallBack() {
        XCTAssertNil(DiagnosticsEnhanceCheck.localizedSummary(for: CheckResult(outcome: .fail, summary: "x")))
        XCTAssertNil(DiagnosticsEnhanceCheck.localizedSummary(for: CheckResult(outcome: .unknown, summary: "x")))
    }

    // MARK: - GameConfigAvailableCheck

    func testGameConfigWithoutProgramIsTheNoProgramKey() async {
        let result = await GameConfigAvailableCheck().run(params: [:], context: makeCheckContext())

        XCTAssertEqual(result.summary, "No program specified for game matching")
        assertSummaryLookup(
            GameConfigAvailableCheck.localizedSummary(for: result),
            "troubleshooting.check.gameConfig.noProgram"
        )
    }

    func testGameConfigEmptyDatabaseSummaryIsTheEmptyDatabaseKey() {
        // The bundled database is never empty in a test; this is what the check returns if it were.
        let result = CheckResult(outcome: .unknown, summary: "Game database is empty")

        assertSummaryLookup(
            GameConfigAvailableCheck.localizedSummary(for: result),
            "troubleshooting.check.gameConfig.emptyDatabase"
        )
    }

    func testGameConfigUnknownWithAnotherSummaryFallsBack() {
        let result = CheckResult(outcome: .unknown, summary: "Something else")

        XCTAssertNil(GameConfigAvailableCheck.localizedSummary(for: result))
    }

    func testGameConfigNoMatchNamesTheProgram() async {
        let program = "definitely-not-a-real-game-zzz.exe"
        let context = makeCheckContext(programName: program)
        let result = await GameConfigAvailableCheck().run(params: [:], context: context)

        XCTAssertEqual(result.outcome, .fail)
        XCTAssertEqual(result.summary, "No known game configuration for \(program)")
        assertSummaryLookup(
            GameConfigAvailableCheck.localizedSummary(for: result),
            "troubleshooting.check.gameConfig.none %@",
            program
        )
    }

    func testGameConfigMatchNamesTheGameAndLocalizesTheRating() async {
        let result = await GameConfigAvailableCheck().run(
            params: [:],
            context: makeCheckContext(programName: "eldenring.exe")
        )

        XCTAssertEqual(result.outcome, .pass)
        XCTAssertEqual(result.summary, "Known config available: Elden Ring")
        XCTAssertEqual(result.evidence["rating"], CompatibilityRating.playable.displayName)
        assertCatalogKey(result.evidence["rating"] ?? "")
        assertSummaryLookup(
            GameConfigAvailableCheck.localizedSummary(for: result),
            "troubleshooting.check.gameConfig.available %@",
            "Elden Ring"
        )
    }

    func testGameConfigMissingEvidenceAndOtherOutcomesFallBack() {
        XCTAssertNil(GameConfigAvailableCheck.localizedSummary(for: CheckResult(outcome: .fail, summary: "x")))
        XCTAssertNil(GameConfigAvailableCheck.localizedSummary(for: CheckResult(outcome: .pass, summary: "x")))
        let configured = CheckResult(outcome: .alreadyConfigured, evidence: ["gameName": "G"], summary: "x")
        XCTAssertNil(GameConfigAvailableCheck.localizedSummary(for: configured))
        let error = CheckResult(outcome: .error, evidence: ["programName": "p"], summary: "x")
        XCTAssertNil(GameConfigAvailableCheck.localizedSummary(for: error))
    }
}
