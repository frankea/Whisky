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

@testable import WhiskyKit
import XCTest

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

    // MARK: - Environment Variable Key Validation Tests

    func testIsValidEnvKeyWithValidKeys() {
        // Standard environment variable names
        XCTAssertTrue(Wine.isValidEnvKey("PATH"))
        XCTAssertTrue(Wine.isValidEnvKey("HOME"))
        XCTAssertTrue(Wine.isValidEnvKey("USER"))
        XCTAssertTrue(Wine.isValidEnvKey("LANG"))

        // Mixed case
        XCTAssertTrue(Wine.isValidEnvKey("MyVar"))
        XCTAssertTrue(Wine.isValidEnvKey("myVar"))

        // With underscores
        XCTAssertTrue(Wine.isValidEnvKey("MY_VAR"))
        XCTAssertTrue(Wine.isValidEnvKey("MY_LONG_VARIABLE_NAME"))
        XCTAssertTrue(Wine.isValidEnvKey("_underscore"))
        XCTAssertTrue(Wine.isValidEnvKey("_"))
        XCTAssertTrue(Wine.isValidEnvKey("__"))
        XCTAssertTrue(Wine.isValidEnvKey("___TRIPLE"))

        // With numbers (not at start)
        XCTAssertTrue(Wine.isValidEnvKey("VAR1"))
        XCTAssertTrue(Wine.isValidEnvKey("VAR123"))
        XCTAssertTrue(Wine.isValidEnvKey("MY_VAR_2"))
        XCTAssertTrue(Wine.isValidEnvKey("_1"))
        XCTAssertTrue(Wine.isValidEnvKey("A1B2C3"))

        // Single character
        XCTAssertTrue(Wine.isValidEnvKey("A"))
        XCTAssertTrue(Wine.isValidEnvKey("z"))
    }

    func testIsValidEnvKeyWithInvalidKeys() {
        // Starting with a digit (invalid per POSIX)
        XCTAssertFalse(Wine.isValidEnvKey("123start"))
        XCTAssertFalse(Wine.isValidEnvKey("1VAR"))
        XCTAssertFalse(Wine.isValidEnvKey("9"))

        // Contains hyphen
        XCTAssertFalse(Wine.isValidEnvKey("my-var"))
        XCTAssertFalse(Wine.isValidEnvKey("MY-VAR"))

        // Contains space
        XCTAssertFalse(Wine.isValidEnvKey("my var"))
        XCTAssertFalse(Wine.isValidEnvKey("MY VAR"))
        XCTAssertFalse(Wine.isValidEnvKey(" LEADING"))
        XCTAssertFalse(Wine.isValidEnvKey("TRAILING "))

        // Contains newline (potential injection vector)
        XCTAssertFalse(Wine.isValidEnvKey("my\nvar"))
        XCTAssertFalse(Wine.isValidEnvKey("VAR\n"))

        // Contains other shell special characters
        XCTAssertFalse(Wine.isValidEnvKey("VAR$NAME"))
        XCTAssertFalse(Wine.isValidEnvKey("VAR`cmd`"))
        XCTAssertFalse(Wine.isValidEnvKey("VAR;echo"))
        XCTAssertFalse(Wine.isValidEnvKey("VAR|pipe"))
        XCTAssertFalse(Wine.isValidEnvKey("VAR&bg"))
        XCTAssertFalse(Wine.isValidEnvKey("VAR=value"))
        XCTAssertFalse(Wine.isValidEnvKey("VAR'quote"))
        XCTAssertFalse(Wine.isValidEnvKey("VAR\"dquote"))
        XCTAssertFalse(Wine.isValidEnvKey("VAR(paren)"))
        XCTAssertFalse(Wine.isValidEnvKey("VAR[bracket]"))
        XCTAssertFalse(Wine.isValidEnvKey("VAR{brace}"))
        XCTAssertFalse(Wine.isValidEnvKey("VAR<redirect>"))
        XCTAssertFalse(Wine.isValidEnvKey("VAR!bang"))

        // Contains dot
        XCTAssertFalse(Wine.isValidEnvKey("my.var"))
        XCTAssertFalse(Wine.isValidEnvKey(".hidden"))

        // Contains slash
        XCTAssertFalse(Wine.isValidEnvKey("path/to"))
        XCTAssertFalse(Wine.isValidEnvKey("VAR\\backslash"))
    }

    func testIsValidEnvKeyEdgeCases() {
        // Empty string
        XCTAssertFalse(Wine.isValidEnvKey(""))

        // Unicode characters (should be rejected - POSIX only accepts ASCII)
        XCTAssertFalse(Wine.isValidEnvKey("VAR_é"))
        XCTAssertFalse(Wine.isValidEnvKey("変数"))
        XCTAssertFalse(Wine.isValidEnvKey("VАRIABLE")) // Cyrillic 'А' instead of ASCII 'A'
        XCTAssertFalse(Wine.isValidEnvKey("café"))

        // Control characters
        XCTAssertFalse(Wine.isValidEnvKey("VAR\0NULL"))
        XCTAssertFalse(Wine.isValidEnvKey("VAR\tTAB"))
        XCTAssertFalse(Wine.isValidEnvKey("VAR\rCR"))
    }

    func testIsAsciiLetter() {
        // Valid uppercase letters
        XCTAssertTrue(Wine.isAsciiLetter("A"))
        XCTAssertTrue(Wine.isAsciiLetter("M"))
        XCTAssertTrue(Wine.isAsciiLetter("Z"))

        // Valid lowercase letters
        XCTAssertTrue(Wine.isAsciiLetter("a"))
        XCTAssertTrue(Wine.isAsciiLetter("m"))
        XCTAssertTrue(Wine.isAsciiLetter("z"))

        // Invalid: digits
        XCTAssertFalse(Wine.isAsciiLetter("0"))
        XCTAssertFalse(Wine.isAsciiLetter("5"))
        XCTAssertFalse(Wine.isAsciiLetter("9"))

        // Invalid: special characters
        XCTAssertFalse(Wine.isAsciiLetter("_"))
        XCTAssertFalse(Wine.isAsciiLetter("-"))
        XCTAssertFalse(Wine.isAsciiLetter(" "))

        // Invalid: Unicode letters (looks like ASCII but isn't)
        XCTAssertFalse(Wine.isAsciiLetter("é"))
        XCTAssertFalse(Wine.isAsciiLetter("ñ"))
        XCTAssertFalse(Wine.isAsciiLetter("А")) // Cyrillic A
    }

    func testIsAsciiDigit() {
        // Valid digits
        XCTAssertTrue(Wine.isAsciiDigit("0"))
        XCTAssertTrue(Wine.isAsciiDigit("5"))
        XCTAssertTrue(Wine.isAsciiDigit("9"))

        // Invalid: letters
        XCTAssertFalse(Wine.isAsciiDigit("A"))
        XCTAssertFalse(Wine.isAsciiDigit("a"))

        // Invalid: special characters
        XCTAssertFalse(Wine.isAsciiDigit("_"))
        XCTAssertFalse(Wine.isAsciiDigit("-"))
        XCTAssertFalse(Wine.isAsciiDigit("."))

        // Invalid: Unicode digits
        XCTAssertFalse(Wine.isAsciiDigit("١")) // Arabic-Indic digit 1
        XCTAssertFalse(Wine.isAsciiDigit("①")) // Circled digit 1
    }

    // MARK: - Prefix Repair Tests

    /// Verifies that the repairPrefix method signature exists with expected modifiers.
    ///
    /// Note: Full integration testing of repairPrefix requires Wine to be installed
    /// and a valid bottle to be created, which is beyond unit test scope. This test
    /// verifies the API contract is maintained.
    func testRepairPrefixMethodExists() {
        // Verify the method is accessible as a static @MainActor async throws function
        // that returns String. This compile-time check ensures the API contract.
        let methodReference: @MainActor (Bottle) async throws -> String = Wine.repairPrefix
        XCTAssertNotNil(methodReference)
    }
}
