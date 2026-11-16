//
//  LocalizedCheckSummaryTestsC.swift
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

/// On-screen summaries of the checks that read bottle settings: DXVK settings,
/// setting values, and environment variables. Each result comes from running
/// the check against a temporary bottle.
final class LocalizedSettingsCheckSummaryTests: XCTestCase {
    // MARK: - DXVKSettingsCheck

    func testDXVKMissingSettingParameterKeepsTheEnglishSummary() async throws {
        let result = try await DXVKSettingsCheck().run(params: [:], context: CheckSummaryFixture.bottle(self))

        XCTAssertEqual(result.outcome, .error)
        XCTAssertEqual(result.summary, "Missing 'setting' parameter")
        XCTAssertNil(DXVKSettingsCheck.localizedSummary(for: result))
    }

    func testDXVKUnreadableSettingsIsLocalized() async throws {
        let context = try CheckSummaryFixture.corruptBottle(self)
        let result = await DXVKSettingsCheck().run(params: ["setting": "async"], context: context)

        XCTAssertEqual(result.summary, "Failed to read bottle settings")
        assertSummaryLookup(DXVKSettingsCheck.localizedSummary(for: result), "troubleshooting.check.settingsUnreadable")
    }

    func testDXVKUnknownSettingNamesTheSetting() async throws {
        let context = try CheckSummaryFixture.bottle(self)
        let result = await DXVKSettingsCheck().run(params: ["setting": "frobnicate"], context: context)

        XCTAssertEqual(result.summary, "Unknown DXVK setting: frobnicate")
        assertSummaryLookup(
            DXVKSettingsCheck.localizedSummary(for: result),
            "troubleshooting.check.dxvk.unknownSetting %@",
            "frobnicate"
        )
    }

    func testDXVKMatchNamesSettingAndValue() async throws {
        let context = try CheckSummaryFixture.bottle(self) { $0.dxvkAsync = true }
        // `expected` defaults to "true".
        let result = await DXVKSettingsCheck().run(params: ["setting": "async"], context: context)

        XCTAssertEqual(result.outcome, .alreadyConfigured)
        XCTAssertEqual(result.summary, "DXVK async is already true")
        assertSummaryLookup(
            DXVKSettingsCheck.localizedSummary(for: result),
            "troubleshooting.check.dxvk.matches %@ %@",
            "async",
            "true"
        )
    }

    func testDXVKMismatchNamesSettingCurrentAndExpected() async throws {
        let context = try CheckSummaryFixture.bottle(self) { $0.dxvkHud = .off }
        let result = await DXVKSettingsCheck().run(params: ["setting": "hud", "expected": "fps"], context: context)

        XCTAssertEqual(result.outcome, .fail)
        XCTAssertEqual(result.summary, "DXVK hud is off, expected fps")
        assertSummaryLookup(
            DXVKSettingsCheck.localizedSummary(for: result),
            "troubleshooting.check.dxvk.mismatch %@ %@ %@",
            "hud",
            "off",
            "fps"
        )
    }

    func testDXVKOtherOutcomesAndPartialEvidenceFallBack() {
        XCTAssertNil(DXVKSettingsCheck.localizedSummary(for: CheckResult(outcome: .pass, summary: "x")))
        XCTAssertNil(DXVKSettingsCheck.localizedSummary(for: CheckResult(outcome: .unknown, summary: "x")))
        let noExpected = CheckResult(outcome: .alreadyConfigured, evidence: ["setting": "async"], summary: "x")
        XCTAssertNil(DXVKSettingsCheck.localizedSummary(for: noExpected))
        let noCurrent = CheckResult(outcome: .fail, evidence: ["setting": "hud", "expected": "fps"], summary: "x")
        XCTAssertNil(DXVKSettingsCheck.localizedSummary(for: noCurrent))
    }

    // MARK: - SettingValueCheck

    func testSettingValueMissingParametersKeepTheEnglishSummary() async throws {
        let context = try CheckSummaryFixture.bottle(self)
        let noSetting = await SettingValueCheck().run(params: ["expected": "true"], context: context)
        let noExpected = await SettingValueCheck().run(params: ["setting": "dxvk"], context: context)

        XCTAssertEqual(noSetting.summary, "Missing 'setting' parameter")
        XCTAssertEqual(noExpected.summary, "Missing 'expected' parameter")
        XCTAssertNil(SettingValueCheck.localizedSummary(for: noSetting))
        XCTAssertNil(SettingValueCheck.localizedSummary(for: noExpected))
    }

