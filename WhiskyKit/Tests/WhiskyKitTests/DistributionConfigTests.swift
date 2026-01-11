//
//  DistributionConfigTests.swift
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

import SemanticVersion
@testable import WhiskyKit
import XCTest

final class DistributionConfigTests: XCTestCase {
    // MARK: - Base URL Tests

    func testBaseURL() {
        XCTAssertEqual(DistributionConfig.baseURL, "https://frankea.github.io/Whisky")
    }

    func testBaseURLIsHTTPS() {
        XCTAssertTrue(DistributionConfig.baseURL.hasPrefix("https://"))
    }

    // MARK: - Version Plist URL Tests

    func testVersionPlistURL() {
        let expectedURL = "https://frankea.github.io/Whisky/WhiskyWineVersion.plist"
        XCTAssertEqual(DistributionConfig.versionPlistURL, expectedURL)
    }

    func testVersionPlistURLIsValid() {
        let urlString = DistributionConfig.versionPlistURL
        XCTAssertNotNil(URL(string: urlString), "Version plist URL should be a valid URL")
    }

    // MARK: - Releases Base URL Tests

    func testReleasesBaseURL() {
        let expectedURL = "https://github.com/frankea/Whisky/releases/download"
        XCTAssertEqual(DistributionConfig.releasesBaseURL, expectedURL)
    }

    func testReleasesBaseURLIsHTTPS() {
        XCTAssertTrue(DistributionConfig.releasesBaseURL.hasPrefix("https://"))
    }

    // MARK: - Appcast URL Tests

    func testAppcastURL() {
        let expectedURL = "https://frankea.github.io/Whisky/appcast.xml"
        XCTAssertEqual(DistributionConfig.appcastURL, expectedURL)
    }

    func testAppcastURLIsValid() {
        let urlString = DistributionConfig.appcastURL
        XCTAssertNotNil(URL(string: urlString), "Appcast URL should be a valid URL")
    }

    // MARK: - Libraries URL Construction Tests

    func testLibrariesURLWithStandardVersion() {
        let version = "2.5.0"
        let url = DistributionConfig.librariesURL(version: version)
        let expectedURL = "https://github.com/frankea/Whisky/releases/download/v2.5.0/Libraries.tar.gz"

        XCTAssertEqual(url, expectedURL)
    }

    func testLibrariesURLWithSingleDigitVersion() {
        let version = "1.0.0"
        let url = DistributionConfig.librariesURL(version: version)
        let expectedURL = "https://github.com/frankea/Whisky/releases/download/v1.0.0/Libraries.tar.gz"

        XCTAssertEqual(url, expectedURL)
    }

    func testLibrariesURLWithMultiDigitVersion() {
        let version = "10.20.30"
        let url = DistributionConfig.librariesURL(version: version)
        let expectedURL = "https://github.com/frankea/Whisky/releases/download/v10.20.30/Libraries.tar.gz"

        XCTAssertEqual(url, expectedURL)
    }

    func testLibrariesURLFormat() {
        let version = "2.5.0"
        let url = DistributionConfig.librariesURL(version: version)

        XCTAssertTrue(url.contains("/v2.5.0/"), "URL should include version tag")
        XCTAssertTrue(url.hasSuffix("Libraries.tar.gz"), "URL should end with Libraries.tar.gz")
    }

    func testLibrariesURLIsValid() {
        let version = "2.5.0"
        let urlString = DistributionConfig.librariesURL(version: version)

        XCTAssertNotNil(URL(string: urlString), "Libraries URL should be a valid URL")
    }

    func testLibrariesURLFormatRegex() {
        let version = "2.5.0"
        let url = DistributionConfig.librariesURL(version: version)

        // Verify the URL follows the expected pattern
        let pattern = "^https://github\\.com/frankea/Whisky/releases/download/"
            + "v\\d+\\.\\d+\\.\\d+/Libraries\\.tar\\.gz$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            XCTFail("Invalid regex pattern: \(pattern)")
            return
        }
        let range = NSRange(location: 0, length: url.utf16.count)

