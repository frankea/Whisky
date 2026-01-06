//
//  BottleSettingsTests.swift
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
import SemanticVersion

final class BottleSettingsTests: XCTestCase {

    // MARK: - BottleSettings Default Values

    func testBottleSettingsDefaultValues() {
        let settings = BottleSettings()

        // Verify default values
        XCTAssertEqual(settings.name, "Bottle")
        XCTAssertEqual(settings.windowsVersion, .win10)
        XCTAssertEqual(settings.enhancedSync, .msync)
        XCTAssertFalse(settings.metalHud)
        XCTAssertFalse(settings.metalTrace)
        XCTAssertFalse(settings.dxvk)
        XCTAssertTrue(settings.dxvkAsync)
        XCTAssertEqual(settings.dxvkHud, .off)
        XCTAssertFalse(settings.avxEnabled)
        XCTAssertFalse(settings.dxrEnabled)
        XCTAssertFalse(settings.metalValidation)
        XCTAssertTrue(settings.sequoiaCompatMode)
        XCTAssertEqual(settings.performancePreset, .balanced)
        XCTAssertTrue(settings.shaderCacheEnabled)
        XCTAssertFalse(settings.forceD3D11)
        XCTAssertFalse(settings.vcRedistInstalled)
        XCTAssertTrue(settings.pins.isEmpty)
        XCTAssertTrue(settings.blocklist.isEmpty)
    }

    // MARK: - Encoding/Decoding Roundtrip

    func testBottleSettingsEncodingDecodingRoundtrip() throws {
        var settings = BottleSettings()
        settings.name = "Test Bottle"
        settings.windowsVersion = .win11
        settings.dxvk = true
        settings.dxvkHud = .full
        settings.metalHud = true
        settings.enhancedSync = .esync
        settings.avxEnabled = true
        settings.performancePreset = .performance

        // Encode to PropertyList
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(settings)

        // Decode back
        let decoder = PropertyListDecoder()
        let decoded = try decoder.decode(BottleSettings.self, from: data)

        // Verify all values
        XCTAssertEqual(decoded.name, "Test Bottle")
        XCTAssertEqual(decoded.windowsVersion, .win11)
        XCTAssertTrue(decoded.dxvk)
        XCTAssertEqual(decoded.dxvkHud, .full)
        XCTAssertTrue(decoded.metalHud)
        XCTAssertEqual(decoded.enhancedSync, .esync)
        XCTAssertTrue(decoded.avxEnabled)
        XCTAssertEqual(decoded.performancePreset, .performance)
    }

    func testBottleSettingsJSONEncodingDecoding() throws {
        var settings = BottleSettings()
        settings.name = "JSON Test"
        settings.windowsVersion = .win7
        settings.sequoiaCompatMode = false

        // Encode to JSON
        let encoder = JSONEncoder()
        let data = try encoder.encode(settings)

        // Decode back
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(BottleSettings.self, from: data)

        XCTAssertEqual(decoded.name, "JSON Test")
        XCTAssertEqual(decoded.windowsVersion, .win7)
        XCTAssertFalse(decoded.sequoiaCompatMode)
    }

    // MARK: - WinVersion Tests

    func testWinVersionRawValues() {
        XCTAssertEqual(WinVersion.winXP.rawValue, "winxp64")
        XCTAssertEqual(WinVersion.win7.rawValue, "win7")
        XCTAssertEqual(WinVersion.win8.rawValue, "win8")
        XCTAssertEqual(WinVersion.win81.rawValue, "win81")
        XCTAssertEqual(WinVersion.win10.rawValue, "win10")
        XCTAssertEqual(WinVersion.win11.rawValue, "win11")
    }

    func testWinVersionPrettyNames() {
        XCTAssertEqual(WinVersion.winXP.pretty(), "Windows XP")
        XCTAssertEqual(WinVersion.win7.pretty(), "Windows 7")
        XCTAssertEqual(WinVersion.win8.pretty(), "Windows 8")
        XCTAssertEqual(WinVersion.win81.pretty(), "Windows 8.1")
        XCTAssertEqual(WinVersion.win10.pretty(), "Windows 10")
        XCTAssertEqual(WinVersion.win11.pretty(), "Windows 11")
    }

    func testWinVersionCaseIterable() {
        XCTAssertEqual(WinVersion.allCases.count, 6)
        XCTAssertTrue(WinVersion.allCases.contains(.win10))
    }

    // MARK: - EnhancedSync Tests

    func testEnhancedSyncEncodingDecoding() throws {
        let values: [EnhancedSync] = [.none, .esync, .msync]

        for value in values {
            let encoder = JSONEncoder()
            let data = try encoder.encode(value)

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(EnhancedSync.self, from: data)

            XCTAssertEqual(decoded, value)
        }
    }

    // MARK: - DXVKHUD Tests

    func testDXVKHUDEncodingDecoding() throws {
        let values: [DXVKHUD] = [.full, .partial, .fps, .off]

        for value in values {
            let encoder = JSONEncoder()
            let data = try encoder.encode(value)

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(DXVKHUD.self, from: data)

            XCTAssertEqual(decoded, value)
        }
    }

