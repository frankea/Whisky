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

// MARK: - Username Detection Tests

final class WinePrefixUsernameDetectionTests: XCTestCase {
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
        try Data("test".utf8).write(to: usersDir.appendingPathComponent("notauser"))
        try FileManager.default.createDirectory(
            at: usersDir.appendingPathComponent("realuser"),
            withIntermediateDirectories: true
        )

        let username = WinePrefixValidation.detectWineUsername(in: usersDir)

        XCTAssertEqual(username, "realuser")
    }

    func testDetectWineUsernameReturnsConsistentResults() throws {
        let usersDir = tempDir.appendingPathComponent("users")
        try FileManager.default.createDirectory(at: usersDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: usersDir.appendingPathComponent("testuser"),
            withIntermediateDirectories: true
        )

        let result1 = WinePrefixValidation.detectWineUsername(in: usersDir)
        let result2 = WinePrefixValidation.detectWineUsername(in: usersDir)

        XCTAssertEqual(result1, "testuser")
        XCTAssertEqual(result1, result2)
    }

    func testDetectWineUsernameNilAllowsFallback() throws {
        let usersDir = tempDir.appendingPathComponent("users")
        try FileManager.default.createDirectory(at: usersDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: usersDir.appendingPathComponent("Public"),
            withIntermediateDirectories: true
        )

        let username = WinePrefixValidation.detectWineUsername(in: usersDir)

        XCTAssertNil(username)
        XCTAssertEqual(username ?? "crossover", "crossover")
    }
}

// MARK: - ValidationResult Tests

final class WinePrefixValidationResultTests: XCTestCase {
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

// MARK: - validatePrefix Tests

final class ValidatePrefixTests: XCTestCase {
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

    private func createValidPrefixStructure(at bottleURL: URL, username: String = "testuser") throws {
        let appData = bottleURL
            .appendingPathComponent("drive_c")
            .appendingPathComponent("users")
            .appendingPathComponent(username)
            .appendingPathComponent("AppData")
        try FileManager.default.createDirectory(
            at: appData.appendingPathComponent("Local"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: appData.appendingPathComponent("Roaming"),
            withIntermediateDirectories: true
        )
    }

    @MainActor
    func testValidatePrefixReturnsValidForCompleteStructure() throws {
        let bottleURL = tempDir.appendingPathComponent("TestBottle")
        try createValidPrefixStructure(at: bottleURL)

        let bottle = Bottle(bottleUrl: bottleURL)
        let result = WinePrefixValidation.validatePrefix(for: bottle)

        XCTAssertTrue(result.isValid)
        XCTAssertNil(result.diagnostics)
    }

    @MainActor
    func testValidatePrefixReturnsCorruptedForMissingPrefix() throws {
        let bottleURL = tempDir.appendingPathComponent("NonExistentBottle")

        let bottle = Bottle(bottleUrl: bottleURL)
        let result = WinePrefixValidation.validatePrefix(for: bottle)

        if case let .corruptedPrefix(diagnostics) = result {
            XCTAssertFalse(diagnostics.prefixExists)
        } else {
            XCTFail("Expected corruptedPrefix result")
        }
    }

    @MainActor
    func testValidatePrefixReturnsCorruptedForMissingDriveC() throws {
        let bottleURL = tempDir.appendingPathComponent("TestBottle")
        try FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)

        let bottle = Bottle(bottleUrl: bottleURL)
        let result = WinePrefixValidation.validatePrefix(for: bottle)

        if case let .corruptedPrefix(diagnostics) = result {
            XCTAssertTrue(diagnostics.prefixExists)
            XCTAssertFalse(diagnostics.driveCExists)
        } else {
            XCTFail("Expected corruptedPrefix result")
        }
    }

    @MainActor
    func testValidatePrefixReturnsCorruptedForMissingUsersDir() throws {
        let bottleURL = tempDir.appendingPathComponent("TestBottle")
        let driveC = bottleURL.appendingPathComponent("drive_c")
        try FileManager.default.createDirectory(at: driveC, withIntermediateDirectories: true)

        let bottle = Bottle(bottleUrl: bottleURL)
        let result = WinePrefixValidation.validatePrefix(for: bottle)

        if case let .corruptedPrefix(diagnostics) = result {
            XCTAssertFalse(diagnostics.usersDirectoryExists)
        } else {
            XCTFail("Expected corruptedPrefix result")
        }
    }

