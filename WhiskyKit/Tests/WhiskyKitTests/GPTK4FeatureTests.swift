//
//  GPTK4FeatureTests.swift
//  WhiskyKit
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

/// Covers the GPTK 4 settings Apple documents in the evaluation environment's Read Me:
/// `D3DM_MTL4` and `D3DM_MAX_FPS`. MetalFX has its own end-to-end bridge suite.
final class GPTK4FeatureTests: XCTestCase {
    private func environment(_ configure: (inout BottleSettings) -> Void) -> [String: String] {
        var settings = BottleSettings()
        settings.graphicsBackend = .d3dMetal
        configure(&settings)
        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)
        return env
    }

    // MARK: - Metal 4 backend

    /// Apple enables Metal 4 by default on macOS 27+, so the default must emit nothing at all —
    /// writing `D3DM_MTL4=1` on an older OS would claim a backend that isn't there.
    func testMetal4EmitsNothingWhenLeftOn() {
        XCTAssertNil(environment { _ in }["D3DM_MTL4"])
    }

    func testMetal4OptOutSelectsMetal3() {
        XCTAssertEqual(environment { $0.metal4Backend = false }["D3DM_MTL4"], "0")
    }

    // MARK: - Frame rate cap

    func testFrameRateUncappedByDefault() {
        XCTAssertNil(environment { _ in }["D3DM_MAX_FPS"])
    }

    func testFrameRateCapIsPassedThrough() {
        XCTAssertEqual(environment { $0.maxFPS = 60 }["D3DM_MAX_FPS"], "60")
    }

    /// Zero means uncapped, and a negative value is meaningless; neither may reach D3DMetal,
    /// which would otherwise be handed a cap of "0" and stop presenting.
    func testNonPositiveFrameRateCapIsNotEmitted() {
        XCTAssertNil(environment { $0.maxFPS = 0 }["D3DM_MAX_FPS"])
        XCTAssertNil(environment { $0.maxFPS = -1 }["D3DM_MAX_FPS"])
    }

    func testD3DMetalSettingsDoNotLeakToDXVK() {
        let env = environment {
            $0.graphicsBackend = .dxvk
            $0.metal4Backend = false
            $0.maxFPS = 60
        }

        XCTAssertNil(env["D3DM_MTL4"])
        XCTAssertNil(env["D3DM_MAX_FPS"])
    }

    // MARK: - Round-tripping

    /// Settings live in a plist on disk, so a new field that doesn't decode is a field that
    /// silently resets every launch.
    func testNewSettingsSurviveEncodingRoundTrip() throws {
        var settings = BottleSettings()
        settings.metal4Backend = false
        settings.maxFPS = 120

        let encoded = try PropertyListEncoder().encode(settings)
        let decoded = try PropertyListDecoder().decode(BottleSettings.self, from: encoded)

        XCTAssertFalse(decoded.metal4Backend)
        XCTAssertEqual(decoded.maxFPS, 120)
    }

    /// Bottles created before these fields existed must keep Apple's defaults rather than
    /// decoding to `false` and quietly disabling the Metal 4 backend.
    func testMetal4DefaultsOnForBottlesPredatingTheField() throws {
        let legacy = Data("""
        {"metalHud": false, "metalTrace": false, "dxrEnabled": false, \
        "metalValidation": false, "sequoiaCompatMode": true}
        """.utf8)
        let decoded = try JSONDecoder().decode(BottleMetalConfig.self, from: legacy)

        XCTAssertTrue(decoded.metal4Backend, "Metal 4 is Apple's default and must survive migration")
        XCTAssertEqual(decoded.maxFPS, 0)
    }
}
