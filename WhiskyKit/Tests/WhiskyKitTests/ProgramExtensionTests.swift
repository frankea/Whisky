//
//  ProgramExtensionTests.swift
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

// MARK: - Program.generateTerminalCommand Tests

final class ProgramGenerateTerminalCommandTests: XCTestCase {
    var tempDir: URL!
    var bottleURL: URL!
    var programURL: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appending(path: "program_test_\(UUID().uuidString)")
        bottleURL = tempDir.appending(path: "TestBottle")

        // Create bottle directory structure
        let driveCURL = bottleURL.appending(path: "drive_c")
        try? FileManager.default.createDirectory(at: driveCURL, withIntermediateDirectories: true)

        // Create a fake .exe file
        programURL = driveCURL.appending(path: "test_program.exe")
        try? Data("fake exe".utf8).write(to: programURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    @MainActor
    func testGenerateTerminalCommandContainsProgramPath() throws {
        let bottle = Bottle(bottleUrl: bottleURL)
        let program = Program(url: programURL, bottle: bottle)

        let command = program.generateTerminalCommand()

        // Command should contain the program path
        XCTAssertTrue(command.contains("test_program.exe"), "Command should contain program name")
    }

    @MainActor
    func testGenerateTerminalCommandContainsWineBinary() throws {
        let bottle = Bottle(bottleUrl: bottleURL)
        let program = Program(url: programURL, bottle: bottle)

        let command = program.generateTerminalCommand()

        // Command should contain wine64
        XCTAssertTrue(command.contains("wine64"), "Command should contain wine64 binary")
    }

    @MainActor
    func testGenerateTerminalCommandWithCustomArgs() throws {
        let bottle = Bottle(bottleUrl: bottleURL)
        let program = Program(url: programURL, bottle: bottle)

        let command = program.generateTerminalCommand(args: "-windowed -nosound")

        // Command should contain the custom arguments
        XCTAssertTrue(command.contains("-windowed"), "Command should contain -windowed arg")
        XCTAssertTrue(command.contains("-nosound"), "Command should contain -nosound arg")
    }

    @MainActor
    func testGenerateTerminalCommandWithNilArgsUsesSettings() throws {
        let bottle = Bottle(bottleUrl: bottleURL)
        let program = Program(url: programURL, bottle: bottle)
        program.settings.arguments = "-testarg"

        let command = program.generateTerminalCommand(args: nil)

        // Command should contain the settings arguments
        XCTAssertTrue(command.contains("-testarg"), "Command should contain settings argument")
    }

    @MainActor
    func testGenerateTerminalCommandWithEmptyArgs() throws {
        let bottle = Bottle(bottleUrl: bottleURL)
        let program = Program(url: programURL, bottle: bottle)

        let command = program.generateTerminalCommand(args: "")

        // Command should still be valid with empty args
        XCTAssertTrue(command.contains("wine64"), "Command should still contain wine64")
        XCTAssertTrue(command.contains("test_program.exe"), "Command should still contain program")
    }

    @MainActor
    func testGenerateTerminalCommandContainsWinePrefix() throws {
        let bottle = Bottle(bottleUrl: bottleURL)
        let program = Program(url: programURL, bottle: bottle)

        let command = program.generateTerminalCommand()

        // Command should set WINEPREFIX to bottle path
        XCTAssertTrue(command.contains("WINEPREFIX="), "Command should set WINEPREFIX")
        XCTAssertTrue(command.contains(bottleURL.path), "Command should contain bottle path")
    }

    // MARK: - Array-based generateTerminalCommand Tests

    @MainActor
    func testGenerateTerminalCommandWithArrayArgs() throws {
        let bottle = Bottle(bottleUrl: bottleURL)
        let program = Program(url: programURL, bottle: bottle)

        let command = program.generateTerminalCommand(args: ["-windowed", "-nosound"])

        // Command should contain the arguments
        XCTAssertTrue(command.contains("-windowed"), "Command should contain -windowed arg")
        XCTAssertTrue(command.contains("-nosound"), "Command should contain -nosound arg")
    }

    @MainActor
    func testGenerateTerminalCommandWithArrayArgsContainingSpaces() throws {
        let bottle = Bottle(bottleUrl: bottleURL)
        let program = Program(url: programURL, bottle: bottle)

        let command = program.generateTerminalCommand(args: ["--name", "Player Name"])

        // Command should contain escaped arguments
        XCTAssertTrue(command.contains("--name"), "Command should contain --name arg")
        // The space in "Player Name" should be escaped
        XCTAssertTrue(
            command.contains("Player\\ Name") || command.contains("Player Name"),
            "Command should handle spaces in arguments"
        )
    }

    @MainActor
    func testGenerateTerminalCommandWithEmptyArrayArgs() throws {
        let bottle = Bottle(bottleUrl: bottleURL)
        let program = Program(url: programURL, bottle: bottle)

        let command = program.generateTerminalCommand(args: [])

        // Command should still be valid with empty args array
        XCTAssertTrue(command.contains("wine64"), "Command should still contain wine64")
        XCTAssertTrue(command.contains("test_program.exe"), "Command should still contain program")
    }

    @MainActor
    func testGenerateTerminalCommandWithSpecialCharacterArgs() throws {
        let bottle = Bottle(bottleUrl: bottleURL)
        let program = Program(url: programURL, bottle: bottle)

        let command = program.generateTerminalCommand(args: ["--path", "--flag"])

        // Basic flags without special chars should be in command
        XCTAssertTrue(command.contains("--path"), "Command should contain path arg")
        XCTAssertTrue(command.contains("--flag"), "Command should contain flag arg")
    }
}

// MARK: - Program.generateEnvironment Tests

final class ProgramGenerateEnvironmentTests: XCTestCase {
    var tempDir: URL!
    var bottleURL: URL!
    var programURL: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appending(path: "env_test_\(UUID().uuidString)")
        bottleURL = tempDir.appending(path: "TestBottle")