    func testSettingValueUnreadableSettingsIsLocalized() async throws {
        let context = try CheckSummaryFixture.corruptBottle(self)
        let result = await SettingValueCheck().run(params: ["setting": "dxvk", "expected": "true"], context: context)

        XCTAssertEqual(result.outcome, .error)
        assertSummaryLookup(SettingValueCheck.localizedSummary(for: result), "troubleshooting.check.settingsUnreadable")
    }

    func testSettingValueUnknownSettingNamesTheSetting() async throws {
        let context = try CheckSummaryFixture.bottle(self)
        let result = await SettingValueCheck().run(params: ["setting": "frobnicate", "expected": "1"], context: context)

        XCTAssertEqual(result.summary, "Unknown setting: frobnicate")
        assertSummaryLookup(
            SettingValueCheck.localizedSummary(for: result),
            "troubleshooting.check.setting.unknown %@",
            "frobnicate"
        )
    }

    func testSettingValueMatchNamesSettingAndValue() async throws {
        let context = try CheckSummaryFixture.bottle(self) { $0.metalHud = true }
        let params = ["setting": "metalHud", "expected": "true"]
        let result = await SettingValueCheck().run(params: params, context: context)

        XCTAssertEqual(result.outcome, .alreadyConfigured)
        XCTAssertEqual(result.summary, "metalHud is already true")
        assertSummaryLookup(
            SettingValueCheck.localizedSummary(for: result),
            "troubleshooting.check.value.matches %@ %@",
            "metalHud",
            "true"
        )
    }

    func testSettingValueMismatchNamesSettingCurrentAndExpected() async throws {
        let context = try CheckSummaryFixture.bottle(self) { $0.audioDriver = .disabled }
        let result = await SettingValueCheck().run(
            params: ["setting": "audioDriver", "expected": "coreaudio"],
            context: context
        )

        XCTAssertEqual(result.outcome, .fail)
        XCTAssertEqual(result.summary, "audioDriver is disabled, expected coreaudio")
        assertSummaryLookup(
            SettingValueCheck.localizedSummary(for: result),
            "troubleshooting.check.value.mismatch %@ %@ %@",
            "audioDriver",
            "disabled",
            "coreaudio"
        )
    }

    func testSettingValueAndDXVKUseTheirOwnKeys() {
        // The same evidence reads differently: DXVK summaries say "DXVK".
        let evidence = ["setting": "async", "current": "false", "expected": "true"]
        for outcome in [CheckOutcome.alreadyConfigured, .fail, .error] {
            let result = CheckResult(outcome: outcome, evidence: evidence, summary: "x")
            let dxvk = DXVKSettingsCheck.localizedSummary(for: result)
            let value = SettingValueCheck.localizedSummary(for: result)
            XCTAssertNotNil(dxvk, "\(outcome)")
            XCTAssertNotEqual(dxvk, value, "\(outcome)")
        }
    }

    func testSettingValueOtherOutcomesAndPartialEvidenceFallBack() {
        XCTAssertNil(SettingValueCheck.localizedSummary(for: CheckResult(outcome: .pass, summary: "x")))
        XCTAssertNil(SettingValueCheck.localizedSummary(for: CheckResult(outcome: .unknown, summary: "x")))
        let noExpected = CheckResult(outcome: .alreadyConfigured, evidence: ["setting": "dxvk"], summary: "x")
        XCTAssertNil(SettingValueCheck.localizedSummary(for: noExpected))
        let noCurrent = CheckResult(outcome: .fail, evidence: ["setting": "dxvk", "expected": "true"], summary: "x")
        XCTAssertNil(SettingValueCheck.localizedSummary(for: noCurrent))
    }

    // MARK: - EnvironmentCheck

