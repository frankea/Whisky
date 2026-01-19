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

        var plist = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
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

        var plist = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
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

// MARK: - BottlePerformanceConfig Tests

final class BottlePerformanceConfigTests: XCTestCase {
    func testDefaultValues() {
        let config = BottlePerformanceConfig()

        XCTAssertEqual(config.performancePreset, .balanced)
        XCTAssertTrue(config.shaderCacheEnabled)
        XCTAssertFalse(config.forceD3D11)
        XCTAssertFalse(config.vcRedistInstalled)
    }

    func testRoundTrip() throws {
        var original = BottlePerformanceConfig()
        original.performancePreset = .performance
        original.shaderCacheEnabled = false
        original.forceD3D11 = true
        original.vcRedistInstalled = true

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(original)

        let decoded = try PropertyListDecoder().decode(BottlePerformanceConfig.self, from: data)

        XCTAssertEqual(decoded.performancePreset, .performance)
        XCTAssertFalse(decoded.shaderCacheEnabled)
        XCTAssertTrue(decoded.forceD3D11)
        XCTAssertTrue(decoded.vcRedistInstalled)
    }

    func testDecodeWithMissingValuesUsesDefaults() throws {
        let plist: [String: Any] = [:]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let config = try PropertyListDecoder().decode(BottlePerformanceConfig.self, from: data)

        XCTAssertEqual(config.performancePreset, .balanced)
        XCTAssertTrue(config.shaderCacheEnabled)
        XCTAssertFalse(config.forceD3D11)
        XCTAssertFalse(config.vcRedistInstalled)
    }
}

// MARK: - DXVKHUD Tests

final class DXVKHUDTests: XCTestCase {
    func testAllCases() {
        let allCases: [DXVKHUD] = [.full, .partial, .fps, .off]
        XCTAssertEqual(allCases.count, 4)
    }

    func testRoundTrip() throws {
        let values: [DXVKHUD] = [.full, .partial, .fps, .off]

        for value in values {
            struct Container: Codable {
                let hud: DXVKHUD
            }

            let original = Container(hud: value)
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            let data = try encoder.encode(original)

            let decoded = try PropertyListDecoder().decode(Container.self, from: data)
            XCTAssertEqual(decoded.hud, value)
        }
    }
}

// MARK: - PerformancePreset Tests

final class PerformancePresetDetailedTests: XCTestCase {
    func testAllCases() {
        XCTAssertEqual(PerformancePreset.allCases.count, 4)
        XCTAssertTrue(PerformancePreset.allCases.contains(.balanced))
        XCTAssertTrue(PerformancePreset.allCases.contains(.performance))
        XCTAssertTrue(PerformancePreset.allCases.contains(.quality))
        XCTAssertTrue(PerformancePreset.allCases.contains(.unity))
    }

    func testRoundTrip() throws {
        for preset in PerformancePreset.allCases {
            struct Container: Codable {
                let preset: PerformancePreset
            }

            let original = Container(preset: preset)
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            let data = try encoder.encode(original)

            let decoded = try PropertyListDecoder().decode(Container.self, from: data)
            XCTAssertEqual(decoded.preset, preset)
        }
    }

    func testDescriptionIsNotEmpty() {
        for preset in PerformancePreset.allCases {
            XCTAssertFalse(preset.description().isEmpty, "Description for \(preset) should not be empty")
        }
    }
}

// MARK: - BottleSettings Version Tests

final class BottleSettingsVersionTests: XCTestCase {
    func testDefaultFileVersion() {
        XCTAssertEqual(BottleSettings.defaultFileVersion, SemanticVersion(1, 0, 0))
    }

    func testNewSettingsHaveDefaultFileVersion() {
        let settings = BottleSettings()
        XCTAssertEqual(settings.fileVersion, SemanticVersion(1, 0, 0))
    }

    func testSettingsDecodeWithInvalidVersionReturnsDefault() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: "version_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let metadataURL = tempDir.appending(path: "Metadata.plist")

        var settings = BottleSettings()
        settings.name = "Old Version Bottle"

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        var data = try encoder.encode(settings)

        var plist = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
        plist["fileVersion"] = ["major": 99, "minor": 0, "patch": 0, "preRelease": "", "build": ""]
        data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: metadataURL)

        let loaded = try BottleSettings.decode(from: metadataURL)

        XCTAssertEqual(loaded.name, "Bottle")
        XCTAssertEqual(loaded.fileVersion, SemanticVersion(1, 0, 0))
    }
}

// MARK: - BottleSettings Property Accessors Tests

final class BottleSettingsPropertyAccessorsTests: XCTestCase {
    func testWineVersionAccessor() {
        var settings = BottleSettings()
        let newVersion = SemanticVersion(9, 0, 0)
        settings.wineVersion = newVersion
        XCTAssertEqual(settings.wineVersion, newVersion)
    }

    func testWindowsVersionAccessor() {
        var settings = BottleSettings()
        settings.windowsVersion = .win11
        XCTAssertEqual(settings.windowsVersion, .win11)
    }

    func testAVXEnabledAccessor() {
        var settings = BottleSettings()
        settings.avxEnabled = true
        XCTAssertTrue(settings.avxEnabled)
    }

    func testEnhancedSyncAccessor() {
        var settings = BottleSettings()
        settings.enhancedSync = .esync
        XCTAssertEqual(settings.enhancedSync, .esync)
    }

    func testMetalHudAccessor() {
        var settings = BottleSettings()
        settings.metalHud = true
        XCTAssertTrue(settings.metalHud)
    }

    func testMetalTraceAccessor() {
        var settings = BottleSettings()
        settings.metalTrace = true
        XCTAssertTrue(settings.metalTrace)
    }

    func testDXRAccessor() {
        var settings = BottleSettings()
        settings.dxrEnabled = true
        XCTAssertTrue(settings.dxrEnabled)
    }

    func testDXVKAccessor() {
        var settings = BottleSettings()
        settings.dxvk = true
        XCTAssertTrue(settings.dxvk)
    }

    func testDXVKAsyncAccessor() {
        var settings = BottleSettings()
        settings.dxvkAsync = false
        XCTAssertFalse(settings.dxvkAsync)
    }

    func testDXVKHudAccessor() {
        var settings = BottleSettings()
        settings.dxvkHud = .full
        XCTAssertEqual(settings.dxvkHud, .full)
    }

    func testPerformancePresetAccessor() {
        var settings = BottleSettings()
        settings.performancePreset = .performance
        XCTAssertEqual(settings.performancePreset, .performance)
    }

    func testShaderCacheAccessor() {
        var settings = BottleSettings()
        settings.shaderCacheEnabled = false
        XCTAssertFalse(settings.shaderCacheEnabled)
    }

    func testForceD3D11Accessor() {
        var settings = BottleSettings()
        settings.forceD3D11 = true
        XCTAssertTrue(settings.forceD3D11)
    }

    func testVCRedistAccessor() {
        var settings = BottleSettings()
        settings.vcRedistInstalled = true
        XCTAssertTrue(settings.vcRedistInstalled)
    }

    func testSequoiaCompatModeAccessor() {
        var settings = BottleSettings()
        settings.sequoiaCompatMode = false
        XCTAssertFalse(settings.sequoiaCompatMode)
    }

    func testMetalValidationAccessor() {
        var settings = BottleSettings()
        settings.metalValidation = true
        XCTAssertTrue(settings.metalValidation)
    }
}
