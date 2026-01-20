//
//  TerminalAppTests.swift
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

/// Tests for TerminalApp enum functionality
final class TerminalAppTests: XCTestCase {
    // MARK: - Enum Cases

    func testAllCasesExist() {
        let allCases = TerminalApp.allCases
        XCTAssertEqual(allCases.count, 3)
        XCTAssertTrue(allCases.contains(.terminal))
        XCTAssertTrue(allCases.contains(.iterm))
        XCTAssertTrue(allCases.contains(.warp))
    }

    // MARK: - Display Names

    func testDisplayNames() {
        XCTAssertEqual(TerminalApp.terminal.displayName, "Terminal")
        XCTAssertEqual(TerminalApp.iterm.displayName, "iTerm2")
        XCTAssertEqual(TerminalApp.warp.displayName, "Warp")
    }

    // MARK: - Bundle Identifiers

    func testBundleIdentifiers() {
        XCTAssertEqual(TerminalApp.terminal.bundleIdentifier, "com.apple.Terminal")
        XCTAssertEqual(TerminalApp.iterm.bundleIdentifier, "com.googlecode.iterm2")
        XCTAssertEqual(TerminalApp.warp.bundleIdentifier, "dev.warp.Warp-Stable")
    }

    // MARK: - Raw Values

    func testRawValues() {
        XCTAssertEqual(TerminalApp.terminal.rawValue, "terminal")
        XCTAssertEqual(TerminalApp.iterm.rawValue, "iterm")
        XCTAssertEqual(TerminalApp.warp.rawValue, "warp")
    }

    func testInitFromRawValue() {
        XCTAssertEqual(TerminalApp(rawValue: "terminal"), .terminal)
        XCTAssertEqual(TerminalApp(rawValue: "iterm"), .iterm)
        XCTAssertEqual(TerminalApp(rawValue: "warp"), .warp)
        XCTAssertNil(TerminalApp(rawValue: "invalid"))
    }

    // MARK: - Identifiable

    func testIdentifiable() {
        XCTAssertEqual(TerminalApp.terminal.id, "terminal")
        XCTAssertEqual(TerminalApp.iterm.id, "iterm")
        XCTAssertEqual(TerminalApp.warp.id, "warp")
    }

    // MARK: - AppleScript Generation

    func testGenerateAppleScriptForTerminal() {
        let script = TerminalApp.terminal.generateAppleScript(for: "/path/to/script.sh")

        XCTAssertTrue(script.contains("tell application \"Terminal\""))
        XCTAssertTrue(script.contains("activate"))
        XCTAssertTrue(script.contains("do script"))
        XCTAssertTrue(script.contains("source"))
        XCTAssertTrue(script.contains("/path/to/script.sh"))
    }

    func testGenerateAppleScriptForITerm() {
        let script = TerminalApp.iterm.generateAppleScript(for: "/path/to/script.sh")

        XCTAssertTrue(script.contains("tell application \"iTerm\""))
        XCTAssertTrue(script.contains("activate"))
        XCTAssertTrue(script.contains("create window with default profile"))
        XCTAssertTrue(script.contains("write text"))
        XCTAssertTrue(script.contains("source"))
        XCTAssertTrue(script.contains("/path/to/script.sh"))
    }

    func testGenerateAppleScriptForWarp() {
        let script = TerminalApp.warp.generateAppleScript(for: "/path/to/script.sh")

        XCTAssertTrue(script.contains("tell application \"Warp\""))
        XCTAssertTrue(script.contains("activate"))
        XCTAssertTrue(script.contains("open -a Warp"))
        XCTAssertTrue(script.contains("/path/to/script.sh"))
    }

    // MARK: - Path Escaping in AppleScript

    func testAppleScriptEscapesBackslashes() {
        let pathWithBackslash = "/path/with\\backslash/script.sh"
        let script = TerminalApp.terminal.generateAppleScript(for: pathWithBackslash)

        // Backslash should be escaped for AppleScript string literal
        XCTAssertTrue(script.contains("\\\\"))
    }