    func testEnvironmentMissingKeyParameterKeepsTheEnglishSummary() async throws {
        let result = try await EnvironmentCheck().run(params: [:], context: CheckSummaryFixture.bottle(self))

        XCTAssertEqual(result.outcome, .error)
        XCTAssertEqual(result.summary, "Missing 'key' parameter")
        XCTAssertNil(EnvironmentCheck.localizedSummary(for: result))
    }

    func testEnvironmentUnreadableSettingsIsLocalized() async throws {
        let context = try CheckSummaryFixture.corruptBottle(self)
        let result = await EnvironmentCheck().run(params: ["key": hudKey], context: context)

        assertSummaryLookup(EnvironmentCheck.localizedSummary(for: result), "troubleshooting.check.settingsUnreadable")
    }

    func testEnvironmentMatchNamesKeyAndValue() async throws {
        let context = try CheckSummaryFixture.bottle(self) { $0.metalHud = true }
        let result = await EnvironmentCheck().run(params: ["key": hudKey, "expected": "1"], context: context)

        XCTAssertEqual(result.outcome, .pass)
        XCTAssertEqual(result.summary, "\(hudKey) is set to 1")
        assertSummaryLookup(
            EnvironmentCheck.localizedSummary(for: result),
            "troubleshooting.check.env.matches %@ %@",
            hudKey,
            "1"
        )
    }

    func testEnvironmentSetWithoutExpectationNamesTheKey() async throws {
        let context = try CheckSummaryFixture.bottle(self) { $0.metalHud = true }
        let result = await EnvironmentCheck().run(params: ["key": hudKey], context: context)

        XCTAssertEqual(result.summary, "\(hudKey) is set")
        assertSummaryLookup(EnvironmentCheck.localizedSummary(for: result), "troubleshooting.check.env.set %@", hudKey)
    }

    func testEnvironmentMismatchReusesTheValueMismatchKey() async throws {
        let context = try CheckSummaryFixture.bottle(self) { $0.metalHud = true }
        let result = await EnvironmentCheck().run(params: ["key": hudKey, "expected": "0"], context: context)

        XCTAssertEqual(result.outcome, .fail)
        XCTAssertEqual(result.summary, "\(hudKey) is 1, expected 0")
        assertSummaryLookup(
            EnvironmentCheck.localizedSummary(for: result),
            "troubleshooting.check.value.mismatch %@ %@ %@",
            hudKey,
            "1",
            "0"
        )
    }

    func testEnvironmentUnsetWithExpectationSaysNotSet() async throws {
        let context = try CheckSummaryFixture.bottle(self) { $0.metalHud = false }
        let result = await EnvironmentCheck().run(params: ["key": hudKey, "expected": "1"], context: context)

        XCTAssertNil(result.evidence["currentValue"])
        XCTAssertEqual(result.summary, "\(hudKey) is not set, expected 1")
        assertSummaryLookup(
            EnvironmentCheck.localizedSummary(for: result),
            "troubleshooting.check.env.mismatchUnset %@ %@",
            hudKey,
            "1"
        )
    }

    func testEnvironmentUnsetWithoutExpectationSaysNotSet() async throws {
        let context = try CheckSummaryFixture.bottle(self) { $0.metalHud = false }
        let result = await EnvironmentCheck().run(params: ["key": hudKey], context: context)

        XCTAssertEqual(result.outcome, .fail)
        XCTAssertEqual(result.summary, "\(hudKey) is not set")
        let summary = EnvironmentCheck.localizedSummary(for: result)
        assertSummaryLookup(summary, "troubleshooting.check.env.unset %@", hudKey)
    }

    func testEnvironmentOutcomesItNeverReturnsFallBack() {
        let evidence = ["key": hudKey, "currentValue": "1", "expected": "1"]
        for outcome in [CheckOutcome.alreadyConfigured, .unknown] {
            let result = CheckResult(outcome: outcome, evidence: evidence, summary: "x")
            XCTAssertNil(EnvironmentCheck.localizedSummary(for: result), "\(outcome)")
        }
        XCTAssertNil(EnvironmentCheck.localizedSummary(for: CheckResult(outcome: .pass, summary: "x")))
    }

    // MARK: - Helpers

    /// Set by the bottle layer exactly when the Metal HUD is on, on every backend.
    private let hudKey = "MTL_HUD_ENABLED"
}
