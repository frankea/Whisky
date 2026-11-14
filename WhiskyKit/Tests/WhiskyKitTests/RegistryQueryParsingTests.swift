//
//  RegistryQueryParsingTests.swift
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

/// `reg query` output as Wine prints it: a key line, then one line per value
/// with four-space separators, CRLF line endings.
final class RegistryQueryParsingTests: XCTestCase {
    private func output(_ valueLine: String) -> String {
        "\r\nHKEY_CURRENT_USER\\Software\\Wine\\Drivers\r\n\(valueLine)\r\n\r\n"
    }

    func testStringValue() {
        let value = Wine.registryValue(fromQueryOutput: output("    Audio    REG_SZ    coreaudio"), type: .string)
        XCTAssertEqual(value, "coreaudio")
    }

    func testEmptyStringValueIsEmptyNotTheTypeName() {
        // A disabled audio driver is stored as Audio="". Wine prints no data
        // token for it, which the old parser read back as "REG_SZ".
        let value = Wine.registryValue(fromQueryOutput: output("    Audio    REG_SZ    "), type: .string)
        XCTAssertEqual(value, "")
    }

    func testEmptyStringValueWithoutTrailingSpaces() {
        let value = Wine.registryValue(fromQueryOutput: output("    Audio    REG_SZ"), type: .string)
        XCTAssertEqual(value, "")
    }

    func testValueWithSpacesComesBackWhole() {
        let value = Wine.registryValue(
            fromQueryOutput: output("    Path    REG_SZ    C:\\Program Files\\Some Game"),
            type: .string
        )
        XCTAssertEqual(value, "C:\\Program Files\\Some Game")
    }

    func testDwordValue() {
        let value = Wine.registryValue(fromQueryOutput: output("    LogPixels    REG_DWORD    0x90"), type: .dword)
        XCTAssertEqual(value, "0x90")
    }

    func testBinaryValue() {
        // Wine prints REG_BINARY data as contiguous uppercase hex.
        let value = Wine.registryValue(
            fromQueryOutput: output("    guid    REG_BINARY    53FAF8B304008E43900351A46E139BFC"),
            type: .binary
        )
        XCTAssertEqual(value, "53FAF8B304008E43900351A46E139BFC")
    }

    func testMissingValueIsNil() {
        XCTAssertNil(Wine.registryValue(
            fromQueryOutput: "\r\nHKEY_CURRENT_USER\\Software\\Wine\\Drivers\r\n",
            type: .string
        ))
        XCTAssertNil(Wine.registryValue(fromQueryOutput: "", type: .string))
    }

    func testOtherTypesDoNotMatch() {
        // REG_EXPAND_SZ and REG_MULTI_SZ are not REG_SZ.
        XCTAssertNil(Wine.registryValue(
            fromQueryOutput: output("    Path    REG_EXPAND_SZ    %SystemRoot%"),
            type: .string
        ))
        XCTAssertNil(Wine.registryValue(fromQueryOutput: output("    Audio    REG_SZ    x"), type: .dword))
    }

    func testTypeNameInsideTheValueNameIsSkipped() {
        let value = Wine.registryValue(
            fromQueryOutput: output("    MY_REG_SZ_NAME    REG_SZ    data"),
            type: .string
        )
        XCTAssertEqual(value, "data")
    }
}
