//
//  ProgramOverridesTests.swift
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

final class ProgramOverridesTests: XCTestCase {
    // MARK: - isEmpty

    func testDefaultIsEmpty() {
        let overrides = ProgramOverrides()
        XCTAssertTrue(overrides.isEmpty)
    }

    func testPartialOverrideNotEmpty() {
        var overrides = ProgramOverrides()
        overrides.dxvk = true
        XCTAssertFalse(overrides.isEmpty)
    }

    // MARK: - Codable Round-Trip

    func testCodableRoundTripAllNil() throws {
        let overrides = ProgramOverrides()
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(overrides)
        let decoded = try PropertyListDecoder().decode(ProgramOverrides.self, from: data)
        XCTAssertTrue(decoded.isEmpty)
        XCTAssertEqual(decoded, overrides)
    }

    func testCodableRoundTripPartialValues() throws {
        var overrides = ProgramOverrides()
        overrides.dxvk = true
        overrides.enhancedSync = .msync

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(overrides)
        let decoded = try PropertyListDecoder().decode(ProgramOverrides.self, from: data)
        XCTAssertEqual(decoded.dxvk, true)
        XCTAssertEqual(decoded.enhancedSync, .msync)
        XCTAssertNil(decoded.dxvkAsync)
        XCTAssertNil(decoded.forceD3D11)
    }

    // MARK: - Backward Compatibility

    func testProgramSettingsWithoutOverridesKeyDecodesNil() throws {
        // Simulate an existing plist without the "overrides" key
        let settings = ProgramSettings()
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(settings)
        let decoded = try PropertyListDecoder().decode(ProgramSettings.self, from: data)
        XCTAssertNil(decoded.overrides)
    }

    func testBottleSettingsWithoutCustomDLLOverridesDecodesEmpty() throws {
        // Simulate an existing plist without the "customDLLOverrides" key
        let settings = BottleSettings()
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(settings)
        let decoded = try PropertyListDecoder().decode(BottleSettings.self, from: data)
        XCTAssertTrue(decoded.dllOverrides.isEmpty)
    }
}
