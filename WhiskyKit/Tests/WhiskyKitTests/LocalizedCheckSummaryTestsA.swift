//
//  LocalizedCheckSummaryTestsA.swift
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

/// On-screen summaries of the audio device and audio driver checks.
///
/// Each result comes from running the check where the branch is reachable
/// hermetically, so the evidence keys the summary reads are the ones the check
/// writes. ``CheckResult/summary`` must stay English for history and exports.
final class LocalizedAudioCheckSummaryTests: XCTestCase {
    // MARK: - AudioDeviceCheck

    func testAudioDeviceWithNoDeviceIsTheNoneKey() async {
        let result = await AudioDeviceCheck().run(params: [:], context: audioContext(device: nil, transport: nil))

        XCTAssertEqual(result.outcome, .fail)
        XCTAssertEqual(result.summary, "No default audio output device detected")
        assertSummaryLookup(AudioDeviceCheck.localizedSummary(for: result), "troubleshooting.check.audioDevice.none")
    }

    func testAudioDeviceWiredShowsDeviceAndTransportName() async {
        let result = await AudioDeviceCheck().run(
            params: [:],
            context: audioContext(device: "MacBook Pro Speakers", transport: "Built-in")
        )

        XCTAssertEqual(result.summary, "MacBook Pro Speakers (Built-in) available")
        assertSummaryLookup(
            AudioDeviceCheck.localizedSummary(for: result),
            "troubleshooting.check.audioDevice.available %@ %@",
            "MacBook Pro Speakers",
            AudioTransportType.builtIn.displayName
        )
    }

    func testAudioDeviceWithoutTransportShowsTheUnknownName() async {
        let result = await AudioDeviceCheck().run(
            params: [:],
            context: audioContext(device: "Mystery", transport: nil)
        )

        XCTAssertEqual(result.evidence["transportType"], "unknown")
        assertSummaryLookup(
            AudioDeviceCheck.localizedSummary(for: result),
            "troubleshooting.check.audioDevice.available %@ %@",
            "Mystery",
            AudioTransportType.unknown.displayName
        )
    }

    func testAudioDeviceTransportMapsFromExportAndRawNames() {
        // Preflight stores the English export name; sessions saved before it did hold the raw value.
        for transport in AudioTransportType.allCases where transport != .bluetooth {
            for stored in [transport.exportName, transport.rawValue] {
                let summary = AudioDeviceCheck.localizedSummary(for: audioResult(device: "Out", transport: stored))
                assertSummaryLookup(
                    summary,
                    "troubleshooting.check.audioDevice.available %@ %@",
                    "Out",
                    transport.displayName
                )
            }
        }
    }

    func testAudioDeviceRawBuiltInValueIsNotShownRaw() {
        let summary = AudioDeviceCheck.localizedSummary(for: audioResult(device: "Out", transport: "builtIn"))

        XCTAssertEqual(summary?.hasSuffix(" Built-in"), true, String(describing: summary))
        XCTAssertEqual(summary?.contains("builtIn"), false)
    }

    func testAudioDeviceUnrecognizedTransportPassesThrough() {
        let summary = AudioDeviceCheck.localizedSummary(for: audioResult(device: "Out", transport: "Carrier Pigeon"))

        assertSummaryLookup(summary, "troubleshooting.check.audioDevice.available %@ %@", "Out", "Carrier Pigeon")
    }

    func testAudioDeviceBluetoothRunUsesTheBluetoothKeyAndWarning() async throws {
        let result = await AudioDeviceCheck().run(
            params: [:],
            context: audioContext(device: "AirPods Pro", transport: "Bluetooth")
        )

        XCTAssertEqual(result.outcome, .pass)
        XCTAssertEqual(result.confidence, .medium)
        XCTAssertEqual(result.summary, "AirPods Pro connected via Bluetooth (potential latency)")
        let warning = try XCTUnwrap(result.evidence["warning"])
        assertSummaryLookup(warning, "troubleshooting.check.audioDevice.bluetoothWarning")
        assertSummaryLookup(
            AudioDeviceCheck.localizedSummary(for: result),
            "troubleshooting.check.audioDevice.bluetooth %@",
            "AirPods Pro"
        )
    }

