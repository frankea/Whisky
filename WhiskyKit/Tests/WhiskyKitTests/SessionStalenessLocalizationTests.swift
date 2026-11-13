//
//  SessionStalenessLocalizationTests.swift
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

/// The "Since you left" messages from staleness detection: each change's
/// message is a catalog lookup carrying the values that changed, while its
/// `oldValue` and `newValue` keep the raw values the preflight stored.
final class SessionStalenessLocalizationTests: XCTestCase {
    private let store = TroubleshootingSessionStore()
    private let bottleURL = URL(filePath: "/tmp/staleness-localization-test-bottle")

    private func preflight(
        backend: String = "dxvk",
        audioDevice: String? = "MacBook Pro Speakers",
        wineserverRunning: Bool = false,
        processCount: Int = 0
    ) -> PreflightData {
        PreflightData(
            bottleURL: bottleURL,
            bottleName: "Staleness Test",
            isWineserverRunning: wineserverRunning,
            processCount: processCount,
            audioDeviceName: audioDevice,
            graphicsBackend: backend
        )
    }

    private func changes(from snapshot: PreflightData?, to current: PreflightData) -> [StalenessChange] {
        var session = TroubleshootingSession(bottleURL: bottleURL)
        session.preflightSnapshot = snapshot
        return store.checkStaleness(session: session, currentPreflight: current)
    }

