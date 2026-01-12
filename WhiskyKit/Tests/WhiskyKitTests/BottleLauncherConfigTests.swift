//
//  BottleLauncherConfigTests.swift
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

import XCTest
@testable import WhiskyKit

final class BottleLauncherConfigTests: XCTestCase {
    func testDefaultLauncherConfig() throws {
        let config = BottleLauncherConfig()

        XCTAssertFalse(config.compatibilityMode)
        XCTAssertEqual(config.launcherMode, .auto)
        XCTAssertNil(config.detectedLauncher)
        XCTAssertEqual(config.launcherLocale, .auto)
        XCTAssertTrue(config.gpuSpoofing)
        XCTAssertEqual(config.gpuVendor, .nvidia)
        XCTAssertEqual(config.networkTimeout, 60000)
        XCTAssertTrue(config.autoEnableDXVK)
    }

    func testLauncherConfigCodable() throws {
        var config = BottleLauncherConfig()
        config.compatibilityMode = true
        config.launcherMode = .manual
        config.detectedLauncher = .steam
        config.launcherLocale = .english
        config.gpuVendor = .amd
        config.networkTimeout = 90000

        // Encode
        let encoder = PropertyListEncoder()
        let data = try encoder.encode(config)

        // Decode
        let decoder = PropertyListDecoder()
        let decoded = try decoder.decode(BottleLauncherConfig.self, from: data)

        XCTAssertEqual(decoded.compatibilityMode, true)
        XCTAssertEqual(decoded.launcherMode, .manual)
        XCTAssertEqual(decoded.detectedLauncher, .steam)
        XCTAssertEqual(decoded.launcherLocale, .english)
        XCTAssertEqual(decoded.gpuVendor, .amd)
        XCTAssertEqual(decoded.networkTimeout, 90000)
    }

    func testLauncherModeEnum() throws {
        XCTAssertEqual(LauncherMode.auto.rawValue, "auto")
        XCTAssertEqual(LauncherMode.manual.rawValue, "manual")

        // Test all cases present
        let allCases = LauncherMode.allCases
        XCTAssertEqual(allCases.count, 2)
        XCTAssertTrue(allCases.contains(.auto))
        XCTAssertTrue(allCases.contains(.manual))
    }

    func testBottleSettingsIncludesLauncherConfig() throws {
        let settings = BottleSettings()

        // Test default values are accessible
        XCTAssertFalse(settings.launcherCompatibilityMode)
        XCTAssertEqual(settings.launcherMode, .auto)
        XCTAssertNil(settings.detectedLauncher)
        XCTAssertTrue(settings.gpuSpoofing)
        XCTAssertEqual(settings.gpuVendor, .nvidia)
    }

    func testBottleSettingsLauncherConfigModification() throws {
        var settings = BottleSettings()

        // Modify launcher settings
        settings.launcherCompatibilityMode = true
        settings.launcherMode = .manual
        settings.detectedLauncher = .rockstar
        settings.launcherLocale = .english
        settings.gpuSpoofing = false
        settings.networkTimeout = 120000

        // Verify changes
        XCTAssertTrue(settings.launcherCompatibilityMode)
        XCTAssertEqual(settings.launcherMode, .manual)
        XCTAssertEqual(settings.detectedLauncher, .rockstar)
        XCTAssertEqual(settings.launcherLocale, .english)
        XCTAssertFalse(settings.gpuSpoofing)
        XCTAssertEqual(settings.networkTimeout, 120000)
    }

    func testEnvironmentVariablesWithLauncherCompatibility() throws {
        var settings = BottleSettings()
        settings.launcherCompatibilityMode = true
        settings.detectedLauncher = .steam
        settings.launcherLocale = .english
        settings.gpuSpoofing = true

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        // Should include Steam-specific fixes
        XCTAssertEqual(env["STEAM_DISABLE_CEF_SANDBOX"], "1")

        // Should include locale override
        XCTAssertEqual(env["LC_ALL"], "en_US")
        XCTAssertEqual(env["LC_TIME"], "C")

        // Should include GPU spoofing
        XCTAssertNotNil(env["GPU_VENDOR_ID"])
        XCTAssertNotNil(env["D3DM_FEATURE_LEVEL_12_1"])
    }

    func testEnvironmentVariablesWithoutLauncherCompatibility() throws {
        var settings = BottleSettings()
        settings.launcherCompatibilityMode = false

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        // Should not include launcher-specific fixes
        XCTAssertNil(env["STEAM_DISABLE_CEF_SANDBOX"])
        // GPU spoofing should not be applied if launcher compat is off
    }

    func testNetworkTimeoutConfiguration() throws {
        var settings = BottleSettings()
        settings.launcherCompatibilityMode = true
        settings.networkTimeout = 45000

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        // Should include custom network timeout
        XCTAssertEqual(env["WINHTTP_CONNECT_TIMEOUT"], "45000")
        XCTAssertEqual(env["WINHTTP_RECEIVE_TIMEOUT"], "90000")  // 2x connect timeout
    }

    func testAutoEnableDXVKForRockstar() throws {
        var settings = BottleSettings()
        settings.launcherCompatibilityMode = true
        settings.detectedLauncher = .rockstar
        settings.autoEnableDXVK = true
        settings.dxvk = false  // Explicitly disabled

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        // Should still enable DXVK overrides because Rockstar requires it
        XCTAssertEqual(env["WINEDLLOVERRIDES"], "dxgi,d3d9,d3d10core,d3d11=n,b")
    }

    func testSSLTLSConfiguration() throws {
        var settings = BottleSettings()
        settings.launcherCompatibilityMode = true

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        // Should include SSL/TLS fixes
        XCTAssertEqual(env["WINE_ENABLE_SSL"], "1")
        XCTAssertEqual(env["WINE_SSL_VERSION_MIN"], "TLS1.2")
    }

    func testConnectionPoolingFixes() throws {
        var settings = BottleSettings()
        settings.launcherCompatibilityMode = true

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        // Should include connection fixes
        XCTAssertEqual(env["WINE_MAX_CONNECTIONS_PER_SERVER"], "10")
        XCTAssertEqual(env["WINE_FORCE_HTTP11"], "1")
    }
}