    func testAudioDeviceBluetoothIsRecognizedInEveryStoredForm() async {
        for stored in ["bluetooth", "Bluetooth", "Bluetooth Low Energy"] {
            let summary = AudioDeviceCheck.localizedSummary(for: audioResult(device: "Pods", transport: stored))
            assertSummaryLookup(summary, "troubleshooting.check.audioDevice.bluetooth %@", "Pods")

            let context = audioContext(device: "Pods", transport: stored)
            let result = await AudioDeviceCheck().run(params: [:], context: context)
            XCTAssertNotNil(result.evidence["warning"], stored)
        }
    }

    func testAudioDevicePassWithoutEvidenceFallsBackToSummary() {
        let deviceOnly = CheckResult(outcome: .pass, evidence: ["deviceName": "Out"], summary: "x")
        let transportOnly = CheckResult(outcome: .pass, evidence: ["transportType": "USB"], summary: "x")

        XCTAssertNil(AudioDeviceCheck.localizedSummary(for: deviceOnly))
        XCTAssertNil(AudioDeviceCheck.localizedSummary(for: transportOnly))
    }

    // MARK: - AudioDriverCheck

    func testAudioDriverMatchShowsTheDriverDisplayName() async throws {
        let context = try CheckSummaryFixture.bottle(self) { $0.audioDriver = .coreaudio }
        let result = await AudioDriverCheck().run(params: ["expected": "coreaudio"], context: context)

        XCTAssertEqual(result.outcome, .alreadyConfigured)
        XCTAssertEqual(result.summary, "Audio driver is already set to coreaudio")
        assertSummaryLookup(
            AudioDriverCheck.localizedSummary(for: result),
            "troubleshooting.check.audioDriver.matches %@",
            "CoreAudio"
        )
    }

    func testAudioDriverMismatchShowsBothDisplayNames() async throws {
        let context = try CheckSummaryFixture.bottle(self) { $0.audioDriver = .disabled }
        let result = await AudioDriverCheck().run(params: ["expected": "coreaudio"], context: context)

        XCTAssertEqual(result.outcome, .fail)
        XCTAssertEqual(result.summary, "Audio driver is disabled, expected coreaudio")
        assertSummaryLookup(
            AudioDriverCheck.localizedSummary(for: result),
            "troubleshooting.check.audioDriver.mismatch %@ %@",
            AudioDriverMode.disabled.displayName,
            AudioDriverMode.coreaudio.displayName
        )
    }

    func testAudioDriverEveryModeMapsToItsDisplayName() {
        for mode in AudioDriverMode.allCases {
            let result = CheckResult(
                outcome: .alreadyConfigured,
                evidence: ["currentDriver": mode.rawValue, "expectedDriver": mode.rawValue],
                summary: "x"
            )
            assertSummaryLookup(
                AudioDriverCheck.localizedSummary(for: result),
                "troubleshooting.check.audioDriver.matches %@",
                mode.displayName
            )
        }
    }

    func testAudioDriverUnknownIdStaysRaw() {
        let result = CheckResult(
            outcome: .fail,
            evidence: ["currentDriver": "pulseaudio", "expectedDriver": "auto"],
            summary: "x"
        )

        assertSummaryLookup(
            AudioDriverCheck.localizedSummary(for: result),
            "troubleshooting.check.audioDriver.mismatch %@ %@",
            "pulseaudio",
            AudioDriverMode.auto.displayName
        )
    }

    func testAudioDriverUnreadableSettingsIsLocalized() async throws {
        let result = try await AudioDriverCheck().run(params: [:], context: CheckSummaryFixture.corruptBottle(self))

        XCTAssertEqual(result.outcome, .error)
        XCTAssertEqual(result.summary, "Failed to read bottle settings")
        assertSummaryLookup(AudioDriverCheck.localizedSummary(for: result), "troubleshooting.check.settingsUnreadable")
    }

