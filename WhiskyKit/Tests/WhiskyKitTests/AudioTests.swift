//
//  AudioTests.swift
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

import CoreAudio
@testable import WhiskyKit
import XCTest

final class AudioTests: XCTestCase {
    // MARK: - AudioDeviceHistory: Ring Buffer Bounds

    func testHistoryAppendRespectsMaxEvents() {
        let history = AudioDeviceHistory(maxEvents: 20)

        for index in 0 ..< 25 {
            let event = makeEvent(
                deviceName: "Device-\(index)",
                eventType: .defaultOutputChanged,
                secondsAgo: Double(25 - index) * 60
            )
            history.append(event)
        }

        XCTAssertEqual(history.events.count, 20, "History should cap at maxEvents")
    }

    func testHistoryFIFOEvictsOldestFirst() {
        let history = AudioDeviceHistory(maxEvents: 3)

        let event1 = makeEvent(deviceName: "First", secondsAgo: 300)
        let event2 = makeEvent(deviceName: "Second", secondsAgo: 200)
        let event3 = makeEvent(deviceName: "Third", secondsAgo: 100)
        let event4 = makeEvent(deviceName: "Fourth", secondsAgo: 0)

        history.append(event1)
        history.append(event2)
        history.append(event3)
        history.append(event4)

        XCTAssertEqual(history.events.count, 3)
        XCTAssertEqual(history.events[0].deviceName, "Second")
        XCTAssertEqual(history.events[1].deviceName, "Third")
        XCTAssertEqual(history.events[2].deviceName, "Fourth")
    }

    // MARK: - AudioDeviceHistory: 30-Second Deduplication

    func testHistoryDeduplicatesSameDeviceAndTypeWithin30Seconds() {
        let history = AudioDeviceHistory()
        let now = Date()

        let event1 = AudioDeviceChangeEvent(
            timestamp: now,
            eventType: .defaultOutputChanged,
            deviceName: "Speakers",
            transportType: .builtIn
        )
        let event2 = AudioDeviceChangeEvent(
            timestamp: now.addingTimeInterval(10),
            eventType: .defaultOutputChanged,
            deviceName: "Speakers",
            transportType: .builtIn
        )

        history.append(event1)
        history.append(event2)

        XCTAssertEqual(history.events.count, 1, "Duplicate within 30s should be coalesced")
    }

    func testHistoryDoesNotDeduplicateDifferentDeviceNames() {
        let history = AudioDeviceHistory()
        let now = Date()

        let event1 = AudioDeviceChangeEvent(
            timestamp: now,
            eventType: .defaultOutputChanged,
            deviceName: "Speakers",
            transportType: .builtIn
        )
        let event2 = AudioDeviceChangeEvent(
            timestamp: now.addingTimeInterval(5),
            eventType: .defaultOutputChanged,
            deviceName: "Headphones",
            transportType: .usb
        )

        history.append(event1)
        history.append(event2)

        XCTAssertEqual(history.events.count, 2, "Different devices should not be deduplicated")
    }

    func testHistoryDoesNotDeduplicateDifferentEventTypes() {
        let history = AudioDeviceHistory()
        let now = Date()

        let event1 = AudioDeviceChangeEvent(
            timestamp: now,
            eventType: .disconnected,
            deviceName: "Speakers",
            transportType: .builtIn
        )
        let event2 = AudioDeviceChangeEvent(
            timestamp: now.addingTimeInterval(5),
            eventType: .reconnected,
            deviceName: "Speakers",
            transportType: .builtIn
        )

        history.append(event1)
        history.append(event2)

        XCTAssertEqual(history.events.count, 2, "Different event types should not be deduplicated")
    }

    func testHistoryAllowsSameDeviceAfter30Seconds() {
        let history = AudioDeviceHistory()
        let now = Date()

        let event1 = AudioDeviceChangeEvent(
            timestamp: now,
            eventType: .defaultOutputChanged,
            deviceName: "Speakers",
            transportType: .builtIn
        )
        let event2 = AudioDeviceChangeEvent(
            timestamp: now.addingTimeInterval(31),
            eventType: .defaultOutputChanged,
            deviceName: "Speakers",
            transportType: .builtIn
        )

        history.append(event1)
        history.append(event2)

        XCTAssertEqual(history.events.count, 2, "Same device after 30s should not be deduplicated")
    }

    // MARK: - AudioDeviceHistory: Clear and Export

    func testHistoryClearEmptiesEvents() {
        let history = AudioDeviceHistory()
        history.append(makeEvent(deviceName: "Device", secondsAgo: 60))
        XCTAssertFalse(history.events.isEmpty)

        history.clear()

        XCTAssertTrue(history.events.isEmpty, "clear() should remove all events")
    }

    func testHistoryExportReturnsCopy() {
        let history = AudioDeviceHistory()
        history.append(makeEvent(deviceName: "Device", secondsAgo: 60))

        let exported = history.export()
        history.clear()

        XCTAssertEqual(exported.count, 1, "export() should return an independent copy")
        XCTAssertTrue(history.events.isEmpty, "Original should be cleared independently")
    }

    // MARK: - AudioStatus