    // MARK: - PerformancePreset Tests

    func testPerformancePresetDescriptions() {
        XCTAssertEqual(PerformancePreset.balanced.description(), "Balanced (Default)")
        XCTAssertEqual(PerformancePreset.performance.description(), "Performance Mode")
        XCTAssertEqual(PerformancePreset.quality.description(), "Quality Mode")
        XCTAssertEqual(PerformancePreset.unity.description(), "Unity Games Optimized")
    }

    func testPerformancePresetCaseIterable() {
        XCTAssertEqual(PerformancePreset.allCases.count, 4)
    }

    // MARK: - Environment Variables Tests

    func testEnvironmentVariablesWithDXVK() {
        var settings = BottleSettings()
        settings.dxvk = true
        settings.dxvkHud = .full

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        XCTAssertEqual(env["WINEDLLOVERRIDES"], "dxgi,d3d9,d3d10core,d3d11=n,b")
        XCTAssertEqual(env["DXVK_HUD"], "full")
    }

    func testEnvironmentVariablesWithDXVKHUDPartial() {
        var settings = BottleSettings()
        settings.dxvk = true
        settings.dxvkHud = .partial

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        XCTAssertEqual(env["DXVK_HUD"], "devinfo,fps,frametimes")
    }

    func testEnvironmentVariablesWithDXVKHUDFPS() {
        var settings = BottleSettings()
        settings.dxvk = true
        settings.dxvkHud = .fps

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        XCTAssertEqual(env["DXVK_HUD"], "fps")
    }

    func testEnvironmentVariablesWithDXVKAsync() {
        var settings = BottleSettings()
        settings.dxvkAsync = true

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        XCTAssertEqual(env["DXVK_ASYNC"], "1")
    }

    func testEnvironmentVariablesWithESyncOnly() {
        var settings = BottleSettings()
        settings.enhancedSync = .esync

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        XCTAssertEqual(env["WINEESYNC"], "1")
        XCTAssertNil(env["WINEMSYNC"])
    }

    func testEnvironmentVariablesWithMSync() {
        var settings = BottleSettings()
        settings.enhancedSync = .msync

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        XCTAssertEqual(env["WINEMSYNC"], "1")
        // MSync also sets ESYNC for D3DM compatibility
        XCTAssertEqual(env["WINEESYNC"], "1")
    }

    func testEnvironmentVariablesWithNoEnhancedSync() {
        var settings = BottleSettings()
        settings.enhancedSync = .none

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        XCTAssertNil(env["WINEESYNC"])
        XCTAssertNil(env["WINEMSYNC"])
    }

    func testEnvironmentVariablesWithMetalHUD() {
        var settings = BottleSettings()
        settings.metalHud = true

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        XCTAssertEqual(env["MTL_HUD_ENABLED"], "1")
    }

    func testEnvironmentVariablesWithMetalTrace() {
        var settings = BottleSettings()
        settings.metalTrace = true

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        XCTAssertEqual(env["METAL_CAPTURE_ENABLED"], "1")
    }

    func testEnvironmentVariablesWithAVX() {
        var settings = BottleSettings()
        settings.avxEnabled = true

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        XCTAssertEqual(env["ROSETTA_ADVERTISE_AVX"], "1")
    }

    func testEnvironmentVariablesWithDXR() {
        var settings = BottleSettings()
        settings.dxrEnabled = true

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        XCTAssertEqual(env["D3DM_SUPPORT_DXR"], "1")
    }

    func testEnvironmentVariablesWithMetalValidation() {
        var settings = BottleSettings()
        settings.metalValidation = true

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        XCTAssertEqual(env["MTL_DEBUG_LAYER"], "1")
    }

    func testEnvironmentVariablesWithSequoiaCompatMode() {
        var settings = BottleSettings()
        settings.sequoiaCompatMode = true
        settings.metalValidation = false

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        XCTAssertEqual(env["MTL_DEBUG_LAYER"], "0")
        XCTAssertEqual(env["D3DM_VALIDATION"], "0")
        XCTAssertEqual(env["WINEFSYNC"], "0")
    }

    func testEnvironmentVariablesWithPerformancePreset() {
        var settings = BottleSettings()
        settings.performancePreset = .performance

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        XCTAssertEqual(env["D3DM_FAST_SHADER_COMPILE"], "1")
        XCTAssertEqual(env["D3DM_VALIDATION"], "0")
    }

    func testEnvironmentVariablesWithQualityPreset() {
        var settings = BottleSettings()
        settings.performancePreset = .quality
        settings.sequoiaCompatMode = false

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        XCTAssertEqual(env["DXVK_SHADER_OPT_LEVEL"], "2")
        XCTAssertEqual(env["D3DM_FAST_SHADER_COMPILE"], "0")
    }