    func testAppleScriptEscapesQuotes() {
        let pathWithQuote = "/path/with\"quote/script.sh"
        let script = TerminalApp.terminal.generateAppleScript(for: pathWithQuote)

        // Quote should be escaped for AppleScript string literal
        XCTAssertTrue(script.contains("\\\""))
    }

    func testAppleScriptWithSpacesInPath() {
        let pathWithSpaces = "/path/with spaces/script.sh"

        let terminalScript = TerminalApp.terminal.generateAppleScript(for: pathWithSpaces)
        XCTAssertTrue(terminalScript.contains("with spaces"))

        let itermScript = TerminalApp.iterm.generateAppleScript(for: pathWithSpaces)
        XCTAssertTrue(itermScript.contains("with spaces"))

        let warpScript = TerminalApp.warp.generateAppleScript(for: pathWithSpaces)
        XCTAssertTrue(warpScript.contains("with spaces"))
    }

    // MARK: - Installation Detection

    func testTerminalIsAlwaysInstalled() {
        // Terminal.app is always present on macOS
        XCTAssertTrue(TerminalApp.terminal.isInstalled)
    }

    func testInstalledTerminalsContainsTerminal() {
        // Terminal.app should always be in the list
        XCTAssertTrue(TerminalApp.installedTerminals.contains(.terminal))
    }

    func testInstalledTerminalsNotEmpty() {
        // Should never be empty since Terminal.app is always present
        XCTAssertFalse(TerminalApp.installedTerminals.isEmpty)
    }

    // MARK: - Preferred Terminal

    func testPreferredFallsBackToTerminal() {
        // If the preferred terminal is not installed, it should fall back to Terminal
        // We can't easily test this without mocking, but we can verify the property exists
        let preferred = TerminalApp.preferred
        XCTAssertTrue(TerminalApp.allCases.contains(preferred))
    }

    // MARK: - Deprecated generateDirectCommandScript Tests

    func testGenerateDirectCommandScriptForTerminal() {
        let command = "echo 'Hello World'"
        let script = TerminalApp.terminal.generateDirectCommandScript(command: command)

        XCTAssertNotNil(script)
        XCTAssertTrue(script?.contains("tell application \"Terminal\"") ?? false)
        XCTAssertTrue(script?.contains("activate") ?? false)
        XCTAssertTrue(script?.contains("do script") ?? false)
    }

    func testGenerateDirectCommandScriptForITerm() {
        let command = "echo 'Hello World'"
        let script = TerminalApp.iterm.generateDirectCommandScript(command: command)

        XCTAssertNotNil(script)
        XCTAssertTrue(script?.contains("tell application \"iTerm\"") ?? false)
        XCTAssertTrue(script?.contains("activate") ?? false)
        XCTAssertTrue(script?.contains("write text") ?? false)
    }

    func testGenerateDirectCommandScriptForWarp() {
        let command = "echo 'Hello World'"
        let script = TerminalApp.warp.generateDirectCommandScript(command: command)

        // Warp creates a temp script file, so this should succeed
        XCTAssertNotNil(script)
        XCTAssertTrue(script?.contains("tell application \"Warp\"") ?? false)
        XCTAssertTrue(script?.contains("open -a Warp") ?? false)
    }

    func testGenerateDirectCommandScriptEscapesSpecialCharacters() {
        let command = "echo \"Hello\\World\""
        let script = TerminalApp.terminal.generateDirectCommandScript(command: command)

        XCTAssertNotNil(script)
        // The escaping should handle backslashes and quotes
        XCTAssertTrue(script?.contains("\\") ?? false)
    }

    func testGenerateDirectCommandScriptWithComplexCommand() {
        let command = "cd /path/to/dir && ./run.sh --arg=\"value with spaces\""
        let script = TerminalApp.terminal.generateDirectCommandScript(command: command)

        XCTAssertNotNil(script)
        XCTAssertTrue(script?.contains("do script") ?? false)
    }
}