    private func onlyChange(
        from snapshot: PreflightData,
        to current: PreflightData,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> StalenessChange {
        let found = changes(from: snapshot, to: current)
        XCTAssertEqual(found.count, 1, found.map(\.field).description, file: file, line: line)
        return try XCTUnwrap(found.first, file: file, line: line)
    }

    // MARK: - Nothing to report

    func testNoSnapshotMeansNoChanges() {
        XCTAssertTrue(changes(from: nil, to: preflight()).isEmpty)
    }

    func testIdenticalPreflightMeansNoChanges() {
        XCTAssertTrue(changes(from: preflight(), to: preflight()).isEmpty)
    }

    // MARK: - Graphics backend

    func testBackendChangeNamesBothBackendsTheWayTheAppDoes() throws {
        let change = try onlyChange(from: preflight(backend: "dxvk"), to: preflight(backend: "d3dMetal"))

        XCTAssertEqual(change.field, "graphicsBackend")
        XCTAssertEqual(change.oldValue, "dxvk")
        XCTAssertEqual(change.newValue, "d3dMetal")
        XCTAssertEqual(
            change.displayMessage,
            String(localized: "troubleshooting.resume.change.backend DXVK D3DMetal")
        )
        assertCatalogKey(change.displayMessage)
    }

    func testBackendChangeUsesTheLocalizedRecommendedName() throws {
        let change = try onlyChange(
            from: preflight(backend: "recommended"), to: preflight(backend: "wined3d")
        )
        let recommended = GraphicsBackend.recommended.displayName

        XCTAssertEqual(
            change.displayMessage,
            String(localized: "troubleshooting.resume.change.backend \(recommended) WineD3D")
        )
        XCTAssertFalse(change.displayMessage.contains(" recommended "))
    }

    func testBackendChangeKeepsARawValueThatNamesNoBackend() throws {
        let change = try onlyChange(from: preflight(backend: "gptk"), to: preflight(backend: "dxmt"))

        XCTAssertEqual(change.oldValue, "gptk")
        XCTAssertEqual(
            change.displayMessage,
            String(localized: "troubleshooting.resume.change.backend gptk DXMT")
        )
        assertCatalogKey(change.displayMessage)
    }

    // MARK: - Audio device

    func testAudioDeviceChangeBetweenNamedDevices() throws {
        let change = try onlyChange(
            from: preflight(audioDevice: "MacBook Pro Speakers"), to: preflight(audioDevice: "AirPods")
        )

        XCTAssertEqual(change.field, "audioDeviceName")
        XCTAssertEqual(change.oldValue, "MacBook Pro Speakers")
        XCTAssertEqual(change.newValue, "AirPods")
        XCTAssertEqual(
            change.displayMessage,
            String(localized: "troubleshooting.resume.change.audioDevice \("MacBook Pro Speakers") \("AirPods")")
        )
        assertCatalogKey(change.displayMessage)
    }

    func testAudioDeviceAppearingShowsTheLocalizedNoDevice() throws {
        let change = try onlyChange(from: preflight(audioDevice: nil), to: preflight(audioDevice: "AirPods"))
        let noDevice = String(localized: "troubleshooting.resume.change.noDevice")

        // The stored values keep the raw "none"; only the message is localized.
        XCTAssertEqual(change.oldValue, "none")
        XCTAssertEqual(change.newValue, "AirPods")
        XCTAssertEqual(
            change.displayMessage,
            String(localized: "troubleshooting.resume.change.audioDevice \(noDevice) \("AirPods")")
        )
        assertCatalogKey(noDevice)
        assertCatalogKey(change.displayMessage)
    }

    func testAudioDeviceDisappearingShowsTheLocalizedNoDevice() throws {
        let change = try onlyChange(from: preflight(audioDevice: "AirPods"), to: preflight(audioDevice: nil))
        let noDevice = String(localized: "troubleshooting.resume.change.noDevice")

        XCTAssertEqual(change.oldValue, "AirPods")
        XCTAssertEqual(change.newValue, "none")
        XCTAssertEqual(
            change.displayMessage,
            String(localized: "troubleshooting.resume.change.audioDevice \("AirPods") \(noDevice)")
        )
    }

    func testNoAudioDeviceEitherTimeIsNotAChange() {
        XCTAssertTrue(changes(from: preflight(audioDevice: nil), to: preflight(audioDevice: nil)).isEmpty)
    }

    // MARK: - Wineserver

    func testWineserverStartingAndStoppingUseDifferentKeys() throws {
        let started = try onlyChange(
            from: preflight(wineserverRunning: false), to: preflight(wineserverRunning: true)
        )
        let stopped = try onlyChange(
            from: preflight(wineserverRunning: true), to: preflight(wineserverRunning: false)
        )

        XCTAssertEqual(
            started.displayMessage, String(localized: "troubleshooting.resume.change.wineserverStarted")
        )
        XCTAssertEqual(
            stopped.displayMessage, String(localized: "troubleshooting.resume.change.wineserverStopped")
        )
        XCTAssertNotEqual(started.displayMessage, stopped.displayMessage)
        assertCatalogKey(started.displayMessage)
        assertCatalogKey(stopped.displayMessage)
        // The stored states stay English identifiers.
        XCTAssertEqual([started.oldValue, started.newValue], ["stopped", "running"])
        XCTAssertEqual([stopped.oldValue, stopped.newValue], ["running", "stopped"])
    }

    // MARK: - Process count

    func testProcessCountChangeCarriesBothCounts() throws {
        let change = try onlyChange(from: preflight(processCount: 2), to: preflight(processCount: 12))

        XCTAssertEqual(change.field, "processCount")
        XCTAssertEqual(change.oldValue, "2")
        XCTAssertEqual(change.newValue, "12")
        XCTAssertEqual(
            change.displayMessage,
            String(localized: "troubleshooting.resume.change.processCount \(2) \(12)")
        )
        XCTAssertTrue(change.displayMessage.hasSuffix(" 2 12"))
        assertCatalogKey(change.displayMessage)
    }

    func testSmallProcessCountChangeIsNotReported() {
        XCTAssertTrue(changes(from: preflight(processCount: 10), to: preflight(processCount: 12)).isEmpty)
    }

    // MARK: - Several at once

    func testEveryKindOfChangeGetsItsOwnMessage() {
        let found = changes(
            from: preflight(backend: "dxvk", audioDevice: nil, wineserverRunning: false, processCount: 0),
            to: preflight(backend: "dxmt", audioDevice: "AirPods", wineserverRunning: true, processCount: 8)
        )

        XCTAssertEqual(
            found.map(\.field),
            ["graphicsBackend", "audioDeviceName", "isWineserverRunning", "processCount"]
        )
        XCTAssertEqual(Set(found.map { StringCatalog.stem($0.displayMessage) }).count, 4)
        for change in found {
            assertCatalogKey(change.displayMessage)
        }
    }
}
