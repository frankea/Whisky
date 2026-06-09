//
//  WhiskyWineVersionTests.swift
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

// MARK: - Decoding Tests

final class WhiskyWineVersionDecodingTests: XCTestCase {
    func testDecodeValidPlist() throws {
        let plist: [String: Any] = [
            "version": ["major": 2, "minor": 5, "patch": 0]
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let versionInfo = try PropertyListDecoder().decode(WhiskyWineVersion.self, from: data)

        XCTAssertEqual(versionInfo.version.major, 2)
        XCTAssertEqual(versionInfo.version.minor, 5)
        XCTAssertEqual(versionInfo.version.patch, 0)
        XCTAssertEqual(versionInfo.version, SemanticVersion(2, 5, 0))
    }

    func testDecodeWithDifferentVersions() throws {
        let testCases: [VersionComponents] = [
            VersionComponents(major: 1, minor: 0, patch: 0),
            VersionComponents(major: 2, minor: 5, patch: 0),
            VersionComponents(major: 10, minor: 20, patch: 30),
            VersionComponents(major: 0, minor: 0, patch: 1),
            VersionComponents(major: 99, minor: 99, patch: 99)
        ]

        for testCase in testCases {
            let plist: [String: Any] = [
                "version": [
                    "major": testCase.major,
                    "minor": testCase.minor,
                    "patch": testCase.patch
                ]
            ]

            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            let versionInfo = try PropertyListDecoder().decode(WhiskyWineVersion.self, from: data)

            XCTAssertEqual(versionInfo.version.major, testCase.major)
            XCTAssertEqual(versionInfo.version.minor, testCase.minor)
            XCTAssertEqual(versionInfo.version.patch, testCase.patch)
            XCTAssertEqual(
                versionInfo.version,
                SemanticVersion(testCase.major, testCase.minor, testCase.patch)
            )
        }
    }
}

// MARK: - Encoding Tests

final class WhiskyWineVersionEncodingTests: XCTestCase {
    func testEncodeToPlist() throws {
        let versionInfo = WhiskyWineVersion(version: SemanticVersion(2, 5, 0))

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(versionInfo)

        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]

        XCTAssertNotNil(plist, "Encoded plist should be valid")
        guard let plist else { return }

        XCTAssertNotNil(plist["version"] as? [String: Any], "Version dictionary should exist")
        guard let versionDict = plist["version"] as? [String: Any] else { return }

        XCTAssertEqual(versionDict["major"] as? Int, 2)
        XCTAssertEqual(versionDict["minor"] as? Int, 5)
        XCTAssertEqual(versionDict["patch"] as? Int, 0)
    }

    func testEncodeWithDifferentVersions() throws {
        let testCases: [SemanticVersion] = [
            SemanticVersion(1, 0, 0),
            SemanticVersion(2, 5, 0),
            SemanticVersion(10, 20, 30),
            SemanticVersion(0, 0, 1),
            SemanticVersion(99, 99, 99)
        ]

        for version in testCases {
            let versionInfo = WhiskyWineVersion(version: version)

            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            let data = try encoder.encode(versionInfo)

            let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            XCTAssertNotNil(plist, "Encoded plist should be valid")

            guard let plist,
                  let versionDict = plist["version"] as? [String: Any]
            else {
                XCTFail("Failed to decode encoded plist")
                continue
            }

            XCTAssertEqual(versionDict["major"] as? Int, version.major)
            XCTAssertEqual(versionDict["minor"] as? Int, version.minor)
            XCTAssertEqual(versionDict["patch"] as? Int, version.patch)
        }
    }
}

// MARK: - Round-Trip Tests

final class WhiskyWineVersionRoundTripTests: XCTestCase {
    func testRoundTripEncodingDecoding() throws {
        let originalVersion = SemanticVersion(2, 5, 0)
        let original = WhiskyWineVersion(version: originalVersion)

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(original)

        let decoded = try PropertyListDecoder().decode(WhiskyWineVersion.self, from: data)

        XCTAssertEqual(decoded.version, originalVersion)
        XCTAssertEqual(decoded.version.major, 2)
        XCTAssertEqual(decoded.version.minor, 5)
        XCTAssertEqual(decoded.version.patch, 0)
    }

