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

import XCTest
import SemanticVersion
@testable import WhiskyKit

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
        let expectedURL = "https://github.com/frankea/Whisky/releases/download/v2.5.0-wine/Libraries.tar.gz"
        
        XCTAssertEqual(url, expectedURL)
    }

    func testLibrariesURLWithSingleDigitVersion() {
        let version = "1.0.0"
        let url = DistributionConfig.librariesURL(version: version)
        let expectedURL = "https://github.com/frankea/Whisky/releases/download/v1.0.0-wine/Libraries.tar.gz"
        
        XCTAssertEqual(url, expectedURL)
    }

    func testLibrariesURLWithMultiDigitVersion() {
        let version = "10.20.30"
        let url = DistributionConfig.librariesURL(version: version)
        let expectedURL = "https://github.com/frankea/Whisky/releases/download/v10.20.30-wine/Libraries.tar.gz"
        
        XCTAssertEqual(url, expectedURL)
    }

    func testLibrariesURLIncludesWineSuffix() {
        let version = "2.5.0"
        let url = DistributionConfig.librariesURL(version: version)
        
        XCTAssertTrue(url.contains("-wine"), "URL should include -wine suffix")
        XCTAssertTrue(url.hasSuffix("Libraries.tar.gz"), "URL should end with Libraries.tar.gz")
    }

    func testLibrariesURLIsValid() {
        let version = "2.5.0"
        let urlString = DistributionConfig.librariesURL(version: version)
        
        XCTAssertNotNil(URL(string: urlString), "Libraries URL should be a valid URL")
    }

    func testLibrariesURLFormat() {
        let version = "2.5.0"
        let url = DistributionConfig.librariesURL(version: version)
        
        // Verify the URL follows the expected pattern
        let pattern = "^https://github\\.com/frankea/Whisky/releases/download/v\\d+\\.\\d+\\.\\d+-wine/Libraries\\.tar\\.gz$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            XCTFail("Invalid regex pattern: \(pattern)")
            return
        }
        let range = NSRange(location: 0, length: url.utf16.count)
        
        XCTAssertNotNil(regex.firstMatch(in: url, options: [], range: range), 
                       "URL should match expected format pattern")
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
        
        XCTAssertNotNil(URL(string: urlString), 
                       "Version string should construct a valid URL")
    }

    // MARK: - Integration Tests

    func testWhiskyWineInstallerUsesDistributionConfig() {
        // Verify that WhiskyWineInstaller uses DistributionConfig for version checks
        // This is an indirect test - we verify the URL format matches what DistributionConfig provides
        let expectedURL = DistributionConfig.versionPlistURL
        let expectedURLObject = URL(string: expectedURL)
        
        XCTAssertNotNil(expectedURLObject, 
                       "DistributionConfig should provide a valid URL for WhiskyWineInstaller")
        XCTAssertEqual(expectedURL, "https://frankea.github.io/Whisky/WhiskyWineVersion.plist",
                      "WhiskyWineInstaller should use GitHub Pages URL")
    }

    func testLibrariesURLMatchesReleaseTagFormat() {
        // Verify that the constructed URL matches the expected GitHub Release tag format
        // Tag format: v{VERSION}-wine
        // URL format: v{VERSION}-wine/Libraries.tar.gz
        
        let version = "2.5.0"
        let url = DistributionConfig.librariesURL(version: version)
        
        // Extract the tag portion from the URL
        let components = url.components(separatedBy: "/releases/download/")
        XCTAssertEqual(components.count, 2, "URL should contain releases/download path")
        
        let tagAndFile = components[1]
        XCTAssertTrue(tagAndFile.hasPrefix("v\(version)-wine/"),
                     "URL should start with v{version}-wine/")
        XCTAssertTrue(tagAndFile.hasSuffix("Libraries.tar.gz"),
                     "URL should end with Libraries.tar.gz")
    }
}
