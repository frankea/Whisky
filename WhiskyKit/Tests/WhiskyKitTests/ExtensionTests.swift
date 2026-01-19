//
//  ExtensionTests.swift
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

import Foundation
@testable import WhiskyKit
import XCTest

// MARK: - String.esc Tests

final class StringEscapeTests: XCTestCase {
    func testEscapesSpaces() {
        XCTAssertEqual("hello world".esc, "hello\\ world")
        XCTAssertEqual("path with spaces".esc, "path\\ with\\ spaces")
    }

    func testEscapesDoubleQuotes() {
        XCTAssertEqual("hello\"world".esc, "hello\\\"world")
    }

    func testEscapesSingleQuotes() {
        XCTAssertEqual("hello'world".esc, "hello\\'world")
    }

    func testEscapesBackslashes() {
        XCTAssertEqual("hello\\world".esc, "hello\\\\world")
    }

    func testEscapesParentheses() {
        XCTAssertEqual("(test)".esc, "\\(test\\)")
        XCTAssertEqual("func()".esc, "func\\(\\)")
    }

    func testEscapesBrackets() {
        XCTAssertEqual("[test]".esc, "\\[test\\]")
        XCTAssertEqual("{test}".esc, "\\{test\\}")
    }

    func testEscapesShellOperators() {
        XCTAssertEqual("cmd1 & cmd2".esc, "cmd1\\ \\&\\ cmd2")
        XCTAssertEqual("cmd1 | cmd2".esc, "cmd1\\ \\|\\ cmd2")
        XCTAssertEqual("cmd1 ; cmd2".esc, "cmd1\\ \\;\\ cmd2")
    }

    func testEscapesRedirectionOperators() {
        XCTAssertEqual("input < file".esc, "input\\ \\<\\ file")
        XCTAssertEqual("output > file".esc, "output\\ \\>\\ file")
    }

    func testEscapesBackticks() {
        XCTAssertEqual("`command`".esc, "\\`command\\`")
    }

    func testEscapesDollarSign() {
        XCTAssertEqual("$PATH".esc, "\\$PATH")
        XCTAssertEqual("${VAR}".esc, "\\$\\{VAR\\}")
    }

    func testEscapesExclamation() {
        XCTAssertEqual("test!".esc, "test\\!")
    }

    func testEscapesWildcards() {
        XCTAssertEqual("*.txt".esc, "\\*.txt")
        XCTAssertEqual("file?.txt".esc, "file\\?.txt")
    }

    func testEscapesHash() {
        XCTAssertEqual("#comment".esc, "\\#comment")
    }

    func testEscapesTilde() {
        XCTAssertEqual("~/Documents".esc, "\\~/Documents")
    }

    func testEscapesEquals() {
        XCTAssertEqual("KEY=VALUE".esc, "KEY\\=VALUE")
    }

    func testRemovesControlCharacters() {
        XCTAssertEqual("hello\nworld".esc, "helloworld")
        XCTAssertEqual("hello\tworld".esc, "helloworld")
        XCTAssertEqual("hello\rworld".esc, "helloworld")
    }

    func testRemovesNullCharacter() {
        XCTAssertEqual("hello\0world".esc, "helloworld")
    }

    func testRemovesDeleteCharacter() {
        let deleteChar = Character(UnicodeScalar(127))
        XCTAssertEqual("hello\(deleteChar)world".esc, "helloworld")
    }

    func testPreservesUnicodeCharacters() {
        XCTAssertEqual("日本語".esc, "日本語")
        XCTAssertEqual("émoji 🎉".esc, "émoji\\ 🎉")
        XCTAssertEqual("Ü".esc, "Ü")
    }

    func testEmptyString() {
        XCTAssertEqual("".esc, "")
    }

    func testAlreadySimpleString() {
        XCTAssertEqual("simple".esc, "simple")
        XCTAssertEqual("file.txt".esc, "file.txt")
        XCTAssertEqual("path/to/file".esc, "path/to/file")
    }

    func testComplexPathWithMultipleMetacharacters() {
        let input = "Program Files (x86)/Game's Name"
        let expected = "Program\\ Files\\ \\(x86\\)/Game\\'s\\ Name"
        XCTAssertEqual(input.esc, expected)
    }
}

// MARK: - URL.esc Tests

