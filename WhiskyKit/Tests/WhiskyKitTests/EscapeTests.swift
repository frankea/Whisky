//
//  EscapeTests.swift
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

/// Tests for String.esc and URL.esc shell escaping extensions
final class EscapeTests: XCTestCase {
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

    // MARK: - Control Character Filtering Tests (Security)

    func testEscRemovesNewlineCharacters() {
        // Newlines could enable command injection through command chaining
        let testString = "file\nname"
        let escaped = testString.esc

        XCTAssertFalse(escaped.contains("\n"), "Newline should be removed")
        XCTAssertEqual(escaped, "filename")

        // Multiple newlines
        let multiNewline = "path\n\n\nfile"
        XCTAssertEqual(multiNewline.esc, "pathfile")
    }

    func testEscRemovesTabCharacters() {
        let testString = "file\tname"
        let escaped = testString.esc

        XCTAssertFalse(escaped.contains("\t"), "Tab should be removed")
        XCTAssertEqual(escaped, "filename")
    }

    func testEscRemovesCarriageReturns() {
        let testString = "file\rname"
        let escaped = testString.esc

        XCTAssertFalse(escaped.contains("\r"), "Carriage return should be removed")
        XCTAssertEqual(escaped, "filename")

        // Windows-style line endings
        let windowsNewline = "file\r\nname"
        XCTAssertEqual(windowsNewline.esc, "filename")
    }

    func testEscRemovesOtherControlCharacters() {
        // ASCII 0 (null)
        let withNull = "file\0name"
        XCTAssertFalse(withNull.esc.contains("\0"), "Null character should be removed")

        // ASCII 7 (bell)
        let withBell = "file\u{07}name"
        XCTAssertEqual(withBell.esc, "filename")

        // ASCII 27 (escape)
        let withEscape = "file\u{1B}name"
        XCTAssertEqual(withEscape.esc, "filename")

        // ASCII 127 (delete)
        let withDelete = "file\u{7F}name"
        XCTAssertEqual(withDelete.esc, "filename")
    }

    func testEscPreservesUnicodeCharacters() {
        // Unicode characters should be preserved (non-ASCII)
        let withEmoji = "file 🍷 name"
        XCTAssertTrue(withEmoji.esc.contains("🍷"), "Emoji should be preserved")

        // Accented characters
        let withAccents = "café"
        XCTAssertTrue(withAccents.esc.contains("é"), "Accented characters should be preserved")

        // CJK characters
        let withCJK = "文件"
        XCTAssertEqual(withCJK.esc, "文件", "CJK characters should be preserved")

        // Mixed Unicode and spaces (spaces should be escaped, Unicode preserved)
        let mixed = "файл name"
        let escaped = mixed.esc
        XCTAssertTrue(escaped.contains("файл"), "Cyrillic should be preserved")
        XCTAssertTrue(escaped.contains("\\ "), "Space should be escaped")
    }

    func testEscCombinedControlAndMetacharacters() {
        // Test that control char removal happens before metachar escaping
        let complex = "file\nwith spaces\t& special$chars\r"
        let escaped = complex.esc

        // Control characters removed
        XCTAssertFalse(escaped.contains("\n"))
        XCTAssertFalse(escaped.contains("\t"))
        XCTAssertFalse(escaped.contains("\r"))

        // Metacharacters escaped
        XCTAssertTrue(escaped.contains("\\ "), "Spaces should be escaped")
        XCTAssertTrue(escaped.contains("\\&"), "Ampersand should be escaped")
        XCTAssertTrue(escaped.contains("\\$"), "Dollar sign should be escaped")
    }
}
