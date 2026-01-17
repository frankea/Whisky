//
//  WinePrefixValidationTests.swift
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

final class WinePrefixValidationTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir, FileManager.default.fileExists(atPath: tempDir.path) {
            try FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    func testDetectWineUsernameSkipsPublic() throws {
        let usersDir = tempDir.appendingPathComponent("users")
        try FileManager.default.createDirectory(at: usersDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: usersDir.appendingPathComponent("Public"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: usersDir.appendingPathComponent("testuser"),
            withIntermediateDirectories: true
        )

        let username = WinePrefixValidation.detectWineUsername(in: usersDir)

        XCTAssertEqual(username, "testuser")
    }

    func testDetectWineUsernamePrefersNonCrossover() throws {
        let usersDir = tempDir.appendingPathComponent("users")
        try FileManager.default.createDirectory(at: usersDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: usersDir.appendingPathComponent("crossover"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: usersDir.appendingPathComponent("realuser"),
            withIntermediateDirectories: true
        )

        let username = WinePrefixValidation.detectWineUsername(in: usersDir)

        XCTAssertEqual(username, "realuser")
    }

    func testDetectWineUsernameFallsBackToCrossover() throws {
        let usersDir = tempDir.appendingPathComponent("users")
        try FileManager.default.createDirectory(at: usersDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: usersDir.appendingPathComponent("Public"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: usersDir.appendingPathComponent("crossover"),
            withIntermediateDirectories: true
        )

        let username = WinePrefixValidation.detectWineUsername(in: usersDir)

        XCTAssertEqual(username, "crossover")
    }

    func testDetectWineUsernameReturnsNilForEmptyDir() throws {
        let usersDir = tempDir.appendingPathComponent("users")
        try FileManager.default.createDirectory(at: usersDir, withIntermediateDirectories: true)

        let username = WinePrefixValidation.detectWineUsername(in: usersDir)

        XCTAssertNil(username)
    }

    func testDetectWineUsernameReturnsNilForMissingDir() {
        let usersDir = tempDir.appendingPathComponent("nonexistent")

        let username = WinePrefixValidation.detectWineUsername(in: usersDir)

        XCTAssertNil(username)
    }

    func testDetectWineUsernameIgnoresFiles() throws {
        let usersDir = tempDir.appendingPathComponent("users")
        try FileManager.default.createDirectory(at: usersDir, withIntermediateDirectories: true)
        // Create a file instead of a directory
        try Data("test".utf8).write(to: usersDir.appendingPathComponent("notauser"))
        try FileManager.default.createDirectory(
            at: usersDir.appendingPathComponent("realuser"),
            withIntermediateDirectories: true
        )

        let username = WinePrefixValidation.detectWineUsername(in: usersDir)

        XCTAssertEqual(username, "realuser")
    }

    func testValidationResultIsValidProperty() {
        let valid = WinePrefixValidation.ValidationResult.valid
        let missing = WinePrefixValidation.ValidationResult.missingAppData(diagnostics: WinePrefixDiagnostics())

        XCTAssertTrue(valid.isValid)
        XCTAssertFalse(missing.isValid)
    }

    func testValidationResultDiagnosticsProperty() {
        let diagnostics = WinePrefixDiagnostics()
        let valid = WinePrefixValidation.ValidationResult.valid
        let missing = WinePrefixValidation.ValidationResult.missingAppData(diagnostics: diagnostics)

        XCTAssertNil(valid.diagnostics)
        XCTAssertNotNil(missing.diagnostics)
    }
}
