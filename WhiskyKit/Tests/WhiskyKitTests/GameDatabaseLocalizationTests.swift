//
//  GameDatabaseLocalizationTests.swift
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

/// Checks the localized text of game matches and configuration previews.
///
/// Match explanations look up their key with an English default, which the test
/// runner returns; each one is compared with the catalog's English for that key,
/// so the fallback and the catalog can't drift apart.
final class GameDatabaseLocalizationTests: XCTestCase {
    // MARK: - Fixtures

    private func catalogEnglish(_ key: String, _ arguments: CVarArg...) -> String {
        guard let format = StringCatalog.english[key], !format.isEmpty else {
            XCTFail("\(key) has no English value in Localizable.xcstrings")
            return ""
        }
        return String(format: format, arguments: arguments)
    }

    private func entry(
        steamAppId: Int? = nil,
        exeNames: [String]? = nil,
        fingerprints: [ExeFingerprint]? = nil,
        pathPatterns: [String]? = nil
    ) -> GameDBEntry {
        GameDBEntry(
            id: "frost-quest",
            title: "Frost Quest",
            steamAppId: steamAppId,
            rating: .playable,
            exeNames: exeNames,
            exeFingerprints: fingerprints,
            pathPatterns: pathPatterns,
            variants: [GameConfigVariant(id: "default", label: "Default", settings: GameConfigVariantSettings())]
        )
    }

    private func onlyMatch(_ metadata: ProgramMetadata, _ entry: GameDBEntry) throws -> MatchResult {
        let results = GameMatcher.match(metadata: metadata, against: [entry])
        XCTAssertEqual(results.count, 1)
        return try XCTUnwrap(results.first)
    }

    // MARK: - Hard Identifiers

    func testSteamAppIdExplanationMatchesTheCatalogWithoutDigitGrouping() throws {
        let result = try onlyMatch(
            ProgramMetadata(exeName: "whatever.exe", steamAppId: 1_245_620),
            entry(steamAppId: 1_245_620)
        )
        XCTAssertEqual(result.tier, .hardIdentifier)
        XCTAssertEqual(result.explanation, catalogEnglish("gameConfig.match.steamAppId %@", "1245620"))
        XCTAssertFalse(result.explanation.contains("1,245,620"), result.explanation)
    }

    func testFingerprintExplanationMatchesTheCatalog() throws {
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let result = try onlyMatch(
            ProgramMetadata(exeName: "whatever.exe", fileSize: 4_096, peTimestamp: stamp),
            entry(fingerprints: [ExeFingerprint(fileSize: 4_096, peTimestamp: stamp.addingTimeInterval(0.5))])
        )
        XCTAssertEqual(result.tier, .hardIdentifier)
        XCTAssertEqual(result.confidence, 0.95)
        XCTAssertEqual(result.explanation, catalogEnglish("gameConfig.match.fingerprint"))
    }

    // MARK: - Executable Names

    private struct ExeNameCase {
        let exe: String
        let installPath: String?
        let key: String
        let score: Double
    }

    func testEachExeNameCombinationHasItsOwnWholeSentence() throws {
        let path = "C:/Games/FrostQuest/bin"
        let cases = [
            ExeNameCase(exe: "frostquest.exe", installPath: nil, key: "gameConfig.match.exeName %@", score: 0.85),
            ExeNameCase(exe: "frostquest.exe", installPath: path, key: "gameConfig.match.exeName.path %@", score: 0.90),
            ExeNameCase(exe: "launcher.exe", installPath: nil, key: "gameConfig.match.exeName.generic %@", score: 0.55),
            ExeNameCase(
                exe: "launcher.exe", installPath: path, key: "gameConfig.match.exeName.pathGeneric %@", score: 0.60
            )
        ]
        var explanations: Set<String> = []
        for testCase in cases {
            let result = try onlyMatch(
                ProgramMetadata(exeName: testCase.exe, installPath: testCase.installPath),
                entry(exeNames: ["FrostQuest.exe", "Launcher.exe"], pathPatterns: ["frostquest"])
            )
            XCTAssertEqual(result.tier, .strongHeuristic, testCase.key)
            XCTAssertEqual(result.confidence, testCase.score, accuracy: 0.0001, testCase.key)
            XCTAssertEqual(result.explanation, catalogEnglish(testCase.key, testCase.exe), testCase.key)
            explanations.insert(result.explanation)
        }
        XCTAssertEqual(explanations.count, cases.count)
    }

