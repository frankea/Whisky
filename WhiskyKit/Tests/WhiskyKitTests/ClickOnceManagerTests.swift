//
//  ClickOnceManagerTests.swift
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
import Testing
@testable import WhiskyKit

@Suite("ClickOnceManager Tests")
struct ClickOnceManagerTests {
    // MARK: - Detection Tests

    @Test("Detects ClickOnce directory when it doesn't exist")
    @MainActor func detectAppRefFileNoDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let bottle = Bottle(bottleUrl: tempDir)
        let appRefs = ClickOnceManager.shared.detectAppRefFile(in: bottle)

        #expect(appRefs.isEmpty, "Should return empty array when ClickOnce directory doesn't exist")
    }

    @Test("Detects ClickOnce appref-ms files")
    @MainActor func detectAppRefFileFindsFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let clickOnceDir = tempDir
            .appending(path: "drive_c")
            .appending(path: "users")
            .appending(path: "crossover")
            .appending(path: "AppData")
            .appending(path: "Roaming")
            .appending(path: "Microsoft")
            .appending(path: "ClickOnce")

        try FileManager.default.createDirectory(at: clickOnceDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create test appref-ms files
        let appRef1 = clickOnceDir.appending(path: "TestApp1.appref-ms")
        let appRef2 = clickOnceDir.appending(path: "TestApp2.appref-ms")
        try "Test Content 1".write(to: appRef1, atomically: true, encoding: .utf8)
        try "Test Content 2".write(to: appRef2, atomically: true, encoding: .utf8)

        let bottle = Bottle(bottleUrl: tempDir)
        let appRefs = ClickOnceManager.shared.detectAppRefFile(in: bottle)

        #expect(appRefs.count == 2, "Should detect 2 appref-ms files")
        #expect(appRefs.contains(where: { $0.lastPathComponent == "TestApp1.appref-ms" }))
        #expect(appRefs.contains(where: { $0.lastPathComponent == "TestApp2.appref-ms" }))
    }

    @Test("Ignores non-appref-ms files")
    @MainActor func detectAppRefFileIgnoresOtherFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let clickOnceDir = tempDir
            .appending(path: "drive_c")
            .appending(path: "users")
            .appending(path: "crossover")
            .appending(path: "AppData")
            .appending(path: "Roaming")
            .appending(path: "Microsoft")
            .appending(path: "ClickOnce")

        try FileManager.default.createDirectory(at: clickOnceDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create various file types
        let appRef = clickOnceDir.appending(path: "TestApp.appref-ms")
        let textFile = clickOnceDir.appending(path: "readme.txt")
        let exeFile = clickOnceDir.appending(path: "setup.exe")

        try "Test Content".write(to: appRef, atomically: true, encoding: .utf8)
        try "Readme".write(to: textFile, atomically: true, encoding: .utf8)
        try "Fake exe".write(to: exeFile, atomically: true, encoding: .utf8)

        let bottle = Bottle(bottleUrl: tempDir)
        let appRefs = ClickOnceManager.shared.detectAppRefFile(in: bottle)

        #expect(appRefs.count == 1, "Should only detect .appref-ms files")
        #expect(appRefs[0].lastPathComponent == "TestApp.appref-ms")
    }

    // MARK: - Parsing Tests

    @Test("Parses valid ClickOnce manifest")
    func parseManifestValid() throws {
        let tempFile = FileManager.default.temporaryDirectory.appending(path: "TestApp.appref-ms")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let content = """
        [InternetShortcut]
        URL=http://example.com/apps/TestApp/TestApp.application?version=1.2.3.4
        """
        try content.write(to: tempFile, atomically: true, encoding: .utf8)

        let manifest = try ClickOnceManager.shared.parseManifest(from: tempFile)

        #expect(manifest.name == "TestApp.application", "Name should be extracted from URL")
        #expect(manifest.version == "1.2.3.4", "Version should be extracted from query parameter")
        #expect(manifest.publisher == "Unknown", "Publisher should default to Unknown")
        #expect(manifest.url.absoluteString.contains("example.com"), "URL should be preserved")
    }

    @Test("Parses manifest with minimal URL")
    func parseManifestMinimalURL() throws {
        let tempFile = FileManager.default.temporaryDirectory.appending(path: "MyApp.appref-ms")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let content = """
        [InternetShortcut]
        URL=http://example.com/app.application
        """
        try content.write(to: tempFile, atomically: true, encoding: .utf8)

        let manifest = try ClickOnceManager.shared.parseManifest(from: tempFile)

        #expect(manifest.name == "app.application", "Name should be extracted from URL")
        #expect(manifest.version == "1.0.0.0", "Version should default to 1.0.0.0")
    }

    @Test("Throws error when file not found")
    func parseManifestFileNotFound() throws {
        let nonExistentFile = FileManager.default.temporaryDirectory.appending(path: "nonexistent.appref-ms")

        #expect(throws: ClickOnceError.self) {
            _ = try ClickOnceManager.shared.parseManifest(from: nonExistentFile)
        }
    }

    @Test("Throws error for invalid manifest without URL")
    func parseManifestInvalidNoURL() throws {
        let tempFile = FileManager.default.temporaryDirectory.appending(path: "Invalid.appref-ms")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let content = """
        [InternetShortcut]
        SomeOtherField=value
        """
        try content.write(to: tempFile, atomically: true, encoding: .utf8)

        #expect(throws: ClickOnceError.self) {
            _ = try ClickOnceManager.shared.parseManifest(from: tempFile)
        }
    }

    @Test("Parses manifest with version query parameter")
    func parseManifestWithVersionParameter() throws {
        let tempFile = FileManager.default.temporaryDirectory.appending(path: "VersionedApp.appref-ms")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let content = """
        [InternetShortcut]
        URL=http://example.com/apps/MyApp.application?v=2.5.1.0
        """
        try content.write(to: tempFile, atomically: true, encoding: .utf8)

        let manifest = try ClickOnceManager.shared.parseManifest(from: tempFile)

        #expect(manifest.version == "2.5.1.0", "Version should be extracted from 'v' parameter")
    }

    // MARK: - Environment Tests

    @Test("Generates environment variables for manifest")
    func getEnvironment() {
        let manifest = ClickOnceManager.ClickOnceManifest(
            name: "TestApp",
            url: URL(string: "http://example.com/app.application") ?? URL(fileURLWithPath: "/"),
            version: "1.2.3.4",
            publisher: "TestPublisher",
            supportUrl: URL(string: "http://support.example.com"),
            description: "Test application"
        )

        let env = ClickOnceManager.shared.getEnvironment(for: manifest)

        #expect(env["CLICKONCE_APP"] == "TestApp")
        #expect(env["CLICKONCE_VERSION"] == "1.2.3.4")
        #expect(env["CLICKONCE_PUBLISHER"] == "TestPublisher")
        #expect(env["CLICKONCE_SUPPORT_URL"] == "http://support.example.com")
        #expect(env["CLICKONCE_DESCRIPTION"] == "Test application")
    }

    @Test("Generates environment with optional fields missing")
    func getEnvironmentMinimal() {
        let manifest = ClickOnceManager.ClickOnceManifest(
            name: "MinimalApp",
            url: URL(string: "http://example.com/app.application") ?? URL(fileURLWithPath: "/"),
            version: "1.0.0.0",
            publisher: "Unknown",
            supportUrl: nil,
            description: nil
        )

        let env = ClickOnceManager.shared.getEnvironment(for: manifest)

        #expect(env["CLICKONCE_APP"] == "MinimalApp")
        #expect(env["CLICKONCE_VERSION"] == "1.0.0.0")
        #expect(env["CLICKONCE_PUBLISHER"] == "Unknown")
        #expect(env["CLICKONCE_SUPPORT_URL"] == nil, "Optional field should not be present")
        #expect(env["CLICKONCE_DESCRIPTION"] == nil, "Optional field should not be present")
    }

    // MARK: - Validation Tests

    @Test("Validates correct manifest")
    func validateManifestValid() {
        let manifest = ClickOnceManager.ClickOnceManifest(
            name: "ValidApp",
            url: URL(string: "http://example.com/app.application") ?? URL(fileURLWithPath: "/"),
            version: "1.2.3.4",
            publisher: "TestPublisher",
            supportUrl: nil,
            description: nil
        )

        let isValid = ClickOnceManager.shared.validateManifest(manifest)
        #expect(isValid == true, "Valid manifest should pass validation")
    }

    @Test("Rejects manifest with empty name")
    func validateManifestEmptyName() {
        let manifest = ClickOnceManager.ClickOnceManifest(
            name: "",
            url: URL(string: "http://example.com/app.application") ?? URL(fileURLWithPath: "/"),
            version: "1.2.3.4",
            publisher: "TestPublisher",
            supportUrl: nil,
            description: nil
        )

        let isValid = ClickOnceManager.shared.validateManifest(manifest)
        #expect(isValid == false, "Manifest with empty name should fail validation")
    }

    @Test("Rejects manifest with empty version")
    func validateManifestEmptyVersion() {
        let manifest = ClickOnceManager.ClickOnceManifest(
            name: "TestApp",
            url: URL(string: "http://example.com/app.application") ?? URL(fileURLWithPath: "/"),
            version: "",
            publisher: "TestPublisher",
            supportUrl: nil,
            description: nil
        )

        let isValid = ClickOnceManager.shared.validateManifest(manifest)
        #expect(isValid == false, "Manifest with empty version should fail validation")
    }

    @Test("Rejects manifest with empty publisher")
    func validateManifestEmptyPublisher() {
        let manifest = ClickOnceManager.ClickOnceManifest(
            name: "TestApp",
            url: URL(string: "http://example.com/app.application") ?? URL(fileURLWithPath: "/"),
            version: "1.2.3.4",
            publisher: "",
            supportUrl: nil,
            description: nil
        )

        let isValid = ClickOnceManager.shared.validateManifest(manifest)
        #expect(isValid == false, "Manifest with empty publisher should fail validation")
    }

    @Test("Accepts manifest with non-standard version format")
    func validateManifestNonStandardVersion() {
        let manifest = ClickOnceManager.ClickOnceManifest(
            name: "TestApp",
            url: URL(string: "http://example.com/app.application") ?? URL(fileURLWithPath: "/"),
            version: "1.2-beta",
            publisher: "TestPublisher",
            supportUrl: nil,
            description: nil
        )

        // Non-standard version should still validate (just logs debug warning)
        let isValid = ClickOnceManager.shared.validateManifest(manifest)
        #expect(isValid == true, "Non-standard version format should still validate")
    }

    // MARK: - Installation Tests

    @Test("Installation completes without error")
    @MainActor func install() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let bottle = Bottle(bottleUrl: tempDir)
        let manifest = ClickOnceManager.ClickOnceManifest(
            name: "TestApp",
            url: URL(string: "http://example.com/app.application") ?? URL(fileURLWithPath: "/"),
            version: "1.0.0.0",
            publisher: "TestPublisher",
            supportUrl: nil,
            description: "Test app"
        )

        // Should not throw
        try await ClickOnceManager.shared.install(manifest: manifest, in: bottle)
    }

    // MARK: - Error Tests

    @Test("ClickOnceError provides error descriptions")
    func errorDescriptions() {
        let fileNotFoundError = ClickOnceError.fileNotFound(URL(fileURLWithPath: "/test/path.appref-ms"))
        let invalidManifestError = ClickOnceError.invalidManifest("Missing URL")
        let installationFailedError = ClickOnceError.installationFailed("Wine error")

        #expect(fileNotFoundError.errorDescription?.contains("not found") == true)
        #expect(invalidManifestError.errorDescription?.contains("Invalid") == true)
        #expect(installationFailedError.errorDescription?.contains("failed") == true)
    }

    @Test("ClickOnceError provides recovery suggestions")
    func errorRecoverySuggestions() {
        let fileNotFoundError = ClickOnceError.fileNotFound(URL(fileURLWithPath: "/test/path.appref-ms"))
        let invalidManifestError = ClickOnceError.invalidManifest("Missing URL")
        let installationFailedError = ClickOnceError.installationFailed("Wine error")

        #expect(fileNotFoundError.recoverySuggestion != nil)
        #expect(invalidManifestError.recoverySuggestion != nil)
        #expect(installationFailedError.recoverySuggestion != nil)
    }
}
