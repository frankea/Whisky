//
//  TroubleshootingFlowParamsTests.swift
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

/// Runs checks with the params their shipped flow nodes pass, so a check
/// asked the wrong question (a misnamed param, an expectation no setting can
/// meet) shows up as the wrong outcome.
final class TroubleshootingFlowParamsTests: XCTestCase {
    private func params(flow fileName: String, node nodeId: String) throws -> [String: String] {
        let flow = try XCTUnwrap(FlowLoader.loadFlow(fileName: fileName))
        let node = try XCTUnwrap(flow.nodes[nodeId], "\(fileName) lost \(nodeId)")
        return node.params ?? [:]
    }

    private func preflightContext(
        graphicsBackend: String = "dxvk",
        bottleGraphicsBackend: String? = nil,
        device: String? = "Speakers",
        sampleRate: Double? = nil
    ) -> CheckContext {
        let bottleURL = URL(filePath: "/tmp/flow-params-\(UUID().uuidString)")
        let preflight = PreflightData(
            bottleURL: bottleURL,
            bottleName: "Params",
            isWineserverRunning: false,
            processCount: 0,
            audioDeviceName: device,
            audioTransportType: device == nil ? nil : AudioTransportType.builtIn.exportName,
            audioSampleRate: sampleRate,
            graphicsBackend: graphicsBackend,
            bottleGraphicsBackend: bottleGraphicsBackend
        )
        return CheckContext(
            bottleURL: bottleURL, bottleName: "Params", preflight: preflight,
            session: TroubleshootingSession(bottleURL: bottleURL)
        )
    }

    // MARK: - Graphics

    func testDXVKAsyncCheckReadsTheAsyncSetting() async throws {
        let params = try params(flow: "graphics", node: "check_dxvk_settings")

        let disabled = try CheckSummaryFixture.bottle(self) { $0.dxvkAsync = false }
        let enabled = try CheckSummaryFixture.bottle(self) { $0.dxvkAsync = true }

        let offResult = await DXVKSettingsCheck().run(params: params, context: disabled)
        let onResult = await DXVKSettingsCheck().run(params: params, context: enabled)
        XCTAssertEqual(offResult.outcome, .fail)
        XCTAssertEqual(onResult.outcome, .alreadyConfigured)
    }

    func testBackendCheckComparesTheBackendALaunchUses() async throws {
        let params = try params(flow: "graphics", node: "check_backend")
        XCTAssertEqual(params["scope"], "program_or_bottle")
        let context = preflightContext(graphicsBackend: "dxvk", bottleGraphicsBackend: "d3dMetal")

        let effective = await GraphicsBackendCheck().run(params: params, context: context)
        var bottleParams = params
        bottleParams["scope"] = "bottle"
        let bottleOnly = await GraphicsBackendCheck().run(params: bottleParams, context: context)

        XCTAssertEqual(effective.outcome, .alreadyConfigured, "the program's DXVK override is what runs")
        XCTAssertEqual(bottleOnly.outcome, .fail)
        XCTAssertEqual(bottleOnly.evidence["current"], "d3dMetal")
    }

    // MARK: - Audio

    func testAudioDriverCheckOnlyFailsADisabledDriver() async throws {
        let params = try params(flow: "audio", node: "check_audio_driver")

        for driver in AudioDriverMode.allCases {
            let context = try CheckSummaryFixture.bottle(self) { $0.audioDriver = driver }
            let result = await AudioDriverCheck().run(params: params, context: context)
            XCTAssertEqual(result.outcome, driver == .disabled ? .fail : .alreadyConfigured, "\(driver)")
            if driver == .coreaudio {
                assertSummaryLookup(
                    AudioDriverCheck.localizedSummary(for: result),
                    "troubleshooting.check.audioDriver.matches %@",
                    "CoreAudio"
                )
            }
        }
    }

    func testAudioDriverFixRestoresAnAcceptedDriver() throws {
        let flow = try XCTUnwrap(FlowLoader.loadFlow(fileName: "audio"))
        let fix = try XCTUnwrap(flow.nodes["fix_audio_driver"])
        let accepted = try params(flow: "audio", node: "check_audio_driver")["expected"] ?? ""

        let target = try XCTUnwrap(fix.params?["driver"])
        XCTAssertTrue(accepted.flowParamList.contains(target))
        XCTAssertEqual(fix.fixPreview?.newValue, target)
    }