    @MainActor
    func testValidatePrefixReturnsMissingUserProfileForEmptyUsersDir() throws {
        let bottleURL = tempDir.appendingPathComponent("TestBottle")
        let usersDir = bottleURL.appendingPathComponent("drive_c").appendingPathComponent("users")
        try FileManager.default.createDirectory(at: usersDir, withIntermediateDirectories: true)

        let bottle = Bottle(bottleUrl: bottleURL)
        let result = WinePrefixValidation.validatePrefix(for: bottle)

        if case let .missingUserProfile(diagnostics) = result {
            XCTAssertNil(diagnostics.detectedUsername)
        } else {
            XCTFail("Expected missingUserProfile result")
        }
    }

    @MainActor
    func testValidatePrefixReturnsMissingAppDataForIncompleteStructure() throws {
        let bottleURL = tempDir.appendingPathComponent("TestBottle")
        let userProfile = bottleURL
            .appendingPathComponent("drive_c")
            .appendingPathComponent("users")
            .appendingPathComponent("testuser")
        try FileManager.default.createDirectory(at: userProfile, withIntermediateDirectories: true)

        let bottle = Bottle(bottleUrl: bottleURL)
        let result = WinePrefixValidation.validatePrefix(for: bottle)

        if case let .missingAppData(diagnostics) = result {
            XCTAssertFalse(diagnostics.appDataExists)
        } else {
            XCTFail("Expected missingAppData result")
        }
    }

    @MainActor
    func testValidatePrefixReturnsMissingAppDataForMissingRoaming() throws {
        let bottleURL = tempDir.appendingPathComponent("TestBottle")
        let appData = bottleURL
            .appendingPathComponent("drive_c")
            .appendingPathComponent("users")
            .appendingPathComponent("testuser")
            .appendingPathComponent("AppData")
        try FileManager.default.createDirectory(
            at: appData.appendingPathComponent("Local"),
            withIntermediateDirectories: true
        )

        let bottle = Bottle(bottleUrl: bottleURL)
        let result = WinePrefixValidation.validatePrefix(for: bottle)

        if case let .missingAppData(diagnostics) = result {
            XCTAssertFalse(diagnostics.roamingExists)
        } else {
            XCTFail("Expected missingAppData result")
        }
    }

    @MainActor
    func testValidatePrefixReturnsMissingAppDataForMissingLocal() throws {
        let bottleURL = tempDir.appendingPathComponent("TestBottle")
        let appData = bottleURL
            .appendingPathComponent("drive_c")
            .appendingPathComponent("users")
            .appendingPathComponent("testuser")
            .appendingPathComponent("AppData")
        try FileManager.default.createDirectory(
            at: appData.appendingPathComponent("Roaming"),
            withIntermediateDirectories: true
        )

        let bottle = Bottle(bottleUrl: bottleURL)
        let result = WinePrefixValidation.validatePrefix(for: bottle)

        if case let .missingAppData(diagnostics) = result {
            XCTAssertFalse(diagnostics.localAppDataExists)
        } else {
            XCTFail("Expected missingAppData result")
        }
    }

    @MainActor
    func testValidatePrefixDiagnosticsIncludesPrefixPath() throws {
        let bottleURL = tempDir.appendingPathComponent("TestBottle")

        let bottle = Bottle(bottleUrl: bottleURL)
        let result = WinePrefixValidation.validatePrefix(for: bottle)

        XCTAssertEqual(result.diagnostics?.prefixPath, bottleURL.path)
    }

    @MainActor
    func testValidatePrefixDiagnosticsRecordsEvents() throws {
        let bottleURL = tempDir.appendingPathComponent("Invalid")

        let bottle = Bottle(bottleUrl: bottleURL)
        let result = WinePrefixValidation.validatePrefix(for: bottle)

        XCTAssertFalse(result.diagnostics?.events.isEmpty ?? true)
        XCTAssertTrue(result.diagnostics?.events.contains { $0.contains("Starting") } ?? false)
    }
}
