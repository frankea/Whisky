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

    // MARK: - Username Detection Caching Behavior Tests

    /// Verifies that detectWineUsername returns consistent results for the same directory.
    ///
    /// Note: The Whisky app's `Bottle.wineUsername` property wraps this function with
    /// a `@MainActor`-isolated cache to avoid repeated filesystem scans. This test
    /// verifies the underlying detection returns consistent results.
    func testDetectWineUsernameReturnsConsistentResults() throws {
        let usersDir = tempDir.appendingPathComponent("users")
        try FileManager.default.createDirectory(at: usersDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: usersDir.appendingPathComponent("testuser"),
            withIntermediateDirectories: true
        )

        // Multiple calls should return the same result
        let result1 = WinePrefixValidation.detectWineUsername(in: usersDir)
        let result2 = WinePrefixValidation.detectWineUsername(in: usersDir)
        let result3 = WinePrefixValidation.detectWineUsername(in: usersDir)

        XCTAssertEqual(result1, "testuser")
        XCTAssertEqual(result1, result2)
        XCTAssertEqual(result2, result3)
    }

    /// Verifies that nil result from detectWineUsername allows fallback to default.
    ///
    /// The Whisky app's `Bottle.wineUsername` property falls back to "crossover" when
    /// this function returns nil. This test verifies the nil behavior.
    func testDetectWineUsernameNilAllowsFallback() throws {
        let usersDir = tempDir.appendingPathComponent("users")
        try FileManager.default.createDirectory(at: usersDir, withIntermediateDirectories: true)
        // Only Public directory, no valid user
        try FileManager.default.createDirectory(
            at: usersDir.appendingPathComponent("Public"),
            withIntermediateDirectories: true
        )

        let username = WinePrefixValidation.detectWineUsername(in: usersDir)

        // Returns nil, allowing caller to use fallback (e.g., "crossover")
        XCTAssertNil(username)
        // Demonstrate fallback pattern used by Bottle.wineUsername
        let fallbackUsername = username ?? "crossover"
        XCTAssertEqual(fallbackUsername, "crossover")
    }

    // MARK: - validatePrefix Tests

    /// Helper to create a complete valid Wine prefix structure.
    private func createValidPrefixStructure(at bottleURL: URL, username: String = "testuser") throws {
        let driveC = bottleURL.appendingPathComponent("drive_c")
        let usersDir = driveC.appendingPathComponent("users")
        let userProfile = usersDir.appendingPathComponent(username)
        let appData = userProfile.appendingPathComponent("AppData")
        let roaming = appData.appendingPathComponent("Roaming")
        let local = appData.appendingPathComponent("Local")

        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: roaming, withIntermediateDirectories: true)
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
        // Don't create any directories

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
        // Don't create drive_c

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
        // Don't create users directory

        let bottle = Bottle(bottleUrl: bottleURL)
        let result = WinePrefixValidation.validatePrefix(for: bottle)

        if case let .corruptedPrefix(diagnostics) = result {
            XCTAssertTrue(diagnostics.prefixExists)
            XCTAssertTrue(diagnostics.driveCExists)
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
        // Don't create any user profile directories

        let bottle = Bottle(bottleUrl: bottleURL)
        let result = WinePrefixValidation.validatePrefix(for: bottle)

        if case let .missingUserProfile(diagnostics) = result {
            XCTAssertTrue(diagnostics.usersDirectoryExists)
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
        // Create user profile but NOT AppData
        try FileManager.default.createDirectory(at: userProfile, withIntermediateDirectories: true)

        let bottle = Bottle(bottleUrl: bottleURL)
        let result = WinePrefixValidation.validatePrefix(for: bottle)

        if case let .missingAppData(diagnostics) = result {
            XCTAssertTrue(diagnostics.userProfileExists)
            XCTAssertFalse(diagnostics.appDataExists)
            XCTAssertFalse(diagnostics.roamingExists)
            XCTAssertFalse(diagnostics.localAppDataExists)
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
        let local = appData.appendingPathComponent("Local")
        // Create AppData and Local but NOT Roaming
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)

        let bottle = Bottle(bottleUrl: bottleURL)
        let result = WinePrefixValidation.validatePrefix(for: bottle)

        if case let .missingAppData(diagnostics) = result {
            XCTAssertTrue(diagnostics.appDataExists)
            XCTAssertFalse(diagnostics.roamingExists)
            XCTAssertTrue(diagnostics.localAppDataExists)
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
        let roaming = appData.appendingPathComponent("Roaming")
        // Create AppData and Roaming but NOT Local
        try FileManager.default.createDirectory(at: roaming, withIntermediateDirectories: true)

        let bottle = Bottle(bottleUrl: bottleURL)
        let result = WinePrefixValidation.validatePrefix(for: bottle)

        if case let .missingAppData(diagnostics) = result {
            XCTAssertTrue(diagnostics.appDataExists)
            XCTAssertTrue(diagnostics.roamingExists)
            XCTAssertFalse(diagnostics.localAppDataExists)
        } else {
            XCTFail("Expected missingAppData result")
        }
    }

    @MainActor
    func testValidatePrefixDiagnosticsIncludesPrefixPath() throws {
        let bottleURL = tempDir.appendingPathComponent("TestBottle")
        // Don't create anything - should return corruptedPrefix with diagnostics

        let bottle = Bottle(bottleUrl: bottleURL)
        let result = WinePrefixValidation.validatePrefix(for: bottle)

        if let diagnostics = result.diagnostics {
            XCTAssertEqual(diagnostics.prefixPath, bottleURL.path)
        } else {
            XCTFail("Expected diagnostics to be present")
        }
    }

    @MainActor
    func testValidatePrefixDiagnosticsRecordsEvents() throws {
        let bottleURL = tempDir.appendingPathComponent("TestBottle")
        try createValidPrefixStructure(at: bottleURL)

        let bottle = Bottle(bottleUrl: bottleURL)
        // For a valid result, diagnostics is nil, but we can test an invalid case
        let invalidBottle = Bottle(bottleUrl: tempDir.appendingPathComponent("Invalid"))
        let result = WinePrefixValidation.validatePrefix(for: invalidBottle)

        if let diagnostics = result.diagnostics {
            XCTAssertFalse(diagnostics.events.isEmpty, "Diagnostics should record events")
            // Should have at least "Starting prefix validation" event
            XCTAssertTrue(diagnostics.events.contains { $0.contains("Starting prefix validation") })
        } else {
            XCTFail("Expected diagnostics with events")
        }
    }
}
