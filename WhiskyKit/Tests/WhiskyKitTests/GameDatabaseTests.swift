// swiftlint:disable file_length
//
//  GameDatabaseTests.swift
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

// MARK: - CompatibilityRating Tests

// swiftlint:disable:next type_body_length
final class GameDatabaseTests: XCTestCase {
    // MARK: - Test 1: CompatibilityRating Codable Round-Trip

    func testCompatibilityRatingCodableRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for rating in CompatibilityRating.allCases {
            let data = try encoder.encode(rating)
            let decoded = try decoder.decode(CompatibilityRating.self, from: data)
            XCTAssertEqual(rating, decoded, "Round-trip failed for \(rating)")
        }
    }

    // MARK: - Test 2: CompatibilityRating Comparable

    func testCompatibilityRatingComparable() {
        XCTAssertTrue(CompatibilityRating.works < .playable)
        XCTAssertTrue(CompatibilityRating.playable < .unverified)
        XCTAssertTrue(CompatibilityRating.unverified < .broken)
        XCTAssertTrue(CompatibilityRating.broken < .notSupported)

        // Transitivity
        XCTAssertTrue(CompatibilityRating.works < .notSupported)
        XCTAssertTrue(CompatibilityRating.playable < .broken)

        // Equality
        XCTAssertFalse(CompatibilityRating.works < .works)
    }

    // MARK: - Test 3: GameDBEntry Decodes from Full JSON

    // swiftlint:disable:next function_body_length
    func testGameDBEntryDecodesFromJSON() throws {
        let json = """
        {
          "id": "elden-ring",
          "title": "Elden Ring",
          "aliases": ["ELDEN RING", "eldenring"],
          "subtitle": "Bandai Namco",
          "store": "steam",
          "steamAppId": 1245620,
          "rating": "playable",
          "exeNames": ["eldenring.exe"],
          "exeFingerprints": [
            {
              "sha256": null,
              "fileSize": 78643200,
              "peTimestamp": null
            }
          ],
          "pathPatterns": ["elden ring/game"],
          "antiCheat": null,
          "constraints": {
            "cpuArchitectures": ["arm64"],
            "minMacOSVersion": "15.0.0",
            "minWineVersion": "9.0",
            "requiredBackendCapabilities": []
          },
          "variants": [
            {
              "id": "recommended-apple-silicon",
              "label": "Recommended (Apple Silicon)",
              "isDefault": true,
              "whenToUse": "Standard setup for M-series Macs",
              "rationale": ["D3DMetal provides best performance"],
              "settings": {
                "graphicsBackend": "d3dMetal",
                "dxvk": false,
                "dxvkAsync": false,
                "enhancedSync": "esync",
                "forceD3D11": false,
                "performancePreset": "balanced",
                "shaderCacheEnabled": true,
                "avxEnabled": false,
                "sequoiaCompatMode": false
              },
              "environmentVariables": {
                "D3DM_SUPPORT_DXR": "0"
              },
              "dllOverrides": [],
              "winetricksVerbs": ["vcrun2022"]
            }
          ],
          "notes": ["Easy Anti-Cheat must be disabled"],
          "knownIssues": [
            {
              "description": "Shader stutter in open world",
              "severity": "minor",
              "workaround": "Enable shader cache"
            }
          ],
          "provenance": {
            "source": "maintainer-verified",
            "author": "Whisky Team",
            "lastUpdated": null,
            "referenceURL": null
          }
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoder = JSONDecoder()
        let entry = try decoder.decode(GameDBEntry.self, from: data)

        XCTAssertEqual(entry.id, "elden-ring")
        XCTAssertEqual(entry.title, "Elden Ring")
        XCTAssertEqual(entry.aliases, ["ELDEN RING", "eldenring"])
        XCTAssertEqual(entry.subtitle, "Bandai Namco")
        XCTAssertEqual(entry.store, "steam")
        XCTAssertEqual(entry.steamAppId, 1_245_620)
        XCTAssertEqual(entry.rating, .playable)
        XCTAssertEqual(entry.exeNames, ["eldenring.exe"])
        XCTAssertEqual(entry.exeFingerprints?.count, 1)
        XCTAssertEqual(entry.exeFingerprints?.first?.fileSize, 78_643_200)
        XCTAssertEqual(entry.pathPatterns, ["elden ring/game"])
        XCTAssertNil(entry.antiCheat)
        XCTAssertEqual(entry.constraints?.cpuArchitectures, ["arm64"])
        XCTAssertEqual(entry.constraints?.minMacOSVersion, "15.0.0")
        XCTAssertEqual(entry.constraints?.minWineVersion, "9.0")
        XCTAssertEqual(entry.variants.count, 1)

        let variant = entry.variants[0]
        XCTAssertEqual(variant.id, "recommended-apple-silicon")
        XCTAssertEqual(variant.label, "Recommended (Apple Silicon)")
        XCTAssertEqual(variant.isDefault, true)
        XCTAssertEqual(variant.settings.graphicsBackend, .d3dMetal)
        XCTAssertEqual(variant.settings.dxvk, false)
        XCTAssertEqual(variant.settings.enhancedSync, .esync)
        XCTAssertEqual(variant.settings.forceD3D11, false)
        XCTAssertEqual(variant.settings.performancePreset, "balanced")
        XCTAssertEqual(variant.settings.shaderCacheEnabled, true)
        XCTAssertEqual(variant.environmentVariables?["D3DM_SUPPORT_DXR"], "0")
        XCTAssertEqual(variant.winetricksVerbs, ["vcrun2022"])

        XCTAssertEqual(entry.notes, ["Easy Anti-Cheat must be disabled"])
        XCTAssertEqual(entry.knownIssues?.count, 1)
        XCTAssertEqual(entry.knownIssues?.first?.description, "Shader stutter in open world")
        XCTAssertEqual(entry.knownIssues?.first?.severity, "minor")
        XCTAssertEqual(entry.provenance?.source, "maintainer-verified")
        XCTAssertEqual(entry.provenance?.author, "Whisky Team")
    }

    // MARK: - Test 4: GameDBEntry Defaults for Missing Optionals

    func testGameDBEntryDefaultsForMissingOptionals() throws {
        let json = """
        {
          "id": "minimal-game",
          "title": "Minimal Game",
          "rating": "unverified",
          "variants": [
            {
              "id": "default",
              "label": "Default",
              "settings": {}
            }
          ]
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let entry = try JSONDecoder().decode(GameDBEntry.self, from: data)

        XCTAssertEqual(entry.id, "minimal-game")
        XCTAssertEqual(entry.title, "Minimal Game")
        XCTAssertEqual(entry.rating, .unverified)
        XCTAssertNil(entry.aliases)
        XCTAssertNil(entry.subtitle)
        XCTAssertNil(entry.store)
        XCTAssertNil(entry.steamAppId)
        XCTAssertNil(entry.exeNames)
        XCTAssertNil(entry.exeFingerprints)
        XCTAssertNil(entry.pathPatterns)
        XCTAssertNil(entry.antiCheat)
        XCTAssertNil(entry.constraints)
        XCTAssertNil(entry.notes)
        XCTAssertNil(entry.knownIssues)
        XCTAssertNil(entry.provenance)
        XCTAssertEqual(entry.variants.count, 1)
    }

    // MARK: - Test 5: GameConfigVariantSettings Defaults to Nil

    func testGameConfigVariantSettingsDefaultsToNil() throws {
        let json = """
        {}
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let settings = try JSONDecoder().decode(GameConfigVariantSettings.self, from: data)

        XCTAssertNil(settings.graphicsBackend)
        XCTAssertNil(settings.dxvk)
        XCTAssertNil(settings.dxvkAsync)
        XCTAssertNil(settings.enhancedSync)
        XCTAssertNil(settings.forceD3D11)
        XCTAssertNil(settings.performancePreset)
        XCTAssertNil(settings.shaderCacheEnabled)
        XCTAssertNil(settings.avxEnabled)
        XCTAssertNil(settings.sequoiaCompatMode)
    }

    // MARK: - Test 6: Default Variant Returns First isDefault

    func testDefaultVariantReturnsFirstIsDefault() {
        let variant1 = GameConfigVariant(
            id: "first",
            label: "First",
            isDefault: false,
            settings: GameConfigVariantSettings()
        )
        let variant2 = GameConfigVariant(
            id: "second",
            label: "Second",
            isDefault: true,
            settings: GameConfigVariantSettings()
        )
        let variant3 = GameConfigVariant(
            id: "third",
            label: "Third",
            isDefault: true,
            settings: GameConfigVariantSettings()
        )

        let entry = GameDBEntry(
            id: "test",
            title: "Test Game",
            rating: .playable,
            variants: [variant1, variant2, variant3]
        )

        XCTAssertEqual(entry.defaultVariant?.id, "second")
    }

    // MARK: - Test 7: Default Variant Falls Back to First

    func testDefaultVariantFallsBackToFirst() {
        let variant1 = GameConfigVariant(
            id: "alpha",
            label: "Alpha",
            settings: GameConfigVariantSettings()
        )
        let variant2 = GameConfigVariant(
            id: "beta",
            label: "Beta",
            settings: GameConfigVariantSettings()
        )

        let entry = GameDBEntry(
            id: "test",
            title: "Test Game",
            rating: .works,
            variants: [variant1, variant2]
        )

        XCTAssertEqual(entry.defaultVariant?.id, "alpha")
    }

    // MARK: - Test 8: MatchTier Comparable

    func testMatchTierComparable() {
        XCTAssertTrue(MatchTier.fuzzy < .strongHeuristic)
        XCTAssertTrue(MatchTier.strongHeuristic < .hardIdentifier)
        XCTAssertTrue(MatchTier.fuzzy < .hardIdentifier)
        XCTAssertFalse(MatchTier.hardIdentifier < .hardIdentifier)
    }

    // MARK: - Test 9: SteamAppManifest Parses ACF

    func testSteamAppManifestParsesACF() {
        let acfContent = """
        "AppState"
        {
        \t"appid"\t\t"1245620"
        \t"Universe"\t\t"1"
        \t"name"\t\t"ELDEN RING"
        \t"StateFlags"\t\t"4"
        \t"installdir"\t\t"ELDEN RING"
        }
        """

        let appId = SteamAppManifest.parseAppId(from: acfContent)
        XCTAssertEqual(appId, 1_245_620)
    }

    // MARK: - Test 10: SteamAppManifest Parses AppId Txt

    func testSteamAppManifestParsesAppIdTxt() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "GameDatabaseTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a steam_appid.txt file
        let appIdFile = tempDir.appending(path: "steam_appid.txt")
        try "1245620\n".write(to: appIdFile, atomically: true, encoding: .utf8)

        // Create a fake exe path in this directory
        let exeURL = tempDir.appending(path: "game.exe")

        let appId = SteamAppManifest.findAppIdForProgram(at: exeURL)
        XCTAssertEqual(appId, 1_245_620)
    }

    // MARK: - Additional ACF Parsing Edge Cases

    func testSteamAppManifestParsesACFWithSpaces() {
        let acfContent = """
        "AppState"
        {
            "appid"   "570"
            "name"    "Dota 2"
        }
        """

        let appId = SteamAppManifest.parseAppId(from: acfContent)
        XCTAssertEqual(appId, 570)
    }

    func testSteamAppManifestReturnsNilForMissingAppId() {
        let acfContent = """
        "AppState"
        {
            "name"    "Some Game"
        }
        """

        let appId = SteamAppManifest.parseAppId(from: acfContent)
        XCTAssertNil(appId)
    }

    // MARK: - Test 11: GameConfigSnapshot Plist Round-Trip

    func testGameConfigSnapshotPlistRoundTrip() throws {
        let sampleSettings = Data("sample-settings-plist".utf8)
        let programSettings = ["file:///app/game.exe": Data("program-data".utf8)]

        let snapshot = GameConfigSnapshot(
            bottleSettingsData: sampleSettings,
            programSettingsData: programSettings,
            installedVerbs: ["vcrun2022", "dotnet48"],
            appliedEntryId: "elden-ring",
            appliedVariantId: "recommended-apple-silicon",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(snapshot)

        let decoded = try PropertyListDecoder().decode(GameConfigSnapshot.self, from: data)

        XCTAssertEqual(decoded.bottleSettingsData, sampleSettings)
        XCTAssertEqual(decoded.programSettingsData, programSettings)
        XCTAssertEqual(decoded.installedVerbs, ["vcrun2022", "dotnet48"])
        XCTAssertEqual(decoded.appliedEntryId, "elden-ring")
        XCTAssertEqual(decoded.appliedVariantId, "recommended-apple-silicon")
        XCTAssertEqual(decoded.timestamp.timeIntervalSince1970, 1_700_000_000, accuracy: 1.0)
    }

    // MARK: - Test 12: GameConfigSnapshot Save and Load

    func testGameConfigSnapshotSaveAndLoad() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "SnapshotTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let snapshot = GameConfigSnapshot(
            bottleSettingsData: Data("bottle-data".utf8),
            installedVerbs: ["vcrun2022"],
            appliedEntryId: "test-game",
            appliedVariantId: "default",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )

        try GameConfigSnapshot.save(snapshot, to: tempDir)

        let loaded = GameConfigSnapshot.load(from: tempDir)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.appliedEntryId, "test-game")
        XCTAssertEqual(loaded?.appliedVariantId, "default")
        XCTAssertEqual(loaded?.bottleSettingsData, Data("bottle-data".utf8))
        XCTAssertEqual(loaded?.installedVerbs, ["vcrun2022"])
    }

    // MARK: - Test 13: GameConfigSnapshot Load Returns Nil for Missing

    func testGameConfigSnapshotLoadReturnsNilForMissing() {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "SnapshotMissing-\(UUID().uuidString)")

        let loaded = GameConfigSnapshot.load(from: tempDir)
        XCTAssertNil(loaded)
    }

    // MARK: - Test: GameDBLoader loads bundled JSON

    func testGameDBLoaderLoadsBundledJSON() {
        let entries = GameDBLoader.loadDefaults()
        XCTAssertGreaterThanOrEqual(entries.count, 15, "Expected at least 15 entries in GameDB.json")

        // Check all 5 rating tiers are covered
        let ratings = Set(entries.map(\.rating))
        XCTAssertTrue(ratings.contains(.works))
        XCTAssertTrue(ratings.contains(.playable))
        XCTAssertTrue(ratings.contains(.unverified))
        XCTAssertTrue(ratings.contains(.broken))
        XCTAssertTrue(ratings.contains(.notSupported))

        // Every entry has at least one variant
        for entry in entries {
            XCTAssertFalse(entry.variants.isEmpty, "Entry \(entry.id) has no variants")
        }

        // All IDs are unique
        let ids = entries.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Duplicate entry IDs found")
    }

    // MARK: - Test 14: GameConfigSnapshot Delete

    func testGameConfigSnapshotDelete() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "SnapshotDelete-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let snapshot = GameConfigSnapshot(
            appliedEntryId: "test-game",
            appliedVariantId: "default",
            timestamp: Date()
        )

        try GameConfigSnapshot.save(snapshot, to: tempDir)

        // Verify file exists
        let snapshotURL = tempDir.appending(path: "GameConfigSnapshot.plist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshotURL.path(percentEncoded: false)))

        // Delete
        try GameConfigSnapshot.delete(from: tempDir)

        // Verify file removed
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotURL.path(percentEncoded: false)))

        // Load returns nil
        XCTAssertNil(GameConfigSnapshot.load(from: tempDir))
    }
}

// swiftlint:enable file_length