    func testSampleRateCheckFailsOnlyALowKnownRate() async throws {
        let params = try params(flow: "audio", node: "check_sample_rate")

        let low = await AudioDeviceCheck().run(params: params, context: preflightContext(sampleRate: 22_050))
        let standard = await AudioDeviceCheck().run(params: params, context: preflightContext(sampleRate: 48_000))
        let unknown = await AudioDeviceCheck().run(params: params, context: preflightContext(sampleRate: nil))
        let deviceCheck = await AudioDeviceCheck().run(params: [:], context: preflightContext(sampleRate: 22_050))

        XCTAssertEqual(low.outcome, .fail)
        XCTAssertEqual(low.evidence["recommendedRate"], "44100")
        let lowSummary = AudioDeviceCheck.localizedSummary(for: low)
        XCTAssertEqual(lowSummary, String(localized: "audio.finding.lowSampleRate \(22_050)"))
        assertCatalogKey(lowSummary ?? "")
        XCTAssertEqual(standard.outcome, .pass)
        XCTAssertEqual(standard.evidence["sampleRate"], "48000")
        XCTAssertEqual(unknown.outcome, .pass)
        XCTAssertEqual(deviceCheck.outcome, .pass, "only the sample rate step asks about the rate")
    }

    func testNoDeviceIsStillReportedAsNoDevice() async {
        let result = await AudioDeviceCheck().run(params: [:], context: preflightContext(device: nil))

        XCTAssertEqual(result.outcome, .fail)
        assertSummaryLookup(AudioDeviceCheck.localizedSummary(for: result), "troubleshooting.check.audioDevice.none")
    }

    // MARK: - Performance and controller

    func testEnhancedSyncCheckAcceptsMSyncAndESync() async throws {
        let params = try params(flow: "performance-stability", node: "check_enhanced_sync")

        for mode in [EnhancedSync.none, .esync, .msync] {
            let context = try CheckSummaryFixture.bottle(self) { $0.enhancedSync = mode }
            let result = await SettingValueCheck().run(params: params, context: context)
            XCTAssertEqual(result.outcome, mode == .none ? .fail : .alreadyConfigured, "\(mode)")
        }
    }

    func testAcceptedSettingSummaryNamesTheValueInUse() async throws {
        let params = try params(flow: "performance-stability", node: "check_enhanced_sync")
        let context = try CheckSummaryFixture.bottle(self) { $0.enhancedSync = .msync }

        let result = await SettingValueCheck().run(params: params, context: context)

        XCTAssertEqual(result.summary, "enhancedSync is already msync")
        assertSummaryLookup(
            SettingValueCheck.localizedSummary(for: result),
            "troubleshooting.check.value.matches %@ %@",
            "enhancedSync",
            "msync"
        )
    }

    func testControllerCheckRunsWithItsFlowParams() async throws {
        let params = try params(flow: "controller-input", node: "check_controller_setting")

        let disabled = try CheckSummaryFixture.bottle(self) { $0.controllerCompatibilityMode = false }
        let enabled = try CheckSummaryFixture.bottle(self) { $0.controllerCompatibilityMode = true }

        let offResult = await SettingValueCheck().run(params: params, context: disabled)
        let onResult = await SettingValueCheck().run(params: params, context: enabled)
        XCTAssertEqual(offResult.outcome, .fail)
        XCTAssertEqual(onResult.outcome, .alreadyConfigured)
    }

    // MARK: - Winetricks

    func testMissingVerbsListsEveryVerbTheCheckFoundMissing() {
        let result = CheckResult(
            outcome: .fail, evidence: ["missing": "vcrun2019, dotnet48,d3dx9"], summary: "x"
        )

        XCTAssertEqual(WinetricksVerbCheck.missingVerbs(in: result), ["vcrun2019", "dotnet48", "d3dx9"])
        XCTAssertEqual(WinetricksVerbCheck.missingVerbs(in: CheckResult(outcome: .alreadyConfigured, summary: "x")), [])
        XCTAssertEqual(WinetricksVerbCheck.verbs(in: " d3dx9 , ,dxvk"), ["d3dx9", "dxvk"])
    }
}
