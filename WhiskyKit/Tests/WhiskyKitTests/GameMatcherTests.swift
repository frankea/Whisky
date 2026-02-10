// swiftlint:disable file_length
//
//  GameMatcherTests.swift
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

// MARK: - GameDBLoader Tests

final class GameMatcherTests: XCTestCase {
    // MARK: - Test 1: GameDBLoader Loads Defaults

    func testGameDBLoaderLoadsDefaults() {
        let entries = GameDBLoader.loadDefaults()
        XCTAssertFalse(entries.isEmpty, "loadDefaults() should return a non-empty array")

        // Verify first entry has an expected ID (stardew-valley is first in the seed file)
        XCTAssertEqual(entries.first?.id, "stardew-valley")
    }

    // MARK: - Test 2: GameDBLoader Decodes All Fields

    func testGameDBLoaderDecodesAllFields() {
        let entries = GameDBLoader.loadDefaults()
        XCTAssertFalse(entries.isEmpty)

        // Find an entry with complete fields (Elden Ring has most fields populated)
        let eldenRing = entries.first { $0.id == "elden-ring" }
        XCTAssertNotNil(eldenRing, "Expected to find elden-ring entry")

        guard let entry = eldenRing else { return }

        // Required fields
        XCTAssertEqual(entry.id, "elden-ring")
        XCTAssertEqual(entry.title, "Elden Ring")
        XCTAssertEqual(entry.rating, .playable)
        XCTAssertFalse(entry.variants.isEmpty)

        // Optional but populated fields
        XCTAssertNotNil(entry.aliases)
        XCTAssertNotNil(entry.store)
        XCTAssertNotNil(entry.steamAppId)
        XCTAssertEqual(entry.steamAppId, 1245620)
        XCTAssertNotNil(entry.exeNames)
        XCTAssertNotNil(entry.pathPatterns)
        XCTAssertNotNil(entry.notes)
        XCTAssertNotNil(entry.knownIssues)
        XCTAssertNotNil(entry.provenance)

        // Variant fields
        let variant = entry.variants[0]
        XCTAssertEqual(variant.id, "recommended-apple-silicon")
        XCTAssertEqual(variant.isDefault, true)
        XCTAssertNotNil(variant.settings.graphicsBackend)
        XCTAssertNotNil(variant.testedWith)
    }

    // MARK: - Test 3: GameDBLoader Date Decoding

    func testGameDBLoaderDateDecoding() {
        let entries = GameDBLoader.loadDefaults()
        XCTAssertFalse(entries.isEmpty)

        // Find an entry with testedWith dates
        let entry = entries.first { $0.variants.first?.testedWith != nil }
        XCTAssertNotNil(entry, "Expected at least one entry with testedWith data")

        guard let testedWith = entry?.variants.first?.testedWith else { return }

        // Verify the date decoded correctly from ISO 8601
        // Dates should be valid (not epoch zero)
        XCTAssertGreaterThan(
            testedWith.lastTestedAt.timeIntervalSince1970,
            0,
            "Date should decode from ISO 8601, not be epoch zero"
        )

        // Verify dates are in a reasonable range (after 2024)
        let calendar = Calendar.current
        let year = calendar.component(.year, from: testedWith.lastTestedAt)
        XCTAssertGreaterThanOrEqual(year, 2024, "Tested date should be from 2024 or later")

        // Also verify provenance date if present
        if let provLastUpdated = entry?.provenance?.lastUpdated {
            XCTAssertGreaterThan(
                provLastUpdated.timeIntervalSince1970,
                0,
                "Provenance lastUpdated should decode correctly"
            )
        }
    }
}

// swiftlint:enable file_length
