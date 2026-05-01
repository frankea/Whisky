//
//  PathHandlingTests.swift
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

/// Tests for path handling with special characters in Wine commands and shortcut creation.
///
/// Verifies that paths containing spaces, parentheses, apostrophes, ampersands, brackets,
/// and Unicode characters are correctly handled through URL construction and shell escaping.
final class PathHandlingTests: XCTestCase {
    // MARK: - URL Construction with Special Characters

    func testURLConstructionWithSpaces() {
        let path = "/path/to/My Game (x86)/game.exe"
        let url = URL(fileURLWithPath: path)
        XCTAssertEqual(url.path(percentEncoded: false), path)
        XCTAssertEqual(url.lastPathComponent, "game.exe")
    }

    func testURLConstructionWithParentheses() {
        let path = "/path/to/Game (Special Edition)/launcher.exe"
        let url = URL(fileURLWithPath: path)
        XCTAssertEqual(url.path(percentEncoded: false), path)
    }

    func testURLConstructionWithApostrophe() {
        let path = "/path/to/John's Game/game.exe"
        let url = URL(fileURLWithPath: path)
        XCTAssertEqual(url.path(percentEncoded: false), path)
    }

    func testURLConstructionWithAmpersand() {
        let path = "/path/to/Tom & Jerry/game.exe"
        let url = URL(fileURLWithPath: path)
        XCTAssertEqual(url.path(percentEncoded: false), path)
    }

    func testURLConstructionWithBrackets() {
        let path = "/path/to/Game [Special]/game.exe"
        let url = URL(fileURLWithPath: path)
        XCTAssertEqual(url.path(percentEncoded: false), path)
    }

    func testURLConstructionWithUnicode() {
        let path = "/path/to/Jeu Francais/jeu.exe"
        let url = URL(fileURLWithPath: path)
        XCTAssertEqual(url.path(percentEncoded: false), path)
    }

    // MARK: - Shell Escape (String.esc) with Path Characters

    func testEscapePathWithSpaces() {
        let path = "/path/to/My Game/game.exe"
        let escaped = path.esc
        XCTAssertEqual(escaped, "/path/to/My\\ Game/game.exe")
    }

    func testEscapePathWithParentheses() {
        let path = "/path/to/My Game (x86)/game.exe"
        let escaped = path.esc
        XCTAssertTrue(escaped.contains("\\(x86\\)"), "Parentheses should be escaped")
        XCTAssertTrue(escaped.contains("My\\ Game"), "Spaces should be escaped")
    }

    func testEscapePathWithApostrophe() {
        let path = "/path/to/John's Game/game.exe"
        let escaped = path.esc
        XCTAssertTrue(escaped.contains("John\\'s"), "Apostrophe should be escaped")
    }

    func testEscapePathWithAmpersand() {
        let path = "/path/to/Tom & Jerry/game.exe"
        let escaped = path.esc
        XCTAssertTrue(escaped.contains("\\&"), "Ampersand should be escaped")
    }

    func testEscapePathWithBrackets() {
        let path = "/path/to/Game [Special]/game.exe"
        let escaped = path.esc
        XCTAssertTrue(escaped.contains("\\[Special\\]"), "Brackets should be escaped")
    }

    // MARK: - URL.esc Round-Trip

    func testURLEscapeRoundTrip() {
        // Verify that URL(fileURLWithPath:) -> .esc produces a valid shell-safe path
        let originalPath = "/path/to/My Game (x86)/game.exe"
        let url = URL(fileURLWithPath: originalPath)
        let escaped = url.esc

        // The escaped string should contain backslash-escaped special chars
        XCTAssertTrue(escaped.contains("My\\ Game"), "Space in path should be escaped")
        XCTAssertTrue(escaped.contains("\\(x86\\)"), "Parentheses should be escaped")

        // Original path should be recoverable by removing backslash escapes
        let unescaped = escaped.replacingOccurrences(of: "\\", with: "")
        XCTAssertEqual(unescaped, originalPath)
    }

    func testURLEscapeRoundTripWithApostropheAndAmpersand() {
        let originalPath = "/path/to/John's Tom & Jerry/game.exe"
        let url = URL(fileURLWithPath: originalPath)
        let escaped = url.esc

        XCTAssertTrue(escaped.contains("\\'"), "Apostrophe should be escaped")
        XCTAssertTrue(escaped.contains("\\&"), "Ampersand should be escaped")

        let unescaped = escaped.replacingOccurrences(of: "\\", with: "")
        XCTAssertEqual(unescaped, originalPath)
    }

    // MARK: - Combined Special Characters

    func testPathWithAllSpecialCharacters() {
        // A path that combines multiple special character types
        let path = "/Users/test/My Games (2024)/John's [Best] & More/game.exe"
        let url = URL(fileURLWithPath: path)

        // URL preserves the path
        XCTAssertEqual(url.path(percentEncoded: false), path)

        // Escaping handles all special characters
        let escaped = url.esc
        XCTAssertTrue(escaped.contains("My\\ Games"), "Spaces escaped")
        XCTAssertTrue(escaped.contains("\\(2024\\)"), "Parentheses escaped")
        XCTAssertTrue(escaped.contains("\\'s"), "Apostrophe escaped")
        XCTAssertTrue(escaped.contains("\\[Best\\]"), "Brackets escaped")
        XCTAssertTrue(escaped.contains("\\&"), "Ampersand escaped")
    }

    // MARK: - ShortcutCreator Bundle Creation

    func testShortcutCreatorCreatesBundleStructure() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "PathHandlingTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let appURL = tempDir.appending(path: "Test Game.app")
        let launchScript = "echo hello"

        try ShortcutCreator.createShortcutBundle(at: appURL, launchScript: launchScript, name: "Test Game")

        // Verify bundle structure
        let contentsURL = appURL.appending(path: "Contents")
        let macosURL = contentsURL.appending(path: "MacOS")
        let launchURL = macosURL.appending(path: "launch")
        let infoPlistURL = contentsURL.appending(path: "Info.plist")

        XCTAssertTrue(FileManager.default.fileExists(atPath: launchURL.path(percentEncoded: false)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: infoPlistURL.path(percentEncoded: false)))

        // Verify launch script content
        let scriptContent = try String(contentsOf: launchURL, encoding: .utf8)
        XCTAssertTrue(scriptContent.hasPrefix("#!/bin/bash\n"))
        XCTAssertTrue(scriptContent.contains("echo hello"))

        // Verify launch script is executable (0o755)
        let attributes = try FileManager.default.attributesOfItem(atPath: launchURL.path(percentEncoded: false))
        let permissions = attributes[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o755)
    }

    func testShortcutCreatorWithSpecialCharactersInPath() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "PathHandlingTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create an app bundle with special characters in the name
        let appURL = tempDir.appending(path: "John's Game (x86).app")
        let launchScript = "/path/to/wine start /unix /path/to/John\\'s\\ Game\\ \\(x86\\)/game.exe"

        try ShortcutCreator.createShortcutBundle(at: appURL, launchScript: launchScript, name: "John's Game (x86)")

        let launchURL = appURL.appending(path: "Contents").appending(path: "MacOS").appending(path: "launch")
        XCTAssertTrue(FileManager.default.fileExists(atPath: launchURL.path(percentEncoded: false)))

        let scriptContent = try String(contentsOf: launchURL, encoding: .utf8)
        XCTAssertTrue(scriptContent.contains("John\\'s\\ Game"))
    }
}