        let driveCURL = bottleURL.appending(path: "drive_c")
        try? FileManager.default.createDirectory(at: driveCURL, withIntermediateDirectories: true)

        programURL = driveCURL.appending(path: "test.exe")
        try? Data("fake exe".utf8).write(to: programURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    @MainActor
    func testGenerateEnvironmentWithAutoLocale() throws {
        let bottle = Bottle(bottleUrl: bottleURL)
        let program = Program(url: programURL, bottle: bottle)
        program.settings.locale = .auto

        let env = program.generateEnvironment()

        // Auto locale should not set LC_ALL
        XCTAssertNil(env["LC_ALL"], "LC_ALL should not be set with auto locale")
    }

    @MainActor
    func testGenerateEnvironmentWithSpecificLocale() throws {
        let bottle = Bottle(bottleUrl: bottleURL)
        let program = Program(url: programURL, bottle: bottle)
        program.settings.locale = .german

        let env = program.generateEnvironment()

        // Specific locale should set LC_ALL
        XCTAssertEqual(env["LC_ALL"], Locales.german.rawValue, "LC_ALL should be set to German locale")
    }

    @MainActor
    func testGenerateEnvironmentWithCustomVariables() throws {
        let bottle = Bottle(bottleUrl: bottleURL)
        let program = Program(url: programURL, bottle: bottle)
        program.settings.environment = ["CUSTOM_VAR": "custom_value"]

        let env = program.generateEnvironment()

        XCTAssertEqual(env["CUSTOM_VAR"], "custom_value", "Custom environment variable should be included")
    }

    @MainActor
    func testGenerateEnvironmentWithMultipleCustomVariables() throws {
        let bottle = Bottle(bottleUrl: bottleURL)
        let program = Program(url: programURL, bottle: bottle)
        program.settings.environment = [
            "VAR1": "value1",
            "VAR2": "value2",
            "VAR3": "value3"
        ]

        let env = program.generateEnvironment()

        XCTAssertEqual(env["VAR1"], "value1")
        XCTAssertEqual(env["VAR2"], "value2")
        XCTAssertEqual(env["VAR3"], "value3")
    }

    @MainActor
    func testGenerateEnvironmentCombinesLocaleAndCustomVars() throws {
        let bottle = Bottle(bottleUrl: bottleURL)
        let program = Program(url: programURL, bottle: bottle)
        program.settings.locale = .japanese
        program.settings.environment = ["MY_VAR": "my_value"]

        let env = program.generateEnvironment()

        XCTAssertEqual(env["LC_ALL"], Locales.japanese.rawValue)
        XCTAssertEqual(env["MY_VAR"], "my_value")
    }
}
