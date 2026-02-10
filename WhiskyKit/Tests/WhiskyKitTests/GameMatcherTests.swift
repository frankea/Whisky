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

    // MARK: - GameMatcher Tests

    /// Helper to load entries once for matcher tests.
    private func loadTestEntries() -> [GameDBEntry] {
        GameDBLoader.loadDefaults()
    }

    // MARK: - Test 4: Match Steam App ID Hard Identifier

    func testMatchSteamAppIdHardIdentifier() {
        let entries = loadTestEntries()
        let metadata = ProgramMetadata(
            exeName: "eldenring.exe",
            steamAppId: 1245620
        )

        let results = GameMatcher.match(metadata: metadata, against: entries)
        XCTAssertFalse(results.isEmpty, "Should find at least one match")

        let top = results[0]
        XCTAssertEqual(top.entry.id, "elden-ring")
        XCTAssertGreaterThanOrEqual(top.confidence, 0.95)
        XCTAssertEqual(top.tier, .hardIdentifier)
        XCTAssertTrue(
            top.explanation.lowercased().contains("steam app id"),
            "Explanation should mention Steam App ID"
        )
    }

    // MARK: - Test 5: Match Exe Name Strong Heuristic

    func testMatchExeNameStrongHeuristic() {
        let entries = loadTestEntries()
        let metadata = ProgramMetadata(
            exeName: "eldenring.exe"
            // No steamAppId -- forces heuristic matching
        )

        let results = GameMatcher.match(metadata: metadata, against: entries)
        XCTAssertFalse(results.isEmpty, "Should find at least one match")

        let top = results[0]
        XCTAssertEqual(top.entry.id, "elden-ring")
        XCTAssertGreaterThanOrEqual(top.confidence, 0.8)
        XCTAssertLessThanOrEqual(top.confidence, 0.9)
        XCTAssertEqual(top.tier, .strongHeuristic)
    }

    // MARK: - Test 6: Match Generic Exe Penalized

    func testMatchGenericExePenalized() {
        // Create a test entry that uses a generic exe name
        let testEntry = GameDBEntry(
            id: "test-generic-game",
            title: "Test Generic Game",
            rating: .playable,
            exeNames: ["launcher.exe"],
            variants: [
                GameConfigVariant(
                    id: "default",
                    label: "Default",
                    isDefault: true,
                    settings: GameConfigVariantSettings()
                )
            ]
        )

        let metadata = ProgramMetadata(exeName: "launcher.exe")
        let results = GameMatcher.match(metadata: metadata, against: [testEntry])

        // Generic exe should be penalized: 0.85 - 0.3 = 0.55, which is below strong heuristic
        // It may not appear at all if penalty brings it below threshold, or have a low score
        if let top = results.first {
            XCTAssertLessThan(
                top.confidence, 0.7,
                "Generic exe name should be penalized below strong heuristic threshold"
            )
            XCTAssertTrue(
                top.explanation.contains("generic") || top.explanation.contains("penalty"),
                "Explanation should note the generic penalty"
            )
        }
        // It's also valid if no results come back (score below 0.3 threshold)
    }

    // MARK: - Test 7: Match Fuzzy Token Match

    func testMatchFuzzyTokenMatch() {
        // Create entries with specific titles for fuzzy matching
        let testEntry = GameDBEntry(
            id: "elden-ring-test",
            title: "Elden Ring",
            aliases: ["ELDEN RING"],
            rating: .playable,
            variants: [
                GameConfigVariant(
                    id: "default",
                    label: "Default",
                    isDefault: true,
                    settings: GameConfigVariantSettings()
                )
            ]
        )

        // Use an exe name that contains partial title tokens
        let metadata = ProgramMetadata(exeName: "elden_ring_launcher.exe")
        let results = GameMatcher.match(metadata: metadata, against: [testEntry])

        XCTAssertFalse(results.isEmpty, "Fuzzy matching should find a result")

        let top = results[0]
        XCTAssertGreaterThanOrEqual(top.confidence, 0.3)
        XCTAssertLessThanOrEqual(top.confidence, 0.6)
        XCTAssertEqual(top.tier, .fuzzy)
    }

    // MARK: - Test 8: Match Below Threshold Filtered

    func testMatchBelowThresholdFiltered() {
        let entries = loadTestEntries()
        // Use a name that shares zero tokens with any game title or alias
        let metadata = ProgramMetadata(exeName: "qzxwvjkl.exe")

        let results = GameMatcher.match(metadata: metadata, against: entries)
        XCTAssertTrue(results.isEmpty, "Non-matching metadata should return empty results")
    }

    // MARK: - Test 9: Best Match Returns Nil For Close Scores

    func testBestMatchReturnsNilForCloseScores() {
        // Create two entries with the same exe name -- produces close scores
        let entry1 = GameDBEntry(
            id: "game-a",
            title: "Game A",
            rating: .playable,
            exeNames: ["shared.exe"],
            variants: [
                GameConfigVariant(
                    id: "default",
                    label: "Default",
                    isDefault: true,
                    settings: GameConfigVariantSettings()
                )
            ]
        )
        let entry2 = GameDBEntry(
            id: "game-b",
            title: "Game B",
            rating: .playable,
            exeNames: ["shared.exe"],
            variants: [
                GameConfigVariant(
                    id: "default",
                    label: "Default",
                    isDefault: true,
                    settings: GameConfigVariantSettings()
                )
            ]
        )

        let metadata = ProgramMetadata(exeName: "shared.exe")
        let best = GameMatcher.bestMatch(metadata: metadata, against: [entry1, entry2])

        XCTAssertNil(best, "bestMatch should return nil when top-2 scores are close (ambiguous)")
    }

    // MARK: - Test 10: Best Match Returns Top For Clear Winner

    func testBestMatchReturnsTopForClearWinner() {
        let entries = loadTestEntries()

        // Steam App ID gives a clear 1.0 score -- unambiguous
        let metadata = ProgramMetadata(
            exeName: "eldenring.exe",
            steamAppId: 1245620
        )

        let best = GameMatcher.bestMatch(metadata: metadata, against: entries)
        XCTAssertNotNil(best, "bestMatch should return the clear winner")
        XCTAssertEqual(best?.entry.id, "elden-ring")
        XCTAssertGreaterThanOrEqual(best?.confidence ?? 0, 0.95)
    }

    // MARK: - Test 11: Search Entries By Title

    func testSearchEntriesByTitle() {
        let entries = loadTestEntries()
        let results = GameMatcher.searchEntries("elden ring", in: entries)

        XCTAssertFalse(results.isEmpty, "Should find Elden Ring by title")
        XCTAssertTrue(
            results.contains { $0.id == "elden-ring" },
            "Results should contain elden-ring entry"
        )
    }

    // MARK: - Test 12: Search Entries By Alias

    func testSearchEntriesByAlias() {
        let entries = loadTestEntries()

        // "TW3" is an alias for The Witcher 3
        let results = GameMatcher.searchEntries("TW3", in: entries)
        XCTAssertFalse(results.isEmpty, "Should find The Witcher 3 by alias TW3")
        XCTAssertTrue(
            results.contains { $0.id == "the-witcher-3" },
            "Results should contain the-witcher-3 entry"
        )
    }

    // MARK: - Test 13: Search Entries Case Insensitive

    func testSearchEntriesCaseInsensitive() {
        let entries = loadTestEntries()

        let upper = GameMatcher.searchEntries("ELDEN RING", in: entries)
        let lower = GameMatcher.searchEntries("elden ring", in: entries)
        let mixed = GameMatcher.searchEntries("Elden Ring", in: entries)

        XCTAssertFalse(upper.isEmpty, "Uppercase search should find results")
        XCTAssertFalse(lower.isEmpty, "Lowercase search should find results")
        XCTAssertFalse(mixed.isEmpty, "Mixed-case search should find results")

        // All three should find the same entries
        let upperIds = Set(upper.map(\.id))
        let lowerIds = Set(lower.map(\.id))
        let mixedIds = Set(mixed.map(\.id))

        XCTAssertEqual(upperIds, lowerIds, "Case should not affect search results")
        XCTAssertEqual(lowerIds, mixedIds, "Case should not affect search results")
    }
}