    func testRoundTripWithMultipleVersions() throws {
        let testVersions: [SemanticVersion] = [
            SemanticVersion(1, 0, 0),
            SemanticVersion(2, 5, 0),
            SemanticVersion(10, 20, 30),
            SemanticVersion(0, 0, 1)
        ]

        for version in testVersions {
            let original = WhiskyWineVersion(version: version)

            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            let data = try encoder.encode(original)

            let decoded = try PropertyListDecoder().decode(WhiskyWineVersion.self, from: data)

            XCTAssertEqual(decoded.version, version, "Round-trip should preserve version \(version)")
            XCTAssertEqual(decoded.version.major, version.major)
            XCTAssertEqual(decoded.version.minor, version.minor)
            XCTAssertEqual(decoded.version.patch, version.patch)
        }
    }
}

// MARK: - Error Handling Tests

final class WhiskyWineVersionErrorTests: XCTestCase {
    func testDecodeMissingVersionKey() {
        let plist: [String: Any] = [:]
        assertDecodingError(for: plist)
    }

    func testDecodeMissingMajorKey() {
        let plist: [String: Any] = ["version": ["minor": 5, "patch": 0]]
        assertDecodingError(for: plist)
    }

    func testDecodeMissingMinorKey() {
        let plist: [String: Any] = ["version": ["major": 2, "patch": 0]]
        assertDecodingError(for: plist)
    }

    func testDecodeMissingPatchKey() {
        let plist: [String: Any] = ["version": ["major": 2, "minor": 5]]
        assertDecodingError(for: plist)
    }

    func testDecodeInvalidVersionType() {
        let plist: [String: Any] = ["version": "invalid"]
        assertDecodingError(for: plist)
    }

    func testDecodeInvalidMajorType() {
        let plist: [String: Any] = ["version": ["major": "invalid", "minor": 5, "patch": 0]]
        assertDecodingError(for: plist)
    }

    func testDecodeInvalidMinorType() {
        let plist: [String: Any] = ["version": ["major": 2, "minor": "invalid", "patch": 0]]
        assertDecodingError(for: plist)
    }

    func testDecodeInvalidPatchType() {
        let plist: [String: Any] = ["version": ["major": 2, "minor": 5, "patch": "invalid"]]
        assertDecodingError(for: plist)
    }

    func testDecodeInvalidPlistData() {
        let invalidData = Data("invalid plist data".utf8)

        do {
            _ = try PropertyListDecoder().decode(WhiskyWineVersion.self, from: invalidData)
            XCTFail("Should throw error when plist data is invalid")
        } catch {
            XCTAssertNotNil(error, "Should throw error for invalid plist data")
        }
    }

    private func assertDecodingError(for plist: [String: Any], file: StaticString = #filePath, line: UInt = #line) {
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            _ = try PropertyListDecoder().decode(WhiskyWineVersion.self, from: data)
            XCTFail("Should throw DecodingError", file: file, line: line)
        } catch {
            XCTAssertTrue(error is DecodingError, "Should throw DecodingError", file: file, line: line)
        }
    }
}

// MARK: - Initializer Tests

final class WhiskyWineVersionInitializerTests: XCTestCase {
    func testInitializer() {
        let version = SemanticVersion(2, 5, 0)
        let versionInfo = WhiskyWineVersion(version: version)

        XCTAssertEqual(versionInfo.version, version)
        XCTAssertEqual(versionInfo.version.major, 2)
        XCTAssertEqual(versionInfo.version.minor, 5)
        XCTAssertEqual(versionInfo.version.patch, 0)
    }

    func testMemberwiseInitializer() {
        let version1 = SemanticVersion(1, 0, 0)
        let version2 = SemanticVersion(2, 5, 0)

        let info1 = WhiskyWineVersion(version: version1)
        let info2 = WhiskyWineVersion(version: version2)

        XCTAssertEqual(info1.version, version1)
        XCTAssertEqual(info2.version, version2)
        XCTAssertNotEqual(info1.version, info2.version)
    }
}

// MARK: - DXVK Version Tests