    func testEnvironmentVariablesWithUnityPreset() {
        var settings = BottleSettings()
        settings.performancePreset = .unity
        settings.sequoiaCompatMode = false

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        XCTAssertEqual(env["MONO_THREADS_SUSPEND"], "1")
        XCTAssertEqual(env["WINE_LARGE_ADDRESS_AWARE"], "65536")
        XCTAssertEqual(env["D3DM_FORCE_D3D11"], "1")
        XCTAssertEqual(env["WINE_HEAP_REUSE"], "0")
    }

    func testEnvironmentVariablesWithForceD3D11() {
        var settings = BottleSettings()
        settings.forceD3D11 = true

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        XCTAssertEqual(env["D3DM_FORCE_D3D11"], "1")
        XCTAssertEqual(env["D3DM_FEATURE_LEVEL_12_0"], "0")
    }

    func testEnvironmentVariablesWithDisabledShaderCache() {
        var settings = BottleSettings()
        settings.shaderCacheEnabled = false

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        XCTAssertEqual(env["DXVK_SHADER_COMPILE_THREADS"], "1")
        XCTAssertEqual(env["__GL_SHADER_DISK_CACHE"], "0")
    }

    // MARK: - PinnedProgram Tests

    func testPinnedProgramEncodingDecoding() throws {
        let url = URL(fileURLWithPath: "/Applications/Test.exe")
        let pin = PinnedProgram(name: "Test App", url: url)

        let encoder = JSONEncoder()
        let data = try encoder.encode(pin)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PinnedProgram.self, from: data)

        XCTAssertEqual(decoded.name, "Test App")
        XCTAssertEqual(decoded.url, url)
    }

    func testPinnedProgramEquality() {
        let url = URL(fileURLWithPath: "/Applications/Test.exe")
        let pin1 = PinnedProgram(name: "Test App", url: url)
        let pin2 = PinnedProgram(name: "Test App", url: url)

        XCTAssertEqual(pin1, pin2)
    }

    // MARK: - BottleInfo Tests

    func testBottleInfoDefaultValues() throws {
        let info = BottleInfo()

        XCTAssertEqual(info.name, "Bottle")
        XCTAssertTrue(info.pins.isEmpty)
        XCTAssertTrue(info.blocklist.isEmpty)
    }

    // MARK: - BottleWineConfig Tests

    func testBottleWineConfigDefaultValues() {
        let config = BottleWineConfig()

        XCTAssertEqual(config.wineVersion, SemanticVersion(7, 7, 0))
        XCTAssertEqual(config.windowsVersion, .win10)
        XCTAssertEqual(config.enhancedSync, .msync)
        XCTAssertFalse(config.avxEnabled)
    }

    // MARK: - BottleMetalConfig Tests

    func testBottleMetalConfigDefaultValues() {
        let config = BottleMetalConfig()

        XCTAssertFalse(config.metalHud)
        XCTAssertFalse(config.metalTrace)
        XCTAssertFalse(config.dxrEnabled)
        XCTAssertFalse(config.metalValidation)
        XCTAssertNil(config.forceGPUFamily)
        XCTAssertTrue(config.sequoiaCompatMode)
    }

    // MARK: - BottleDXVKConfig Tests

    func testBottleDXVKConfigDefaultValues() {
        let config = BottleDXVKConfig()

        XCTAssertFalse(config.dxvk)
        XCTAssertTrue(config.dxvkAsync)
        XCTAssertEqual(config.dxvkHud, .off)
    }

    // MARK: - BottlePerformanceConfig Tests

    func testBottlePerformanceConfigDefaultValues() {
        let config = BottlePerformanceConfig()

        XCTAssertEqual(config.performancePreset, .balanced)
        XCTAssertTrue(config.shaderCacheEnabled)
        XCTAssertNil(config.gpuMemoryLimit)
        XCTAssertFalse(config.forceD3D11)
        XCTAssertFalse(config.disableShaderOptimizations)
        XCTAssertFalse(config.vcRedistInstalled)
    }

    // MARK: - Property Getters and Setters

    func testBottleSettingsPropertyAccess() {
        var settings = BottleSettings()

        // Test name property
        settings.name = "Custom Name"
        XCTAssertEqual(settings.name, "Custom Name")

        // Test windowsVersion property
        settings.windowsVersion = .win11
        XCTAssertEqual(settings.windowsVersion, .win11)

        // Test pins property
        let url = URL(fileURLWithPath: "/test.exe")
        let pin = PinnedProgram(name: "Test", url: url)
        settings.pins = [pin]
        XCTAssertEqual(settings.pins.count, 1)
        XCTAssertEqual(settings.pins.first?.name, "Test")

        // Test blocklist property
        let blockUrl = URL(fileURLWithPath: "/blocked.exe")
        settings.blocklist = [blockUrl]
        XCTAssertEqual(settings.blocklist.count, 1)
    }

    // MARK: - Settings Equality

    func testBottleSettingsEquality() {
        let settings1 = BottleSettings()
        let settings2 = BottleSettings()

        XCTAssertEqual(settings1, settings2)

        var settings3 = BottleSettings()
        settings3.name = "Different"

        XCTAssertNotEqual(settings1, settings3)
    }
}
