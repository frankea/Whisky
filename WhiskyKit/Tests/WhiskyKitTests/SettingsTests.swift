//
//  SettingsTests.swift
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

import Foundation
import SemanticVersion
@testable import WhiskyKit
import XCTest

// MARK: - PinnedProgram Decoding Tests

final class PinnedProgramDecodingTests: XCTestCase {
    func testDecodeWithMissingNameUsesEmptyString() throws {
        // First encode a complete PinnedProgram, then modify the plist to test decoding
        let url = URL(fileURLWithPath: "/path/to/app.exe")
        let original = PinnedProgram(name: "Original", url: url)

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        var data = try encoder.encode(original)

        guard var plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            XCTFail("Failed to deserialize plist")
            return
        }
        plist.removeValue(forKey: "name")
        data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)

        let pin = try PropertyListDecoder().decode(PinnedProgram.self, from: data)
        XCTAssertEqual(pin.name, "")
    }

    func testDecodeWithMissingURLGivesNilURL() throws {
        let plist: [String: Any] = [
            "name": "Test App",
            "removable": false
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let pin = try PropertyListDecoder().decode(PinnedProgram.self, from: data)

        XCTAssertNil(pin.url)
    }

    func testDecodeWithMissingRemovableUsesDefault() throws {
        // First encode a complete PinnedProgram, then modify the plist
        let url = URL(fileURLWithPath: "/path/to/app.exe")
        let original = PinnedProgram(name: "Test App", url: url)

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        var data = try encoder.encode(original)

        guard var plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            XCTFail("Failed to deserialize plist")
            return
        }
        plist.removeValue(forKey: "removable")
        data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)

        let pin = try PropertyListDecoder().decode(PinnedProgram.self, from: data)
        XCTAssertFalse(pin.removable)
    }

    func testDecodeEmptyPlistUsesDefaults() throws {
        let plist: [String: Any] = [:]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let pin = try PropertyListDecoder().decode(PinnedProgram.self, from: data)

        XCTAssertEqual(pin.name, "")
        XCTAssertNil(pin.url)
        XCTAssertFalse(pin.removable)
    }

    func testPinnedProgramRoundTrip() throws {
        let url = URL(fileURLWithPath: "/Applications/Game.exe")
        let original = PinnedProgram(name: "My Game", url: url)

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(original)

        let decoded = try PropertyListDecoder().decode(PinnedProgram.self, from: data)

        XCTAssertEqual(decoded.name, "My Game")
        XCTAssertEqual(decoded.url, url)
    }

    func testPinnedProgramHashable() {
        let url = URL(fileURLWithPath: "/test.exe")
        let pin1 = PinnedProgram(name: "Test", url: url)
        let pin2 = PinnedProgram(name: "Test", url: url)

        var set = Set<PinnedProgram>()
        set.insert(pin1)
        set.insert(pin2)

        XCTAssertEqual(set.count, 1)
    }
}

// MARK: - BottleInfo Decoding Tests

final class BottleInfoDecodingTests: XCTestCase {
    func testDecodeWithMissingNameUsesDefault() throws {
        let plist: [String: Any] = [
            "pins": [],
            "blocklist": []
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let info = try PropertyListDecoder().decode(BottleInfo.self, from: data)

        XCTAssertEqual(info.name, "Bottle")
    }

    func testDecodeWithMissingPinsUsesEmptyArray() throws {
        let plist: [String: Any] = [
            "name": "Custom",
            "blocklist": []
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let info = try PropertyListDecoder().decode(BottleInfo.self, from: data)

        XCTAssertTrue(info.pins.isEmpty)
    }

    func testDecodeWithMissingBlocklistUsesEmptyArray() throws {
        let plist: [String: Any] = [
            "name": "Custom",
            "pins": []
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let info = try PropertyListDecoder().decode(BottleInfo.self, from: data)

        XCTAssertTrue(info.blocklist.isEmpty)
    }

    func testDecodeEmptyPlistUsesAllDefaults() throws {
        let plist: [String: Any] = [:]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let info = try PropertyListDecoder().decode(BottleInfo.self, from: data)

        XCTAssertEqual(info.name, "Bottle")
        XCTAssertTrue(info.pins.isEmpty)
        XCTAssertTrue(info.blocklist.isEmpty)
    }

    func testBottleInfoEquality() {
        let info1 = BottleInfo()
        let info2 = BottleInfo()

        XCTAssertEqual(info1, info2)
    }

    func testBottleInfoRoundTrip() throws {
        var original = BottleInfo()
        original.name = "Custom Bottle"
        original.blocklist = [URL(fileURLWithPath: "/blocked.exe")]

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(original)

        let decoded = try PropertyListDecoder().decode(BottleInfo.self, from: data)

        XCTAssertEqual(decoded.name, "Custom Bottle")
        XCTAssertEqual(decoded.blocklist.count, 1)
    }
}

// MARK: - BottleMetalConfig Tests

final class BottleMetalConfigTests: XCTestCase {
    func testDefaultValues() {
        let config = BottleMetalConfig()

        XCTAssertFalse(config.metalHud)
        XCTAssertFalse(config.metalTrace)
        XCTAssertFalse(config.dxrEnabled)
        XCTAssertFalse(config.metalValidation)
        XCTAssertTrue(config.sequoiaCompatMode)
    }

    func testRoundTrip() throws {
        var original = BottleMetalConfig()
        original.metalHud = true
        original.metalTrace = true
        original.dxrEnabled = true
        original.metalValidation = true
        original.sequoiaCompatMode = false

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(original)

        let decoded = try PropertyListDecoder().decode(BottleMetalConfig.self, from: data)

        XCTAssertTrue(decoded.metalHud)
        XCTAssertTrue(decoded.metalTrace)
        XCTAssertTrue(decoded.dxrEnabled)
        XCTAssertTrue(decoded.metalValidation)
        XCTAssertFalse(decoded.sequoiaCompatMode)
    }

    func testDecodeWithMissingValuesUsesDefaults() throws {
        let plist: [String: Any] = [:]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let config = try PropertyListDecoder().decode(BottleMetalConfig.self, from: data)

        XCTAssertFalse(config.metalHud)
        XCTAssertFalse(config.metalTrace)
        XCTAssertFalse(config.dxrEnabled)
        XCTAssertFalse(config.metalValidation)
        XCTAssertTrue(config.sequoiaCompatMode)
    }
}

// MARK: - BottleDXVKConfig Tests

final class BottleDXVKConfigTests: XCTestCase {
    func testDefaultValues() {
        let config = BottleDXVKConfig()

        XCTAssertFalse(config.dxvk)
        XCTAssertTrue(config.dxvkAsync)
        XCTAssertEqual(config.dxvkHud, .off)
    }

    func testRoundTrip() throws {
        var original = BottleDXVKConfig()
        original.dxvk = true
        original.dxvkAsync = false
        original.dxvkHud = .full

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(original)

        let decoded = try PropertyListDecoder().decode(BottleDXVKConfig.self, from: data)

        XCTAssertTrue(decoded.dxvk)
        XCTAssertFalse(decoded.dxvkAsync)
        XCTAssertEqual(decoded.dxvkHud, .full)
    }

    func testDecodeWithMissingValuesUsesDefaults() throws {
        let plist: [String: Any] = [:]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let config = try PropertyListDecoder().decode(BottleDXVKConfig.self, from: data)

        XCTAssertFalse(config.dxvk)
        XCTAssertTrue(config.dxvkAsync)
        XCTAssertEqual(config.dxvkHud, .off)
    }
}