    func testAudioDriverOtherOutcomesAndMissingEvidenceFallBack() {
        XCTAssertNil(AudioDriverCheck.localizedSummary(for: CheckResult(outcome: .pass, summary: "x")))
        XCTAssertNil(AudioDriverCheck.localizedSummary(for: CheckResult(outcome: .unknown, summary: "x")))
        XCTAssertNil(AudioDriverCheck.localizedSummary(for: CheckResult(outcome: .alreadyConfigured, summary: "x")))
        let currentOnly = CheckResult(outcome: .fail, evidence: ["currentDriver": "auto"], summary: "x")
        XCTAssertNil(AudioDriverCheck.localizedSummary(for: currentOnly))
    }

    // MARK: - Helpers

    private func audioContext(device: String?, transport: String?) -> CheckContext {
        let bottleURL = URL(filePath: "/tmp/test-bottle-\(UUID().uuidString)")
        let preflight = PreflightData(
            bottleURL: bottleURL,
            bottleName: "Test Bottle",
            isWineserverRunning: false,
            processCount: 0,
            audioDeviceName: device,
            audioTransportType: transport,
            graphicsBackend: "dxmt"
        )
        return CheckContext(
            bottleURL: bottleURL,
            bottleName: "Test Bottle",
            preflight: preflight,
            session: TroubleshootingSession(bottleURL: bottleURL)
        )
    }

    private func audioResult(device: String, transport: String) -> CheckResult {
        CheckResult(outcome: .pass, evidence: ["deviceName": device, "transportType": transport], summary: "x")
    }
}

/// Bottles and assertions shared by the localized check summary tests.
enum CheckSummaryFixture {
    /// A context for a temporary bottle whose `Metadata.plist` holds `settings`
    /// after `configure`; the directory is removed when `testCase` finishes.
    static func bottle(
        _ testCase: XCTestCase,
        configure: (inout BottleSettings) -> Void = { _ in }
    ) throws -> CheckContext {
        let bottleURL = try makeDirectory(testCase)
        var settings = BottleSettings()
        configure(&settings)
        try settings.encode(to: bottleURL.appending(path: "Metadata.plist"))
        return context(for: bottleURL)
    }

    /// A context for a temporary bottle whose `Metadata.plist` can't be decoded.
    static func corruptBottle(_ testCase: XCTestCase) throws -> CheckContext {
        let bottleURL = try makeDirectory(testCase)
        try Data("not a property list".utf8).write(to: bottleURL.appending(path: "Metadata.plist"))
        return context(for: bottleURL)
    }

    private static func makeDirectory(_ testCase: XCTestCase) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "LocalizedCheckSummaryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        testCase.addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private static func context(for bottleURL: URL) -> CheckContext {
        let preflight = PreflightData(
            bottleURL: bottleURL,
            bottleName: "Test Bottle",
            isWineserverRunning: false,
            processCount: 0,
            graphicsBackend: "dxmt"
        )
        return CheckContext(
            bottleURL: bottleURL,
            bottleName: "Test Bottle",
            preflight: preflight,
            session: TroubleshootingSession(bottleURL: bottleURL)
        )
    }
}

/// Asserts that `value` is the test runner's result of looking up `catalogKey`
/// with `arguments`: the key exists in the catalog with English, takes one
/// `%@` per argument, and the lookup substituted the arguments in order.
func assertSummaryLookup(
    _ value: String?,
    _ catalogKey: String,
    _ arguments: String...,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(
        StringCatalog.english[catalogKey]?.isEmpty,
        false,
        "\"\(catalogKey)\" has no English value in Localizable.xcstrings",
        file: file,
        line: line
    )
    XCTAssertEqual(
        catalogKey.components(separatedBy: "%@").count - 1,
        arguments.count,
        "\"\(catalogKey)\" takes a different number of arguments",
        file: file,
        line: line
    )
    guard let value else {
        XCTFail("no localized summary; expected \"\(catalogKey)\"", file: file, line: line)
        return
    }
    var expected = catalogKey
    for argument in arguments {
        if let range = expected.range(of: "%@") {
            expected.replaceSubrange(range, with: argument)
        }
    }
    XCTAssertEqual(value, expected, file: file, line: line)
    assertCatalogKey(value, file: file, line: line)
}