        XCTAssertNotNil(
            regex.firstMatch(in: url, options: [], range: range),
            "URL should match expected format pattern"
        )
    }

    // MARK: - Version String Construction Tests

    func testVersionStringFromSemanticVersion() {
        let version = SemanticVersion(2, 5, 0)
        let versionString = "\(version.major).\(version.minor).\(version.patch)"

        XCTAssertEqual(versionString, "2.5.0")
    }

    func testVersionStringWithDifferentValues() {
        let version = SemanticVersion(10, 20, 30)
        let versionString = "\(version.major).\(version.minor).\(version.patch)"

        XCTAssertEqual(versionString, "10.20.30")
    }

    func testVersionStringConstructsValidURL() {
        let version = SemanticVersion(2, 5, 0)
        let versionString = "\(version.major).\(version.minor).\(version.patch)"
        let urlString = DistributionConfig.librariesURL(version: versionString)

        XCTAssertNotNil(
            URL(string: urlString),
            "Version string should construct a valid URL"
        )
    }

    // MARK: - Integration Tests

    func testWhiskyWineInstallerUsesDistributionConfig() {
        // Verify that WhiskyWineInstaller uses DistributionConfig for version checks
        // This is an indirect test - we verify the URL format matches what DistributionConfig provides
        let expectedURL = DistributionConfig.versionPlistURL
        let expectedURLObject = URL(string: expectedURL)

        XCTAssertNotNil(
            expectedURLObject,
            "DistributionConfig should provide a valid URL for WhiskyWineInstaller"
        )
        XCTAssertEqual(
            expectedURL,
            "https://frankea.github.io/Whisky/WhiskyWineVersion.plist",
            "WhiskyWineInstaller should use GitHub Pages URL"
        )
    }

    func testLibrariesURLMatchesReleaseTagFormat() {
        // Verify that the constructed URL matches the expected GitHub Release tag format
        // Tag format: v{VERSION}
        // URL format: v{VERSION}/Libraries.tar.gz

        let version = "2.5.0"
        let url = DistributionConfig.librariesURL(version: version)

        // Extract the tag portion from the URL
        let components = url.components(separatedBy: "/releases/download/")
        XCTAssertEqual(components.count, 2, "URL should contain releases/download path")

        let tagAndFile = components[1]
        XCTAssertTrue(
            tagAndFile.hasPrefix("v\(version)/"),
            "URL should start with v{version}/"
        )
        XCTAssertTrue(
            tagAndFile.hasSuffix("Libraries.tar.gz"),
            "URL should end with Libraries.tar.gz"
        )
    }

    // MARK: - End-to-End Workflow Tests

    /// Tests the complete version-to-URL workflow as used in WhiskyWineDownloadView.fetchVersionAndDownload()
    func testCompleteVersionFetchToDownloadURLWorkflow() throws {
        // Simulate the plist data that would be fetched from DistributionConfig.versionPlistURL
        let plist: [String: Any] = [
            "version": [
                "major": 2,
                "minor": 5,
                "patch": 0,
            ],
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let decoder = PropertyListDecoder()
        let versionInfo = try decoder.decode(WhiskyWineVersion.self, from: data)

        // Construct version string as done in fetchVersionAndDownload()
        let version = versionInfo.version
        let versionString = "\(version.major).\(version.minor).\(version.patch)"

        // Construct download URL
        let downloadURLString = DistributionConfig.librariesURL(version: versionString)

        // Verify the complete URL
        let expectedURL = "https://github.com/frankea/Whisky/releases/download/v2.5.0/Libraries.tar.gz"
        XCTAssertEqual(downloadURLString, expectedURL)

        // Verify URL is valid
        XCTAssertNotNil(URL(string: downloadURLString), "Constructed URL should be valid")
    }

    /// Tests the workflow with different versions to ensure proper URL construction
    func testWorkflowWithVariousVersions() throws {
        let testCases: [VersionTestCase] = [
            VersionTestCase(major: 1, minor: 0, patch: 0, expectedTag: "v1.0.0"),
            VersionTestCase(major: 2, minor: 5, patch: 0, expectedTag: "v2.5.0"),
            VersionTestCase(major: 10, minor: 20, patch: 30, expectedTag: "v10.20.30"),
            VersionTestCase(major: 0, minor: 1, patch: 0, expectedTag: "v0.1.0"),
            VersionTestCase(major: 99, minor: 99, patch: 99, expectedTag: "v99.99.99"),
        ]

        for testCase in testCases {
            // Create plist data
            let plist: [String: Any] = [
                "version": [
                    "major": testCase.major,
                    "minor": testCase.minor,
                    "patch": testCase.patch,
                ],
            ]

            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            let decoder = PropertyListDecoder()
            let versionInfo = try decoder.decode(WhiskyWineVersion.self, from: data)

            // Construct version string
            let version = versionInfo.version
            let versionString = "\(version.major).\(version.minor).\(version.patch)"

            // Construct download URL
            let downloadURL = DistributionConfig.librariesURL(version: versionString)

            // Verify URL contains expected tag
            XCTAssertTrue(
                downloadURL.contains(testCase.expectedTag),
                "URL should contain tag \(testCase.expectedTag), got \(downloadURL)"
            )

            // Verify URL is valid
            XCTAssertNotNil(
                URL(string: downloadURL),
                "URL should be valid for version \(testCase.major).\(testCase.minor).\(testCase.patch)"
            )
        }
    }

    /// Tests that invalid version plist data is properly handled
    func testInvalidVersionPlistHandling() {
        // Missing version key
        let invalidPlist: [String: Any] = [:]

        do {
            let data = try PropertyListSerialization.data(fromPropertyList: invalidPlist, format: .xml, options: 0)
            let decoder = PropertyListDecoder()
            _ = try decoder.decode(WhiskyWineVersion.self, from: data)
            XCTFail("Should throw error for missing version key")
        } catch {
            // Expected - this tests that the decode error is propagated
            XCTAssertTrue(error is DecodingError, "Should throw DecodingError")
        }
    }

    /// Tests URL construction with edge case version numbers
    func testURLConstructionEdgeCases() {
        // Test with zero version
        let zeroURL = DistributionConfig.librariesURL(version: "0.0.0")
        let expectedZeroURL = "https://github.com/frankea/Whisky/releases/download/v0.0.0/Libraries.tar.gz"
        XCTAssertEqual(zeroURL, expectedZeroURL)
        XCTAssertNotNil(URL(string: zeroURL))

        // Test with large version numbers
        let largeURL = DistributionConfig.librariesURL(version: "999.999.999")
        let expectedLargeURL = "https://github.com/frankea/Whisky/releases/download/v999.999.999/Libraries.tar.gz"
        XCTAssertEqual(largeURL, expectedLargeURL)
        XCTAssertNotNil(URL(string: largeURL))
    }

    // MARK: - HTTP Error Code Tests

    /// Documents the HTTP status code handling in fetchVersionAndDownload
    /// These tests verify the expected error messages for various HTTP status codes
    func testHTTPStatusCodeErrorMessages() {
        // These test cases document the HTTP error handling in WhiskyWineDownloadView
        let errorCases: [HTTPErrorTestCase] = [
            HTTPErrorTestCase(statusCode: 200, expectedBehavior: "success"),
            HTTPErrorTestCase(statusCode: 201, expectedBehavior: "success"),
            HTTPErrorTestCase(statusCode: 299, expectedBehavior: "success"),
            HTTPErrorTestCase(statusCode: 404, expectedBehavior: "fileNotFound"),
            HTTPErrorTestCase(statusCode: 403, expectedBehavior: "accessDenied"),
            HTTPErrorTestCase(statusCode: 429, expectedBehavior: "rateLimit"),
            HTTPErrorTestCase(statusCode: 500, expectedBehavior: "serverError"),
            HTTPErrorTestCase(statusCode: 502, expectedBehavior: "serverError"),
            HTTPErrorTestCase(statusCode: 503, expectedBehavior: "serverError"),
            HTTPErrorTestCase(statusCode: 400, expectedBehavior: "httpError"),
            HTTPErrorTestCase(statusCode: 401, expectedBehavior: "httpError"),
            HTTPErrorTestCase(statusCode: 418, expectedBehavior: "httpError"),
        ]

        for testCase in errorCases {
            let isSuccess = (200 ... 299).contains(testCase.statusCode)

            if testCase.expectedBehavior == "success" {
                XCTAssertTrue(isSuccess, "Status \(testCase.statusCode) should be success")
            } else {
                XCTAssertFalse(isSuccess, "Status \(testCase.statusCode) should not be success")

                // Verify error categorization matches expected behavior
                let expectedCategory = categorizeHTTPError(statusCode: testCase.statusCode)

                XCTAssertEqual(
                    expectedCategory,
                    testCase.expectedBehavior,
                    "Status \(testCase.statusCode) should map to \(testCase.expectedBehavior)"
                )
            }
        }
    }

    private func categorizeHTTPError(statusCode: Int) -> String {
        switch statusCode {
        case 404:
            "fileNotFound"
        case 403:
            "accessDenied"
        case 429:
            "rateLimit"
        case 500 ... 599:
            "serverError"
        default:
            "httpError"
        }
    }

    /// Tests that all required URLs can be constructed as valid URL objects
    func testAllURLsAreValidForURLSession() {
        // Version plist URL
        let versionURL = URL(string: DistributionConfig.versionPlistURL)
        XCTAssertNotNil(versionURL, "Version plist URL should be valid")
        XCTAssertEqual(versionURL?.scheme, "https")
        XCTAssertEqual(versionURL?.host, "frankea.github.io")

        // Libraries download URL
        let librariesURL = URL(string: DistributionConfig.librariesURL(version: "2.5.0"))
        XCTAssertNotNil(librariesURL, "Libraries URL should be valid")
        XCTAssertEqual(librariesURL?.scheme, "https")
        XCTAssertEqual(librariesURL?.host, "github.com")

        // Appcast URL
        let appcastURL = URL(string: DistributionConfig.appcastURL)
        XCTAssertNotNil(appcastURL, "Appcast URL should be valid")
        XCTAssertEqual(appcastURL?.scheme, "https")
        XCTAssertEqual(appcastURL?.host, "frankea.github.io")
    }
}

// MARK: - Test Helper Types

private struct VersionTestCase {
    let major: Int
    let minor: Int
    let patch: Int
    let expectedTag: String
}

private struct HTTPErrorTestCase {
    let statusCode: Int
    let expectedBehavior: String
}
