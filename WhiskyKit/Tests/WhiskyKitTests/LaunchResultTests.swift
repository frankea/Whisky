//
//  LaunchResultTests.swift
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

final class LaunchResultTests: XCTestCase {
    // MARK: - Enum Case Creation Tests

    func testLaunchedSuccessfullyCreation() {
        let result = LaunchResult.launchedSuccessfully(programName: "TestApp.exe")

        if case let .launchedSuccessfully(name) = result {
            XCTAssertEqual(name, "TestApp.exe")
        } else {
            XCTFail("Expected launchedSuccessfully case")
        }
    }

    func testLaunchedInTerminalCreation() {
        let result = LaunchResult.launchedInTerminal(programName: "Steam.exe")

        if case let .launchedInTerminal(name) = result {
            XCTAssertEqual(name, "Steam.exe")
        } else {
            XCTFail("Expected launchedInTerminal case")
        }
    }

    func testLaunchFailedCreation() {
        let result = LaunchResult.launchFailed(programName: "Broken.exe", errorDescription: "File not found")

        if case let .launchFailed(name, error) = result {
            XCTAssertEqual(name, "Broken.exe")
            XCTAssertEqual(error, "File not found")
        } else {
            XCTFail("Expected launchFailed case")
        }
    }

    // MARK: - programName Computed Property Tests

    func testProgramNameForSuccessfulLaunch() {
        let result = LaunchResult.launchedSuccessfully(programName: "Game.exe")
        XCTAssertEqual(result.programName, "Game.exe")
    }

    func testProgramNameForTerminalLaunch() {
        let result = LaunchResult.launchedInTerminal(programName: "Launcher.exe")
        XCTAssertEqual(result.programName, "Launcher.exe")
    }

    func testProgramNameForFailedLaunch() {
        let result = LaunchResult.launchFailed(programName: "App.exe", errorDescription: "Error")
        XCTAssertEqual(result.programName, "App.exe")
    }

    func testProgramNameWithSpecialCharacters() {
        let specialName = "My Game (2024) - Special Edition.exe"
        let result = LaunchResult.launchedSuccessfully(programName: specialName)
        XCTAssertEqual(result.programName, specialName)
    }

    func testProgramNameWithUnicode() {
        let unicodeName = "ゲーム.exe"
        let result = LaunchResult.launchedInTerminal(programName: unicodeName)
        XCTAssertEqual(result.programName, unicodeName)
    }

    func testProgramNameWithEmptyString() {
        let result = LaunchResult.launchedSuccessfully(programName: "")
        XCTAssertEqual(result.programName, "")
    }

    // MARK: - errorDescription Computed Property Tests

    func testErrorDescriptionForSuccessfulLaunchIsNil() {
        let result = LaunchResult.launchedSuccessfully(programName: "App.exe")
        XCTAssertNil(result.errorDescription)
    }

    func testErrorDescriptionForTerminalLaunchIsNil() {
        let result = LaunchResult.launchedInTerminal(programName: "App.exe")
        XCTAssertNil(result.errorDescription)
    }

    func testErrorDescriptionForFailedLaunch() {
        let errorMessage = "Wine process failed with exit code 1"
        let result = LaunchResult.launchFailed(programName: "App.exe", errorDescription: errorMessage)
        XCTAssertEqual(result.errorDescription, errorMessage)
    }

    func testErrorDescriptionWithEmptyErrorString() {
        let result = LaunchResult.launchFailed(programName: "App.exe", errorDescription: "")
        XCTAssertEqual(result.errorDescription, "")
    }

    func testErrorDescriptionWithLongErrorMessage() {
        let longError = String(repeating: "Error details. ", count: 100)
        let result = LaunchResult.launchFailed(programName: "App.exe", errorDescription: longError)
        XCTAssertEqual(result.errorDescription, longError)
    }

    // MARK: - Sendable Conformance Tests

    func testSendableConformanceWithSuccessfulLaunch() async {
        let result = LaunchResult.launchedSuccessfully(programName: "App.exe")

        // Verify we can safely pass across actor boundaries
        let capturedResult = await Task.detached {
            result
        }.value

        XCTAssertEqual(capturedResult.programName, "App.exe")
    }

    func testSendableConformanceWithTerminalLaunch() async {
        let result = LaunchResult.launchedInTerminal(programName: "App.exe")

        let capturedResult = await Task.detached {
            result
        }.value

        XCTAssertEqual(capturedResult.programName, "App.exe")
    }

    func testSendableConformanceWithFailedLaunch() async {
        let result = LaunchResult.launchFailed(programName: "App.exe", errorDescription: "Error")

        let capturedResult = await Task.detached {
            result
        }.value

        XCTAssertEqual(capturedResult.programName, "App.exe")
        XCTAssertEqual(capturedResult.errorDescription, "Error")
    }

    // MARK: - Equality Tests (via switch matching)

    func testDistinctCasesAreDifferent() {
        let success = LaunchResult.launchedSuccessfully(programName: "App.exe")
        let terminal = LaunchResult.launchedInTerminal(programName: "App.exe")
        let failed = LaunchResult.launchFailed(programName: "App.exe", errorDescription: "Error")

        // Each case should match only itself
        if case .launchedSuccessfully = success {
            // Expected
        } else {
            XCTFail("success should match launchedSuccessfully")
        }

        if case .launchedInTerminal = terminal {
            // Expected
        } else {
            XCTFail("terminal should match launchedInTerminal")
        }

        if case .launchFailed = failed {
            // Expected
        } else {
            XCTFail("failed should match launchFailed")
        }
    }

    // MARK: - Edge Case Tests

    func testLaunchResultWithVeryLongProgramName() {
        let longName = String(repeating: "a", count: 1_000) + ".exe"
        let result = LaunchResult.launchedSuccessfully(programName: longName)
        XCTAssertEqual(result.programName, longName)
    }

    func testLaunchResultWithPathSeparators() {
        let pathName = "C:\\Program Files\\Game\\app.exe"
        let result = LaunchResult.launchedSuccessfully(programName: pathName)
        XCTAssertEqual(result.programName, pathName)
    }
}
