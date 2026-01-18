//
//  BottleInputConfigTests.swift
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

final class BottleInputConfigTests: XCTestCase {
    func testDefaultInputConfig() throws {
        let config = BottleInputConfig()

        XCTAssertFalse(config.controllerCompatibilityMode)
        XCTAssertFalse(config.disableHIDAPI)
        XCTAssertFalse(config.allowBackgroundEvents)
        XCTAssertFalse(config.disableControllerMapping)
    }

    func testInputConfigCodable() throws {
        var config = BottleInputConfig()
        config.controllerCompatibilityMode = true
        config.disableHIDAPI = true
        config.allowBackgroundEvents = true
        config.disableControllerMapping = true

        // Encode
        let encoder = PropertyListEncoder()
        let data = try encoder.encode(config)

        // Decode
        let decoder = PropertyListDecoder()
        let decoded = try decoder.decode(BottleInputConfig.self, from: data)

        XCTAssertTrue(decoded.controllerCompatibilityMode)
        XCTAssertTrue(decoded.disableHIDAPI)
        XCTAssertTrue(decoded.allowBackgroundEvents)
        XCTAssertTrue(decoded.disableControllerMapping)
    }

    func testInputConfigDecoderDefaultValues() throws {
        // Test that missing keys use default values (backwards compatibility)
        let emptyData = try PropertyListEncoder().encode([String: String]())
        let decoder = PropertyListDecoder()

        // This should not throw - missing keys should use defaults
        let decoded = try decoder.decode(BottleInputConfig.self, from: emptyData)

        XCTAssertFalse(decoded.controllerCompatibilityMode)
        XCTAssertFalse(decoded.disableHIDAPI)
        XCTAssertFalse(decoded.allowBackgroundEvents)
        XCTAssertFalse(decoded.disableControllerMapping)
    }

    func testBottleSettingsIncludesInputConfig() throws {
        let settings = BottleSettings()

        // Test default values are accessible
        XCTAssertFalse(settings.controllerCompatibilityMode)
        XCTAssertFalse(settings.disableHIDAPI)
        XCTAssertFalse(settings.allowBackgroundEvents)
        XCTAssertFalse(settings.disableControllerMapping)
    }

    func testBottleSettingsInputConfigModification() throws {
        var settings = BottleSettings()

        // Modify input settings
        settings.controllerCompatibilityMode = true
        settings.disableHIDAPI = true
        settings.allowBackgroundEvents = true
        settings.disableControllerMapping = true

        // Verify changes
        XCTAssertTrue(settings.controllerCompatibilityMode)
        XCTAssertTrue(settings.disableHIDAPI)
        XCTAssertTrue(settings.allowBackgroundEvents)
        XCTAssertTrue(settings.disableControllerMapping)
    }

    func testEnvironmentVariablesWithControllerCompatibility() throws {
        var settings = BottleSettings()
        settings.controllerCompatibilityMode = true
        settings.disableHIDAPI = true
        settings.allowBackgroundEvents = true
        settings.disableControllerMapping = true

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        // Should include SDL environment variables
        XCTAssertEqual(env["SDL_JOYSTICK_HIDAPI"], "0")
        XCTAssertEqual(env["SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS"], "1")
        XCTAssertEqual(env["SDL_GAMECONTROLLER_USE_BUTTON_LABELS"], "1")
    }

    func testEnvironmentVariablesWithPartialControllerSettings() throws {
        var settings = BottleSettings()
        settings.controllerCompatibilityMode = true
        settings.disableHIDAPI = true
        settings.allowBackgroundEvents = false
        settings.disableControllerMapping = false

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        // Should only include HIDAPI disable
        XCTAssertEqual(env["SDL_JOYSTICK_HIDAPI"], "0")
        XCTAssertNil(env["SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS"])
        XCTAssertNil(env["SDL_GAMECONTROLLER_USE_BUTTON_LABELS"])
    }

    func testEnvironmentVariablesWithoutControllerCompatibility() throws {
        var settings = BottleSettings()
        settings.controllerCompatibilityMode = false
        // Even if individual settings are on, they shouldn't apply
        settings.disableHIDAPI = true
        settings.allowBackgroundEvents = true
        settings.disableControllerMapping = true

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        // Should not include any SDL variables since controller compat is off
        XCTAssertNil(env["SDL_JOYSTICK_HIDAPI"])
        XCTAssertNil(env["SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS"])
        XCTAssertNil(env["SDL_GAMECONTROLLER_USE_BUTTON_LABELS"])
    }

    func testInputConfigEquatable() throws {
        let config1 = BottleInputConfig()
        var config2 = BottleInputConfig()

        XCTAssertEqual(config1, config2)

        config2.controllerCompatibilityMode = true
        XCTAssertNotEqual(config1, config2)

        config2.controllerCompatibilityMode = false
        config2.disableHIDAPI = true
        XCTAssertNotEqual(config1, config2)
    }
}
