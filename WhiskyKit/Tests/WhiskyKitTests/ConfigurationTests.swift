//
//  ConfigurationTests.swift
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

import SemanticVersion
@testable import WhiskyKit
import XCTest

// MARK: - BottleWineConfig Decoding Tests

final class BottleWineConfigDecodingTests: XCTestCase {
    private func createVersionDict(major: Int, minor: Int, patch: Int) -> [String: Any] {
        ["major": major, "minor": minor, "patch": patch, "preRelease": "", "build": ""]
    }

    func testDecodeWithAllValues() throws {
        let plist: [String: Any] = [
            "wineVersion": createVersionDict(major: 8, minor: 0, patch: 1),
            "windowsVersion": "win11",
            "enhancedSync": ["esync": [:]],
            "avxEnabled": true
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let config = try PropertyListDecoder().decode(BottleWineConfig.self, from: data)

        XCTAssertEqual(config.wineVersion, SemanticVersion(8, 0, 1))
        XCTAssertEqual(config.windowsVersion, .win11)
        XCTAssertEqual(config.enhancedSync, .esync)
        XCTAssertTrue(config.avxEnabled)
    }

    func testDecodeWithMissingWineVersionUsesDefault() throws {
        let plist: [String: Any] = [
            "windowsVersion": "win10",
            "enhancedSync": ["msync": [:]],
            "avxEnabled": false
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let config = try PropertyListDecoder().decode(BottleWineConfig.self, from: data)

        XCTAssertEqual(config.wineVersion, SemanticVersion(7, 7, 0))
    }

    func testDecodeWithMissingWindowsVersionUsesDefault() throws {
        let plist: [String: Any] = [
            "wineVersion": createVersionDict(major: 8, minor: 0, patch: 0),
            "enhancedSync": ["msync": [:]],
            "avxEnabled": false
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let config = try PropertyListDecoder().decode(BottleWineConfig.self, from: data)

        XCTAssertEqual(config.windowsVersion, .win10)
    }

    func testDecodeWithMissingEnhancedSyncUsesDefault() throws {
        let plist: [String: Any] = [
            "wineVersion": createVersionDict(major: 8, minor: 0, patch: 0),
            "windowsVersion": "win10",
            "avxEnabled": false
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let config = try PropertyListDecoder().decode(BottleWineConfig.self, from: data)

        XCTAssertEqual(config.enhancedSync, .msync)
    }

    func testDecodeWithMissingAVXEnabledUsesDefault() throws {
        let plist: [String: Any] = [
            "wineVersion": createVersionDict(major: 8, minor: 0, patch: 0),
            "windowsVersion": "win10",
            "enhancedSync": ["msync": [:]]
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let config = try PropertyListDecoder().decode(BottleWineConfig.self, from: data)

        XCTAssertFalse(config.avxEnabled)
    }

    func testDecodeEmptyPlistUsesAllDefaults() throws {
        let plist: [String: Any] = [:]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let config = try PropertyListDecoder().decode(BottleWineConfig.self, from: data)

        XCTAssertEqual(config.wineVersion, SemanticVersion(7, 7, 0))
        XCTAssertEqual(config.windowsVersion, .win10)
        XCTAssertEqual(config.enhancedSync, .msync)
        XCTAssertFalse(config.avxEnabled)
    }
}

// MARK: - BottleWineConfig Round-Trip Tests

final class BottleWineConfigRoundTripTests: XCTestCase {
    func testRoundTripWithDefaultValues() throws {
        let original = BottleWineConfig()

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(original)

        let decoded = try PropertyListDecoder().decode(BottleWineConfig.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testRoundTripWithCustomValues() throws {
        var original = BottleWineConfig()
        original.wineVersion = SemanticVersion(9, 0, 0)
        original.windowsVersion = .win11
        original.enhancedSync = .esync
        original.avxEnabled = true

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(original)

        let decoded = try PropertyListDecoder().decode(BottleWineConfig.self, from: data)

        XCTAssertEqual(decoded.wineVersion, SemanticVersion(9, 0, 0))
        XCTAssertEqual(decoded.windowsVersion, .win11)
        XCTAssertEqual(decoded.enhancedSync, .esync)
        XCTAssertTrue(decoded.avxEnabled)
    }

    func testRoundTripWithAllWindowsVersions() throws {
        for windowsVersion in WinVersion.allCases {
            var config = BottleWineConfig()
            config.windowsVersion = windowsVersion

            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            let data = try encoder.encode(config)

            let decoded = try PropertyListDecoder().decode(BottleWineConfig.self, from: data)

            XCTAssertEqual(decoded.windowsVersion, windowsVersion)
        }
    }

    func testRoundTripWithAllEnhancedSyncValues() throws {
        let syncValues: [EnhancedSync] = [.none, .esync, .msync]

        for syncValue in syncValues {
            var config = BottleWineConfig()
            config.enhancedSync = syncValue

            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            let data = try encoder.encode(config)

            let decoded = try PropertyListDecoder().decode(BottleWineConfig.self, from: data)

            XCTAssertEqual(decoded.enhancedSync, syncValue)
        }
    }
}

// MARK: - WinVersion Codable Tests

final class WinVersionCodableTests: XCTestCase {
    func testWinVersionJSONEncoding() throws {
        for version in WinVersion.allCases {
            let encoder = JSONEncoder()
            let data = try encoder.encode(version)

            let string = String(data: data, encoding: .utf8)!

            XCTAssertEqual(string, "\"\(version.rawValue)\"")
        }
    }

    func testWinVersionJSONDecoding() throws {
        for version in WinVersion.allCases {
            let jsonString = "\"\(version.rawValue)\""
            let data = jsonString.data(using: .utf8)!

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(WinVersion.self, from: data)

            XCTAssertEqual(decoded, version)
        }
    }

    func testWinVersionPropertyListRoundTrip() throws {
        struct Container: Codable {
            let version: WinVersion
        }

        for version in WinVersion.allCases {
            let original = Container(version: version)

            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            let data = try encoder.encode(original)

            let decoder = PropertyListDecoder()
            let decoded = try decoder.decode(Container.self, from: data)

            XCTAssertEqual(decoded.version, version)
        }
    }
}

// MARK: - EnhancedSync Tests

final class EnhancedSyncDetailedTests: XCTestCase {
    func testEnhancedSyncEquality() {
        XCTAssertEqual(EnhancedSync.none, EnhancedSync.none)
        XCTAssertEqual(EnhancedSync.esync, EnhancedSync.esync)
        XCTAssertEqual(EnhancedSync.msync, EnhancedSync.msync)

        XCTAssertNotEqual(EnhancedSync.none, EnhancedSync.esync)
        XCTAssertNotEqual(EnhancedSync.esync, EnhancedSync.msync)
        XCTAssertNotEqual(EnhancedSync.none, EnhancedSync.msync)
    }

    func testEnhancedSyncPropertyListRoundTrip() throws {
        struct Container: Codable {
            let sync: EnhancedSync
        }

        let values: [EnhancedSync] = [.none, .esync, .msync]

        for value in values {
            let original = Container(sync: value)

            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            let data = try encoder.encode(original)

            let decoder = PropertyListDecoder()
            let decoded = try decoder.decode(Container.self, from: data)

            XCTAssertEqual(decoded.sync, value)
        }
    }
}

// MARK: - BottleWineConfig Equality Tests

final class BottleWineConfigEqualityTests: XCTestCase {
    func testDefaultConfigsAreEqual() {
        let config1 = BottleWineConfig()
        let config2 = BottleWineConfig()

        XCTAssertEqual(config1, config2)
    }

    func testDifferentWineVersionsAreNotEqual() {
        var config1 = BottleWineConfig()
        var config2 = BottleWineConfig()

        config1.wineVersion = SemanticVersion(7, 7, 0)
        config2.wineVersion = SemanticVersion(8, 0, 0)

        XCTAssertNotEqual(config1, config2)
    }

    func testDifferentWindowsVersionsAreNotEqual() {
        var config1 = BottleWineConfig()
        var config2 = BottleWineConfig()

        config1.windowsVersion = .win10
        config2.windowsVersion = .win11

        XCTAssertNotEqual(config1, config2)
    }

    func testDifferentEnhancedSyncAreNotEqual() {
        var config1 = BottleWineConfig()
        var config2 = BottleWineConfig()

        config1.enhancedSync = .msync
        config2.enhancedSync = .esync

        XCTAssertNotEqual(config1, config2)
    }

    func testDifferentAVXEnabledAreNotEqual() {
        var config1 = BottleWineConfig()
        var config2 = BottleWineConfig()

        config1.avxEnabled = false
        config2.avxEnabled = true

        XCTAssertNotEqual(config1, config2)
    }
}

// MARK: - BottleWineConfig Static Properties Tests

final class BottleWineConfigStaticTests: XCTestCase {
    func testDefaultWineVersion() {
        XCTAssertEqual(BottleWineConfig.defaultWineVersion, SemanticVersion(7, 7, 0))
    }
}
