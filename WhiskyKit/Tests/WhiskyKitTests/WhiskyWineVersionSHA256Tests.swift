//
//  WhiskyWineVersionSHA256Tests.swift
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

    func testUppercaseSHA256IsLowercased() throws {
        // A digest published in uppercase is still valid; it is normalized to
        // lowercase so it compares equal to the lowercase digest the hasher emits.
        let plist: [String: Any] = [
            "version": ["major": 3, "minor": 0, "patch": 0],
            "sha256": sampleHash.uppercased()
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let versionInfo = try PropertyListDecoder().decode(WhiskyWineVersion.self, from: data)

        XCTAssertEqual(versionInfo.sha256, sampleHash)
    }

    func testWhitespaceAroundSHA256IsTrimmed() throws {
        let plist: [String: Any] = [
            "version": ["major": 3, "minor": 0, "patch": 0],
            "sha256": "  \(sampleHash)\n"
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let versionInfo = try PropertyListDecoder().decode(WhiskyWineVersion.self, from: data)

        XCTAssertEqual(versionInfo.sha256, sampleHash)
    }

    func testMalformedSHA256NormalizesToNil() throws {
        // A typo, truncated paste, or placeholder must collapse to nil so that
        // release goes unverified rather than failing every download against an
        // impossible digest.
        let malformedValues = [
            "not-a-valid-hash",
            "TODO",
            String(sampleHash.dropLast()), // 63 chars
            sampleHash + "0", // 65 chars
            "9c3d2a7d9bb682ae8398d8bae458e3cb52bb9f5a3345fb0830a64d9b6a1025fzz", // non-hex
            String(repeating: "\u{FF10}", count: 64) // 64 fullwidth digits (non-ASCII)
        ]

        for malformed in malformedValues {
            let plist: [String: Any] = [
                "version": ["major": 3, "minor": 0, "patch": 0],
                "sha256": malformed
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            let versionInfo = try PropertyListDecoder().decode(WhiskyWineVersion.self, from: data)
            XCTAssertNil(versionInfo.sha256, "Malformed digest \"\(malformed)\" should normalize to nil")
        }
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
