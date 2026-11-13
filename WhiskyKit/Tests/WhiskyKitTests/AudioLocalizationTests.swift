//
//  AudioLocalizationTests.swift
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

/// Checks that the audio diagnostics text shown in the UI comes from the string
/// catalog, while evidence lines and export names stay English.
final class AudioLocalizationTests: XCTestCase {
    // MARK: - AudioTransportType

    func testGenericTransportNamesComeFromTheCatalogWithMatchingEnglish() {
        let keys: [AudioTransportType: String] = [
            .builtIn: "audio.transport.builtIn",
            .virtual: "audio.transport.virtual",
            .aggregate: "audio.transport.aggregate",
            .unknown: "audio.transport.unknown"
        ]
        for (transport, key) in keys {
            // The lookup has an English default, which the test runner returns;
            // it has to agree with the catalog's English and with the export name.
            XCTAssertEqual(transport.displayName, StringCatalog.english[key], key)
            XCTAssertEqual(transport.displayName, transport.exportName, key)
        }
    }

    func testStandardTransportNamesAreNotTranslated() {
        let standard: [AudioTransportType] = [.usb, .bluetooth, .airPlay, .hdmi, .displayPort, .thunderbolt]
        for transport in standard {
            XCTAssertEqual(transport.displayName, transport.exportName, transport.rawValue)
            // A default-value lookup returns English in the test runner too, so
            // check the catalog itself: these names must have no key to translate.
            XCTAssertNil(StringCatalog.english["audio.transport.\(transport.rawValue)"], transport.rawValue)
        }
        XCTAssertEqual(AudioTransportType.displayPort.exportName, "DisplayPort")
        XCTAssertEqual(AudioTransportType.airPlay.exportName, "AirPlay")
    }

    func testExportNamesAreDistinctEnglishWords() {
        let names = AudioTransportType.allCases.map(\.exportName)
        XCTAssertEqual(Set(names).count, AudioTransportType.allCases.count)
        for name in names {
            XCTAssertFalse(name.contains("."), "\(name) looks like a catalog key, not English")
        }
    }

    // MARK: - AudioStatus

    func testEveryStatusNamesACatalogKey() {
        let statuses: [AudioStatus] = [.healthy, .degraded(primaryIssue: "x"), .broken(primaryIssue: "x"), .unknown]
        let names = statuses.map(\.displayName)
        names.forEach { assertCatalogKey($0) }
        XCTAssertEqual(Set(names).count, statuses.count)
    }

    // MARK: - AudioSymptom

    func testEverySymptomHasItsOwnNameAndDescriptionKeys() {
        var names: Set<String> = []
        var descriptions: Set<String> = []
        for symptom in AudioSymptom.allCases {
            assertCatalogKey(symptom.displayName)
            assertCatalogKey(symptom.symptomDescription)
            XCTAssertNotEqual(symptom.displayName, symptom.symptomDescription)
            names.insert(symptom.displayName)
            descriptions.insert(symptom.symptomDescription)
        }
        XCTAssertEqual(names.count, AudioSymptom.allCases.count)
        XCTAssertEqual(descriptions.count, AudioSymptom.allCases.count)
    }

    func testSymptomRawValuesStayStableForExports() {
        // The id and raw value are what exports carry, so they never localize.
        for symptom in AudioSymptom.allCases {
            XCTAssertEqual(symptom.id, symptom.rawValue)
            XCTAssertFalse(symptom.rawValue.contains("."))
        }
    }

    // MARK: - AudioTroubleshootingEngine

    @MainActor
    func testEveryKnownFixActionHasItsOwnCatalogDescription() {
        let actionIds = [
            "check-audio-driver", "set-coreaudio-driver", "reset-audio-state",
            "set-stable-latency", "check-system-settings", "check-dsound"
        ]
        let descriptions = actionIds.map { AudioTroubleshootingEngine.fixDescription(for: $0) }
        for description in descriptions {
            assertCatalogKey(description)
            XCTAssertNotEqual(StringCatalog.stem(description), "audio.troubleshoot.fix.generic")
        }
        XCTAssertEqual(Set(descriptions).count, actionIds.count)
    }

    @MainActor
    func testUnknownFixActionFallsBackToTheGenericLineWithItsId() {
        let description = AudioTroubleshootingEngine.fixDescription(for: "flush-the-mixer")
        assertCatalogKey(description)
        XCTAssertEqual(StringCatalog.stem(description), "audio.troubleshoot.fix.generic")
        XCTAssertTrue(description.hasSuffix("flush-the-mixer"), description)
    }

    @MainActor
    func testOfferedFixesUseTheLocalizedDescriptionForEverySymptom() {
        for symptom in AudioSymptom.allCases {
            let engine = AudioTroubleshootingEngine(probes: [])
            engine.selectedSymptom = symptom
            var offered: [String] = []

            // Walk the symptom's fix order until the engine escalates.
            for _ in 0 ..< 4 {
                engine.offerNextFix()
                guard case let .offeringFix(description, actionId) = engine.wizardState else { break }
                XCTAssertEqual(description, AudioTroubleshootingEngine.fixDescription(for: actionId))
                assertCatalogKey(description)
                XCTAssertNotEqual(StringCatalog.stem(description), "audio.troubleshoot.fix.generic", actionId)
                offered.append(actionId)
                engine.applyFix(actionId: actionId)
            }

            XCTAssertFalse(offered.isEmpty, "\(symptom) offered no fix")
            XCTAssertEqual(Set(offered).count, offered.count, "\(symptom) offered a fix twice")
            XCTAssertEqual(engine.wizardState, .escalation)
        }
    }

    // MARK: - WineAudioTestProbe

    @MainActor
    func testMissingTestHelperSkipsWithALocalizedSummaryAndEnglishEvidence() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "AudioLocalizationTests-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let bottle = Bottle(bottleUrl: dir, inFlight: false, isAvailable: true)

        let missing = dir.appending(path: "WhiskyAudioTest.exe")
        for url in [nil, missing] {
            let result = await WineAudioTestProbe(bottle: bottle, testExeURL: url).run()
            XCTAssertEqual(result.status, .skipped)
            assertCatalogKey(result.summary)
            XCTAssertEqual(StringCatalog.stem(result.summary), "audio.probe.wineTest.unavailable")
            XCTAssertEqual(result.evidence, ["WhiskyAudioTest.exe not found in app bundle"])
            XCTAssertTrue(result.findings.isEmpty)
        }
    }
}