    func testStatusDisplayNames() {
        XCTAssertEqual(AudioStatus.ok.displayName, "OK")
        XCTAssertEqual(AudioStatus.degraded(primaryIssue: "test").displayName, "Degraded")
        XCTAssertEqual(AudioStatus.broken(primaryIssue: "test").displayName, "Broken")
        XCTAssertEqual(AudioStatus.unknown.displayName, "Unknown")
    }

    func testStatusSFSymbols() {
        XCTAssertEqual(AudioStatus.ok.sfSymbol, "checkmark.circle.fill")
        XCTAssertEqual(AudioStatus.degraded(primaryIssue: "test").sfSymbol, "exclamationmark.triangle.fill")
        XCTAssertEqual(AudioStatus.broken(primaryIssue: "test").sfSymbol, "xmark.circle.fill")
        XCTAssertEqual(AudioStatus.unknown.sfSymbol, "questionmark.circle")
    }

    func testStatusTintColors() {
        XCTAssertEqual(AudioStatus.ok.tintColor, "green")
        XCTAssertEqual(AudioStatus.degraded(primaryIssue: "test").tintColor, "orange")
        XCTAssertEqual(AudioStatus.broken(primaryIssue: "test").tintColor, "red")
        XCTAssertEqual(AudioStatus.unknown.tintColor, "secondary")
    }

    // MARK: - AudioTransportType

    func testTransportTypeFromKnownConstants() {
        XCTAssertEqual(
            AudioTransportType(coreAudioTransportType: kAudioDeviceTransportTypeBuiltIn),
            .builtIn
        )
        XCTAssertEqual(
            AudioTransportType(coreAudioTransportType: kAudioDeviceTransportTypeUSB),
            .usb
        )
        XCTAssertEqual(
            AudioTransportType(coreAudioTransportType: kAudioDeviceTransportTypeBluetooth),
            .bluetooth
        )
        XCTAssertEqual(
            AudioTransportType(coreAudioTransportType: kAudioDeviceTransportTypeAirPlay),
            .airPlay
        )
        XCTAssertEqual(
            AudioTransportType(coreAudioTransportType: kAudioDeviceTransportTypeHDMI),
            .hdmi
        )
        XCTAssertEqual(
            AudioTransportType(coreAudioTransportType: kAudioDeviceTransportTypeDisplayPort),
            .displayPort
        )
        XCTAssertEqual(
            AudioTransportType(coreAudioTransportType: kAudioDeviceTransportTypeThunderbolt),
            .thunderbolt
        )
        XCTAssertEqual(
            AudioTransportType(coreAudioTransportType: kAudioDeviceTransportTypeVirtual),
            .virtual
        )
        XCTAssertEqual(
            AudioTransportType(coreAudioTransportType: kAudioDeviceTransportTypeAggregate),
            .aggregate
        )
    }

    func testTransportTypeUnknownForUnrecognizedValue() {
        XCTAssertEqual(
            AudioTransportType(coreAudioTransportType: 0xDEAD_BEEF),
            .unknown
        )
    }

    func testTransportTypeDisplayNames() {
        XCTAssertEqual(AudioTransportType.builtIn.displayName, "Built-in")
        XCTAssertEqual(AudioTransportType.usb.displayName, "USB")
        XCTAssertEqual(AudioTransportType.bluetooth.displayName, "Bluetooth")
        XCTAssertEqual(AudioTransportType.unknown.displayName, "Unknown")
    }

    // MARK: - AudioFinding

    func testFindingConfidenceTierIntegration() {
        let highFinding = AudioFinding(
            id: "high-finding",
            description: "No audio output device detected",
            confidence: .high,
            evidence: "CoreAudio reports 0 output devices",
            suggestedAction: "Check audio device connections"
        )
        XCTAssertEqual(highFinding.confidence, .high)
        XCTAssertEqual(highFinding.confidence.displayName, "High")

        let mediumFinding = AudioFinding(
            id: "medium-finding",
            description: "Sample rate mismatch detected",
            confidence: .medium,
            evidence: "Device at 8000 Hz, expected >= 44100 Hz"
        )
        XCTAssertEqual(mediumFinding.confidence, .medium)
        XCTAssertNil(mediumFinding.suggestedAction)

        let lowFinding = AudioFinding(
            id: "low-finding",
            description: "Bluetooth device may have latency",
            confidence: .low,
            evidence: "Transport type is Bluetooth"
        )
        XCTAssertEqual(lowFinding.confidence, .low)
    }

    func testFindingEquality() {
        let finding1 = AudioFinding(
            id: "test",
            description: "Issue",
            confidence: .high,
            evidence: "Evidence"
        )
        let finding2 = AudioFinding(
            id: "test",
            description: "Issue",
            confidence: .high,
            evidence: "Evidence"
        )
        XCTAssertEqual(finding1, finding2)
    }

    // MARK: - Helpers

    private func makeEvent(
        deviceName: String,
        eventType: AudioDeviceChangeEvent.EventType = .defaultOutputChanged,
        secondsAgo: Double
    ) -> AudioDeviceChangeEvent {
        AudioDeviceChangeEvent(
            timestamp: Date().addingTimeInterval(-secondsAgo),
            eventType: eventType,
            deviceName: deviceName,
            transportType: .builtIn
        )
    }
}