    // MARK: - Fuzzy Tokens

    func testTokenExplanationsCarryBothCountsWithAndWithoutThePathBonus() throws {
        let metadata = ProgramMetadata(exeName: "frostquest_beta.exe")
        let plain = try onlyMatch(metadata, entry(pathPatterns: ["frostquest"]))
        XCTAssertEqual(plain.tier, .fuzzy)
        XCTAssertEqual(plain.explanation, catalogEnglish("gameConfig.match.tokens %lld %lld", 1, 2))

        let withPath = try onlyMatch(
            ProgramMetadata(exeName: "frostquest_beta.exe", installPath: "C:/Games/FrostQuest"),
            entry(pathPatterns: ["frostquest"])
        )
        XCTAssertEqual(withPath.tier, .fuzzy)
        XCTAssertEqual(withPath.explanation, catalogEnglish("gameConfig.match.tokens.path %lld %lld", 1, 2))
        XCTAssertGreaterThan(withPath.confidence, plain.confidence)
    }

    // MARK: - Configuration Preview

    @MainActor
    private func makeBottle() throws -> Bottle {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "GameDatabaseLocalizationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try BottleSettings().encode(to: dir.appending(path: "Metadata.plist"))
        return Bottle(bottleUrl: dir)
    }

    @MainActor
    func testEveryPreviewKindHasLocalizedTextAndItsRawNamesStayAsIs() throws {
        let bottle = try makeBottle()
        defer { try? FileManager.default.removeItem(at: bottle.url) }
        let current = bottle.settings
        let wantedSync: EnhancedSync = current.enhancedSync == .esync ? .msync : .esync
        let variant = GameConfigVariant(
            id: "all",
            label: "All",
            settings: GameConfigVariantSettings(
                dxvk: !current.dxvk,
                dxvkAsync: !current.dxvkAsync,
                enhancedSync: wantedSync,
                shaderCacheEnabled: !current.shaderCacheEnabled,
                avxEnabled: !current.avxEnabled
            ),
            environmentVariables: ["WINE_TEST_FLAG": "1"],
            dllOverrides: [DLLOverrideEntry(dllName: "dxgi", mode: .nativeThenBuiltin)],
            winetricksVerbs: ["vcrun2019"]
        )

        let changes = GameConfigApplicator.previewChanges(
            variant: variant, bottle: bottle, isBackendAvailable: { _ in true }
        )
        let byKind = Dictionary(grouping: changes, by: \.kind)
        let expected: [ConfigChange.Kind] = [
            .dxvk, .dxvkAsync, .enhancedSync, .shaderCache, .avx, .dllOverride, .environmentVariable, .winetricksVerb
        ]
        XCTAssertEqual(Set(byKind.keys), Set(expected))

        for change in changes {
            assertCatalogKey(change.category)
            assertCatalogKey(change.currentValue)
        }

        // Names that are identifiers stay as they are; the rest are catalog keys.
        XCTAssertEqual(byKind[.dxvk]?.first?.settingName, "DXVK")
        XCTAssertEqual(byKind[.dllOverride]?.first?.settingName, "dxgi")
        XCTAssertEqual(byKind[.environmentVariable]?.first?.settingName, "WINE_TEST_FLAG")
        XCTAssertEqual(byKind[.environmentVariable]?.first?.newValue, "1")
        XCTAssertEqual(byKind[.winetricksVerb]?.first?.settingName, "vcrun2019")
        for kind: ConfigChange.Kind in [.dxvkAsync, .enhancedSync, .shaderCache, .avx] {
            try assertCatalogKey(XCTUnwrap(byKind[kind]?.first).settingName)
        }
        for kind: ConfigChange.Kind in [.dxvk, .dxvkAsync, .enhancedSync, .shaderCache, .avx, .winetricksVerb] {
            try assertCatalogKey(XCTUnwrap(byKind[kind]?.first).newValue)
        }

        let graphics = String(localized: "gameConfig.detail.graphics")
        let performance = String(localized: "gameConfig.detail.performance")
        XCTAssertEqual(byKind[.dxvk]?.first?.category, graphics)
        XCTAssertEqual(byKind[.dxvkAsync]?.first?.category, graphics)
        XCTAssertEqual(byKind[.avx]?.first?.category, performance)
        XCTAssertEqual(byKind[.environmentVariable]?.first?.category, String(localized: "program.env"))
        XCTAssertEqual(byKind[.dllOverride]?.first?.currentValue, String(localized: "gameConfig.preview.value.notSet"))
    }

