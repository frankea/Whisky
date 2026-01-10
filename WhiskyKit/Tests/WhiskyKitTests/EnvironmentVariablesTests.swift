//
//  EnvironmentVariablesTests.swift
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

final class EnvironmentVariablesTests: XCTestCase {

    // MARK: - DXVK Environment Variables

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

    // MARK: - Enhanced Sync Environment Variables

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

        // When MSync is enabled, both WINEMSYNC and WINEESYNC must be set.
        // This is required for D3DM compatibility - values are hardcoded in lid3dshared.dylib
        XCTAssertEqual(env["WINEMSYNC"], "1")
        XCTAssertEqual(env["WINEESYNC"], "1")
    }

    func testEnvironmentVariablesWithNoEnhancedSync() {
        var settings = BottleSettings()
        settings.enhancedSync = .none

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        if MacOSVersion.current >= .sequoia15_4 {
            XCTAssertEqual(env["WINEESYNC"], "1")
            XCTAssertNil(env["WINEMSYNC"])
        } else {
            XCTAssertNil(env["WINEESYNC"])
            XCTAssertNil(env["WINEMSYNC"])
        }
    }

    // MARK: - Metal Environment Variables

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

    func testEnvironmentVariablesWithMetalValidation() {
        var settings = BottleSettings()
        settings.metalValidation = true

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        XCTAssertEqual(env["MTL_DEBUG_LAYER"], "1")
    }

    // MARK: - Other Environment Variables

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

    // MARK: - Sequoia Compatibility Mode

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

    // MARK: - Performance Preset Environment Variables

    func testEnvironmentVariablesWithPerformancePreset() {
        var settings = BottleSettings()
        settings.performancePreset = .performance
        settings.sequoiaCompatMode = false  // Disable to test performance preset in isolation

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        // Performance preset - prioritize FPS over visual quality
        XCTAssertEqual(env["D3DM_FAST_SHADER_COMPILE"], "1")
        XCTAssertEqual(env["D3DM_VALIDATION"], "0")
        XCTAssertEqual(env["MTL_DEBUG_LAYER"], "0")
        XCTAssertEqual(env["DXVK_ASYNC"], "1")
        XCTAssertEqual(env["DXVK_SHADER_OPT_LEVEL"], "0")
        XCTAssertEqual(env["MTL_ENABLE_METAL_EVENTS"], "0")
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

        // Unity preset - il2cpp and threading optimizations
        XCTAssertEqual(env["MONO_THREADS_SUSPEND"], "1")
        XCTAssertEqual(env["WINE_LARGE_ADDRESS_AWARE"], "65536")
        XCTAssertEqual(env["D3DM_FORCE_D3D11"], "1")
        XCTAssertEqual(env["WINE_HEAP_REUSE"], "0")
        XCTAssertEqual(env["WINE_DISABLE_NTDLL_THREAD_REGS"], "1")
        XCTAssertEqual(env["WINEPRELOADRESERVE"], "1")
    }

    // MARK: - D3D11 and Shader Cache

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
}
