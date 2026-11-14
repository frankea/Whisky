//
//  CloseWithProcessesPolicyTests.swift
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

final class CloseWithProcessesPolicyTests: XCTestCase {
    // MARK: - Defaults

    func testDefaultIsKeepRunning() {
        XCTAssertEqual(CloseWithProcessesPolicy.defaultPolicy, .alwaysKeepRunning)
        XCTAssertEqual(BottleCleanupConfig().closeWithProcessesPolicy, .alwaysKeepRunning)
        XCTAssertEqual(BottleSettings().closeWithProcessesPolicy, .alwaysKeepRunning)
    }

    func testMissingKeyDecodesToKeepRunning() throws {
        let config = try decodeCleanupConfig(policyRawValue: nil)
        XCTAssertEqual(config.closeWithProcessesPolicy, .alwaysKeepRunning)
    }

    // MARK: - Legacy Migration

    func testLegacyAskDecodesToKeepRunning() throws {
        let config = try decodeCleanupConfig(policyRawValue: "ask")
        XCTAssertEqual(config.closeWithProcessesPolicy, .alwaysKeepRunning)
    }

    func testLegacyAskInWholeSettingsPlistDecodesToKeepRunning() throws {
        var settings = BottleSettings()
        settings.name = "Legacy Ask"
        let decoded = try decodeSettings(settings, withPolicyRawValue: "ask")

        XCTAssertEqual(decoded.name, "Legacy Ask")
        XCTAssertEqual(decoded.closeWithProcessesPolicy, .alwaysKeepRunning)
    }

    func testLegacyAskIsRewrittenAsKeepRunningOnNextSave() throws {
        let legacy = try decodeSettings(BottleSettings(), withPolicyRawValue: "ask")
        XCTAssertEqual(try storedPolicyRawValue(in: legacy), "keepRunning")
    }

    func testOtherCleanupFieldsSurviveLegacyAsk() throws {
        var settings = BottleSettings()
        settings.killOnQuit = .neverKill
        settings.clipboardPolicy = .alwaysClear
        let decoded = try decodeSettings(settings, withPolicyRawValue: "ask")

        XCTAssertEqual(decoded.killOnQuit, .neverKill)
        XCTAssertEqual(decoded.clipboardPolicy, .alwaysClear)
        XCTAssertEqual(decoded.closeWithProcessesPolicy, .alwaysKeepRunning)
    }

    // MARK: - Explicit Choices

    func testExplicitAskRoundTrips() throws {
        var settings = BottleSettings()
        settings.closeWithProcessesPolicy = .ask

        XCTAssertEqual(try storedPolicyRawValue(in: settings), "askEachTime")
        XCTAssertEqual(try roundTrip(settings).closeWithProcessesPolicy, .ask)
        XCTAssertEqual(try decodeCleanupConfig(policyRawValue: "askEachTime").closeWithProcessesPolicy, .ask)
    }

    func testKeepRunningAndStopRoundTripUnchanged() throws {
        let cases: [(CloseWithProcessesPolicy, String)] = [
            (.alwaysKeepRunning, "keepRunning"),
            (.alwaysStop, "stop")
        ]
        for (policy, rawValue) in cases {
            var settings = BottleSettings()
            settings.closeWithProcessesPolicy = policy

            XCTAssertEqual(try storedPolicyRawValue(in: settings), rawValue)
            XCTAssertEqual(try roundTrip(settings).closeWithProcessesPolicy, policy)
            XCTAssertEqual(try decodeCleanupConfig(policyRawValue: rawValue).closeWithProcessesPolicy, policy)
        }
    }

    func testUnknownValueDecodesToKeepRunning() throws {
        let config = try decodeCleanupConfig(policyRawValue: "someFuturePolicy")
        XCTAssertEqual(config.closeWithProcessesPolicy, .alwaysKeepRunning)
    }

    // MARK: - Helpers

    private func decodeCleanupConfig(policyRawValue: String?) throws -> BottleCleanupConfig {
        var dictionary: [String: Any] = ["killOnQuit": "inherit"]
        if let policyRawValue {
            dictionary["closeWithProcessesPolicy"] = policyRawValue
        }
        let data = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
        return try PropertyListDecoder().decode(BottleCleanupConfig.self, from: data)
    }

    private func encodedPlist(_ settings: BottleSettings) throws -> [String: Any] {
        let data = try PropertyListEncoder().encode(settings)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(plist as? [String: Any])
    }

    private func storedPolicyRawValue(in settings: BottleSettings) throws -> String? {
        let cleanup = try XCTUnwrap(encodedPlist(settings)["cleanupConfig"] as? [String: Any])
        return cleanup["closeWithProcessesPolicy"] as? String
    }

    /// Encodes `settings`, overwrites the stored policy with `rawValue` the way an older
    /// build would have written it, and decodes the result.
    private func decodeSettings(
        _ settings: BottleSettings,
        withPolicyRawValue rawValue: String
    ) throws -> BottleSettings {
        var plist = try encodedPlist(settings)
        var cleanup = try XCTUnwrap(plist["cleanupConfig"] as? [String: Any])
        cleanup["closeWithProcessesPolicy"] = rawValue
        plist["cleanupConfig"] = cleanup
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        return try PropertyListDecoder().decode(BottleSettings.self, from: data)
    }

    private func roundTrip(_ settings: BottleSettings) throws -> BottleSettings {
        try PropertyListDecoder().decode(BottleSettings.self, from: PropertyListEncoder().encode(settings))
    }
}