    @MainActor
    func testOnAndOffAreDifferentKeysAndFollowTheBottleValue() throws {
        let bottle = try makeBottle()
        defer { try? FileManager.default.removeItem(at: bottle.url) }
        bottle.settings.avxEnabled = false

        let variant = GameConfigVariant(
            id: "avx", label: "AVX", settings: GameConfigVariantSettings(avxEnabled: true)
        )
        let change = try XCTUnwrap(GameConfigApplicator.previewChanges(variant: variant, bottle: bottle).first)
        XCTAssertEqual(change.kind, .avx)
        XCTAssertEqual(change.currentValue, String(localized: "config.retinaMode.off"))
        XCTAssertEqual(change.newValue, String(localized: "config.retinaMode.on"))
        XCTAssertNotEqual(change.currentValue, change.newValue)
    }

    @MainActor
    func testEnhancedSyncValuesEachHaveTheirOwnKey() throws {
        let bottle = try makeBottle()
        defer { try? FileManager.default.removeItem(at: bottle.url) }
        var seen: Set<String> = []
        for (current, wanted) in [(EnhancedSync.none, EnhancedSync.esync), (.esync, .msync), (.msync, .none)] {
            bottle.settings.enhancedSync = current
            let variant = GameConfigVariant(
                id: "sync", label: "Sync", settings: GameConfigVariantSettings(enhancedSync: wanted)
            )
            let change = try XCTUnwrap(GameConfigApplicator.previewChanges(variant: variant, bottle: bottle).first)
            XCTAssertEqual(change.kind, .enhancedSync)
            assertCatalogKey(change.currentValue)
            assertCatalogKey(change.newValue)
            seen.insert(change.currentValue)
        }
        XCTAssertEqual(seen.count, 3)
    }

    @MainActor
    func testChangedDLLModeKeepsTheModeNamesAndTheLocalizedCategory() throws {
        let bottle = try makeBottle()
        defer { try? FileManager.default.removeItem(at: bottle.url) }
        bottle.settings.dllOverrides = [DLLOverrideEntry(dllName: "d3d11", mode: .builtin)]

        let variant = GameConfigVariant(
            id: "dll",
            label: "DLL",
            settings: GameConfigVariantSettings(),
            dllOverrides: [DLLOverrideEntry(dllName: "d3d11", mode: .native)]
        )
        let change = try XCTUnwrap(GameConfigApplicator.previewChanges(variant: variant, bottle: bottle).first)
        XCTAssertEqual(change.kind, .dllOverride)
        XCTAssertEqual(change.category, String(localized: "gameConfig.detail.dllOverrides"))
        XCTAssertEqual(change.currentValue, DLLOverrideMode.builtin.displayName)
        XCTAssertEqual(change.newValue, DLLOverrideMode.native.displayName)
        XCTAssertTrue(change.isHighImpact)
    }

    @MainActor
    func testBackendChangeUsesTheLocalizedSettingName() throws {
        let bottle = try makeBottle()
        defer { try? FileManager.default.removeItem(at: bottle.url) }
        let variant = GameConfigVariant(
            id: "backend", label: "Backend", settings: GameConfigVariantSettings(graphicsBackend: .wined3d)
        )
        let change = try XCTUnwrap(
            GameConfigApplicator.previewChanges(variant: variant, bottle: bottle, isBackendAvailable: { _ in true })
                .first { $0.kind == .graphicsBackend }
        )
        XCTAssertEqual(change.category, String(localized: "gameConfig.detail.graphics"))
        XCTAssertEqual(change.settingName, String(localized: "config.graphics.backend"))
        assertCatalogKey(change.settingName)
    }
}