final class WhiskyWineVersionDXVKTests: XCTestCase {
    func testDecodeWithDXVKVersion() throws {
        let plist: [String: Any] = [
            "version": ["major": 3, "minor": 0, "patch": 0],
            "dxvkVersion": "1.10.3"
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let versionInfo = try PropertyListDecoder().decode(WhiskyWineVersion.self, from: data)

        XCTAssertEqual(versionInfo.version, SemanticVersion(3, 0, 0))
        XCTAssertEqual(versionInfo.dxvkVersion, "1.10.3")
    }

    func testDecodeWithoutDXVKVersionIsNil() throws {
        // Older runtime plists predate the dxvkVersion key and must still decode.
        let plist: [String: Any] = [
            "version": ["major": 3, "minor": 0, "patch": 0]
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let versionInfo = try PropertyListDecoder().decode(WhiskyWineVersion.self, from: data)

        XCTAssertNil(versionInfo.dxvkVersion)
    }

    func testRoundTripPreservesDXVKVersion() throws {
        let original = WhiskyWineVersion(version: SemanticVersion(3, 0, 0), dxvkVersion: "1.10.3")

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(original)
        let decoded = try PropertyListDecoder().decode(WhiskyWineVersion.self, from: data)

        XCTAssertEqual(decoded.version, original.version)
        XCTAssertEqual(decoded.dxvkVersion, "1.10.3")
    }

    func testNilDXVKVersionIsOmittedFromEncoding() throws {
        let original = WhiskyWineVersion(version: SemanticVersion(3, 0, 0))

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(original)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]

        XCTAssertNotNil(plist)
        XCTAssertNil(plist?["dxvkVersion"], "A nil DXVK version should not be written to the plist")
    }
}

// MARK: - SHA-256 Tests

final class WhiskyWineVersionSHA256Tests: XCTestCase {
    private let sampleHash = "9c3d2a7d9bb682ae8398d8bae458e3cb52bb9f5a3345fb0830a64d9b6a1025f8"

    func testDecodeWithSHA256() throws {
        let plist: [String: Any] = [
            "version": ["major": 3, "minor": 0, "patch": 0],
            "sha256": sampleHash
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let versionInfo = try PropertyListDecoder().decode(WhiskyWineVersion.self, from: data)

        XCTAssertEqual(versionInfo.version, SemanticVersion(3, 0, 0))
        XCTAssertEqual(versionInfo.sha256, sampleHash)
    }

    func testDecodeWithoutSHA256IsNil() throws {
        // Older runtime plists predate the sha256 key and must still decode.
        let plist: [String: Any] = [
            "version": ["major": 3, "minor": 0, "patch": 0]
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let versionInfo = try PropertyListDecoder().decode(WhiskyWineVersion.self, from: data)

        XCTAssertNil(versionInfo.sha256)
    }

    func testEmptySHA256NormalizesToNil() throws {
        // A blank string must collapse to nil so verification is skipped rather
        // than failing every download against an impossible empty digest.
        let plist: [String: Any] = [
            "version": ["major": 3, "minor": 0, "patch": 0],
            "sha256": ""
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let versionInfo = try PropertyListDecoder().decode(WhiskyWineVersion.self, from: data)

        XCTAssertNil(versionInfo.sha256)
    }

    func testRoundTripPreservesSHA256() throws {
        let original = WhiskyWineVersion(
            version: SemanticVersion(3, 0, 0),
            dxvkVersion: "1.10.3",
            sha256: sampleHash
        )

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(original)
        let decoded = try PropertyListDecoder().decode(WhiskyWineVersion.self, from: data)

        XCTAssertEqual(decoded.version, original.version)
        XCTAssertEqual(decoded.dxvkVersion, "1.10.3")
        XCTAssertEqual(decoded.sha256, sampleHash)
    }

    func testNilSHA256IsOmittedFromEncoding() throws {
        let original = WhiskyWineVersion(version: SemanticVersion(3, 0, 0))

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(original)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]

        XCTAssertNotNil(plist)
        XCTAssertNil(plist?["sha256"], "A nil SHA-256 should not be written to the plist")
    }
}

// MARK: - Test Helper Types

private struct VersionComponents {
    let major: Int
    let minor: Int
    let patch: Int
}