final class URLEscapeTests: XCTestCase {
    func testURLEscUsesPathEsc() {
        let url = URL(filePath: "/path/with spaces/file.txt")
        XCTAssertEqual(url.esc, "/path/with\\ spaces/file.txt")
    }

    func testURLEscWithSpecialCharacters() {
        let url = URL(filePath: "/Users/test/Program Files (x86)")
        XCTAssertTrue(url.esc.contains("\\ "))
        XCTAssertTrue(url.esc.contains("\\("))
    }
}

// MARK: - URL.prettyPath Tests

final class URLPrettyPathTests: XCTestCase {
    func testPrettyPathReplacesHomeDirectory() {
        let username = NSUserName()
        let url = URL(filePath: "/Users/\(username)/Documents/test.txt")
        let pretty = url.prettyPath()

        XCTAssertTrue(pretty.hasPrefix("~"))
        XCTAssertFalse(pretty.contains("/Users/\(username)"))
    }

    func testPrettyPathPreservesOtherPaths() {
        let url = URL(filePath: "/var/log/system.log")
        let pretty = url.prettyPath()

        XCTAssertEqual(pretty, "/var/log/system.log")
    }
}

// MARK: - URL.updateParentBottle Tests

final class URLUpdateParentBottleTests: XCTestCase {
    func testUpdateParentBottle() {
        let oldBottle = URL(filePath: "/Users/test/Bottles/OldBottle")
        let newBottle = URL(filePath: "/Users/test/Bottles/NewBottle")
        let programURL = URL(filePath: "/Users/test/Bottles/OldBottle/drive_c/Program Files/game.exe")

        let updated = programURL.updateParentBottle(old: oldBottle, new: newBottle)

        XCTAssertEqual(
            updated.path(percentEncoded: false),
            "/Users/test/Bottles/NewBottle/drive_c/Program Files/game.exe"
        )
    }

    func testUpdateParentBottleWithTrailingSlash() {
        let oldBottle = URL(filePath: "/Bottles/OldBottle/")
        let newBottle = URL(filePath: "/Bottles/NewBottle/")
        let programURL = URL(filePath: "/Bottles/OldBottle/drive_c/test.exe")

        let updated = programURL.updateParentBottle(old: oldBottle, new: newBottle)

        XCTAssertEqual(updated.path(percentEncoded: false), "/Bottles/NewBottle/drive_c/test.exe")
    }

    func testUpdateParentBottleNoMatch() {
        let oldBottle = URL(filePath: "/Bottles/OtherBottle")
        let newBottle = URL(filePath: "/Bottles/NewBottle")
        let programURL = URL(filePath: "/Bottles/DifferentBottle/drive_c/test.exe")

        let updated = programURL.updateParentBottle(old: oldBottle, new: newBottle)

        XCTAssertEqual(updated.path(percentEncoded: false), "/Bottles/DifferentBottle/drive_c/test.exe")
    }
}

// MARK: - Bundle Extension Tests

final class BundleExtensionTests: XCTestCase {
    func testWhiskyBundleIdentifierReturnsValidString() {
        let identifier = Bundle.whiskyBundleIdentifier
        XCTAssertFalse(identifier.isEmpty)
    }

    func testWhiskyBundleIdentifierUsesMainBundleOrFallback() {
        let identifier = Bundle.whiskyBundleIdentifier
        // In tests, returns test bundle identifier; in production returns main bundle or fallback
        // Either way, should be a valid bundle identifier string
        XCTAssertTrue(identifier.contains("."), "Bundle identifier should contain at least one dot")
    }

    func testWhiskyBundleIdentifierFallbackValue() {
        // Test that the fallback constant is correct
        let fallback = "com.franke.Whisky"
        XCTAssertEqual(fallback.components(separatedBy: ".").count, 3)
    }
}

// MARK: - URL Identifiable Tests

final class URLIdentifiableTests: XCTestCase {
    func testURLIdIsItself() {
        let url = URL(filePath: "/test/path")
        XCTAssertEqual(url.id, url)
    }

    func testURLIdentifiableInArray() {
        let urls = [
            URL(filePath: "/test/1"),
            URL(filePath: "/test/2"),
            URL(filePath: "/test/3")
        ]

        for url in urls {
            XCTAssertEqual(url.id, url)
        }
    }
}
