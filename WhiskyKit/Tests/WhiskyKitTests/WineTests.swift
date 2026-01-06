//
//  WineTests.swift
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

final class WineTests: XCTestCase {

    // MARK: - MacOSVersion Tests

    func testMacOSVersionInitialization() {
        let version = MacOSVersion(major: 15, minor: 4, patch: 1)

        XCTAssertEqual(version.major, 15)
        XCTAssertEqual(version.minor, 4)
        XCTAssertEqual(version.patch, 1)
    }

    func testMacOSVersionDescription() {
        let version = MacOSVersion(major: 15, minor: 4, patch: 1)
        XCTAssertEqual(version.description, "15.4.1")

        let versionNoPatch = MacOSVersion(major: 14, minor: 0, patch: 0)
        XCTAssertEqual(versionNoPatch.description, "14.0.0")
    }

    func testMacOSVersionComparableMajor() {
        let older = MacOSVersion(major: 14, minor: 5, patch: 0)
        let newer = MacOSVersion(major: 15, minor: 0, patch: 0)

        XCTAssertTrue(older < newer)
        XCTAssertFalse(newer < older)
    }

    func testMacOSVersionComparableMinor() {
        let older = MacOSVersion(major: 15, minor: 3, patch: 0)
        let newer = MacOSVersion(major: 15, minor: 4, patch: 0)

        XCTAssertTrue(older < newer)
        XCTAssertFalse(newer < older)
    }

    func testMacOSVersionComparablePatch() {
        let older = MacOSVersion(major: 15, minor: 4, patch: 0)
        let newer = MacOSVersion(major: 15, minor: 4, patch: 1)

        XCTAssertTrue(older < newer)
        XCTAssertFalse(newer < older)
    }

    func testMacOSVersionEquality() {
        let version1 = MacOSVersion(major: 15, minor: 4, patch: 1)
        let version2 = MacOSVersion(major: 15, minor: 4, patch: 1)

        XCTAssertTrue(version1 == version2)
        XCTAssertFalse(version1 < version2)
        XCTAssertFalse(version2 < version1)
    }

    func testMacOSVersionPredefinedConstants() {
        // Test that predefined constants have expected values
        XCTAssertEqual(MacOSVersion.sequoia15_3.major, 15)
        XCTAssertEqual(MacOSVersion.sequoia15_3.minor, 3)
        XCTAssertEqual(MacOSVersion.sequoia15_3.patch, 0)

        XCTAssertEqual(MacOSVersion.sequoia15_4.major, 15)
        XCTAssertEqual(MacOSVersion.sequoia15_4.minor, 4)
        XCTAssertEqual(MacOSVersion.sequoia15_4.patch, 0)

        XCTAssertEqual(MacOSVersion.sequoia15_4_1.major, 15)
        XCTAssertEqual(MacOSVersion.sequoia15_4_1.minor, 4)
        XCTAssertEqual(MacOSVersion.sequoia15_4_1.patch, 1)
    }

    func testMacOSVersionComparableWithPredefinedConstants() {
        // sequoia15_3 < sequoia15_4 < sequoia15_4_1
        XCTAssertTrue(MacOSVersion.sequoia15_3 < MacOSVersion.sequoia15_4)
        XCTAssertTrue(MacOSVersion.sequoia15_4 < MacOSVersion.sequoia15_4_1)
        XCTAssertTrue(MacOSVersion.sequoia15_3 < MacOSVersion.sequoia15_4_1)
    }

    func testMacOSVersionCurrentExists() {
        // Just verify current version can be accessed and has valid values
        let current = MacOSVersion.current

        XCTAssertGreaterThan(current.major, 0)
        XCTAssertGreaterThanOrEqual(current.minor, 0)
        XCTAssertGreaterThanOrEqual(current.patch, 0)
    }

    func testMacOSVersionGreaterThanOrEqual() {
        let sequoia153 = MacOSVersion.sequoia15_3
        let sequoia154 = MacOSVersion.sequoia15_4

        XCTAssertTrue(sequoia154 >= sequoia153)
        XCTAssertTrue(sequoia153 >= sequoia153)
        XCTAssertFalse(sequoia153 >= sequoia154)
    }

    // MARK: - RegistryType Tests

    func testRegistryTypeRawValues() {
        XCTAssertEqual(RegistryType.binary.rawValue, "REG_BINARY")
        XCTAssertEqual(RegistryType.dword.rawValue, "REG_DWORD")
        XCTAssertEqual(RegistryType.qword.rawValue, "REG_QWORD")
        XCTAssertEqual(RegistryType.string.rawValue, "REG_SZ")
    }

    // MARK: - WineInterfaceError Tests

    func testWineInterfaceErrorExists() {
        let error = WineInterfaceError.invalidResponse

        XCTAssertNotNil(error)
        // Verify it conforms to Error protocol
        let _: Error = error
    }

    // MARK: - Wine Static Properties Tests

    func testWineStaticPropertiesExist() {
        // Verify static paths exist and are valid URLs
        XCTAssertNotNil(Wine.wineBinary)
        XCTAssertTrue(Wine.wineBinary.path.contains("wine64"))

        XCTAssertNotNil(Wine.logsFolder)
        XCTAssertTrue(Wine.logsFolder.path.contains("Logs"))
    }

    // MARK: - URL Escape Extension Tests

    func testURLEscapeExtension() {
        // Test the existing esc extension from WhiskyKit
        let testURL = URL(fileURLWithPath: "/Applications/Test App.exe")
        let escaped = testURL.esc

        // Verify the exact expected escaped output
        XCTAssertFalse(escaped.isEmpty)
        XCTAssertEqual(escaped, "/Applications/Test\\ App.exe")
    }

    func testURLEscapeExtensionWithSpecialCharacters() {
        // Test escaping of various special shell characters
        let testURL = URL(fileURLWithPath: "/path/with (parentheses) & other$chars.exe")
        let escaped = testURL.esc

        XCTAssertTrue(escaped.contains("\\("), "Parentheses should be escaped")
        XCTAssertTrue(escaped.contains("\\&"), "Ampersand should be escaped")
        XCTAssertTrue(escaped.contains("\\$"), "Dollar sign should be escaped")
    }

    func testStringEscapeExtension() {
        // Test the String.esc extension
        let testString = "file with spaces & special$chars"
        let escaped = testString.esc

        XCTAssertTrue(escaped.contains("\\ "), "Spaces should be escaped")
        XCTAssertTrue(escaped.contains("\\&"), "Ampersand should be escaped")
        XCTAssertTrue(escaped.contains("\\$"), "Dollar sign should be escaped")
    }
}
