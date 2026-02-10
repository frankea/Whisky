// swiftlint:disable file_length
//
//  GameApplicatorTests.swift
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

// MARK: - GameConfigApplicator Tests

final class GameApplicatorTests: XCTestCase {

    // MARK: - Test Fixtures

    /// Creates a temporary bottle directory with a default Metadata.plist.
    @MainActor
    private func makeTestBottle() throws -> Bottle {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "GameApplicatorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Write default Metadata.plist so Bottle can decode settings
        let settings = BottleSettings()
        try settings.encode(to: tempDir.appending(path: "Metadata.plist"))

        return Bottle(bottleUrl: tempDir)
    }

    /// Removes a test bottle's directory.
    @MainActor
    private func cleanupBottle(_ bottle: Bottle) {
        try? FileManager.default.removeItem(at: bottle.url)
    }

    /// Creates a test variant with specific settings.
    private func makeTestVariant(
        id: String = "test-variant",
        graphicsBackend: GraphicsBackend? = nil,
        dxvk: Bool? = nil,
        dxvkAsync: Bool? = nil,
        enhancedSync: EnhancedSync? = nil,
        forceD3D11: Bool? = nil,
        performancePreset: String? = nil,
        shaderCacheEnabled: Bool? = nil,
        avxEnabled: Bool? = nil,
        sequoiaCompatMode: Bool? = nil,
        dllOverrides: [DLLOverrideEntry]? = nil,
        winetricksVerbs: [String]? = nil,
        environmentVariables: [String: String]? = nil
    ) -> GameConfigVariant {
        GameConfigVariant(
            id: id,
            label: "Test Variant",
            isDefault: true,
            settings: GameConfigVariantSettings(
                graphicsBackend: graphicsBackend,
                dxvk: dxvk,
                dxvkAsync: dxvkAsync,
                enhancedSync: enhancedSync,
                forceD3D11: forceD3D11,
                performancePreset: performancePreset,
                shaderCacheEnabled: shaderCacheEnabled,
                avxEnabled: avxEnabled,
                sequoiaCompatMode: sequoiaCompatMode
            ),
            environmentVariables: environmentVariables,
            dllOverrides: dllOverrides,
            winetricksVerbs: winetricksVerbs
        )
    }

    /// Creates a test entry with the given variant.
    private func makeTestEntry(variant: GameConfigVariant) -> GameDBEntry {
        GameDBEntry(
            id: "test-game",
            title: "Test Game",
            rating: .playable,
            variants: [variant]
        )
    }

    // MARK: - Test 1: Apply Creates Snapshot

    @MainActor
    func testApplyCreatesSnapshot() throws {
        let bottle = try makeTestBottle()
        defer { cleanupBottle(bottle) }

        let variant = makeTestVariant(graphicsBackend: .dxvk)
        let entry = makeTestEntry(variant: variant)

        let snapshot = try GameConfigApplicator.apply(entry: entry, variant: variant, to: bottle)

        XCTAssertNotNil(snapshot.bottleSettingsData, "Snapshot should contain bottle settings data")
        XCTAssertEqual(snapshot.appliedEntryId, "test-game")
        XCTAssertEqual(snapshot.appliedVariantId, "test-variant")

        // Verify snapshot was saved to disk
        let loaded = GameConfigSnapshot.load(from: bottle.url)
        XCTAssertNotNil(loaded, "Snapshot should be saved to bottle directory")
        XCTAssertEqual(loaded?.appliedEntryId, "test-game")
    }

    // MARK: - Test 2: Apply Mutates Bottle Settings

    @MainActor
    func testApplyMutatesBottleSettings() throws {
        let bottle = try makeTestBottle()
        defer { cleanupBottle(bottle) }

        // Verify starting state
        XCTAssertEqual(bottle.settings.graphicsBackend, .recommended)

        let variant = makeTestVariant(graphicsBackend: .dxvk, dxvkAsync: true)
        let entry = makeTestEntry(variant: variant)

        _ = try GameConfigApplicator.apply(entry: entry, variant: variant, to: bottle)

        XCTAssertEqual(bottle.settings.graphicsBackend, .dxvk, "Graphics backend should be changed to DXVK")
        XCTAssertTrue(bottle.settings.dxvkAsync, "DXVK async should be enabled")
    }

    // MARK: - Test 3: Apply Adds DLL Overrides

    @MainActor
    func testApplyAddsDLLOverrides() throws {
        let bottle = try makeTestBottle()
        defer { cleanupBottle(bottle) }

        // Start with one existing override
        bottle.settings.dllOverrides = [
            DLLOverrideEntry(dllName: "existing", mode: .builtin)
        ]

        let overrides = [
            DLLOverrideEntry(dllName: "dxgi", mode: .nativeThenBuiltin),
            DLLOverrideEntry(dllName: "d3d11", mode: .nativeThenBuiltin)
        ]
        let variant = makeTestVariant(dllOverrides: overrides)
        let entry = makeTestEntry(variant: variant)

        _ = try GameConfigApplicator.apply(entry: entry, variant: variant, to: bottle)

        XCTAssertEqual(bottle.settings.dllOverrides.count, 3, "Should have existing + 2 new overrides")
        XCTAssertTrue(
            bottle.settings.dllOverrides.contains(where: { $0.dllName == "existing" }),
            "Existing override should be preserved"
        )
        XCTAssertTrue(
            bottle.settings.dllOverrides.contains(where: { $0.dllName == "dxgi" }),
            "New dxgi override should be added"
        )
        XCTAssertTrue(
            bottle.settings.dllOverrides.contains(where: { $0.dllName == "d3d11" }),
            "New d3d11 override should be added"
        )
    }

    // MARK: - Test 4: Revert Restores Original Settings

    @MainActor
    func testRevertRestoresOriginalSettings() throws {
        let bottle = try makeTestBottle()
        defer { cleanupBottle(bottle) }

        // Record original state
        let originalBackend = bottle.settings.graphicsBackend
        let originalDxvkAsync = bottle.settings.dxvkAsync
        let originalForceD3D11 = bottle.settings.forceD3D11

        // Apply changes that differ from defaults:
        // graphicsBackend default = .recommended, dxvkAsync default = true, forceD3D11 default = false
        let variant = makeTestVariant(
            graphicsBackend: .dxvk,
            dxvkAsync: false,
            forceD3D11: true
        )
        let entry = makeTestEntry(variant: variant)
        let snapshot = try GameConfigApplicator.apply(entry: entry, variant: variant, to: bottle)

        // Verify settings changed
        XCTAssertNotEqual(bottle.settings.graphicsBackend, originalBackend)
        XCTAssertNotEqual(bottle.settings.dxvkAsync, originalDxvkAsync)
        XCTAssertNotEqual(bottle.settings.forceD3D11, originalForceD3D11)

        // Revert
        _ = try GameConfigApplicator.revert(bottle: bottle, snapshot: snapshot)

        // Verify settings restored
        XCTAssertEqual(
            bottle.settings.graphicsBackend,
            originalBackend,
            "Graphics backend should be restored"
        )
        XCTAssertEqual(
            bottle.settings.dxvkAsync,
            originalDxvkAsync,
            "DXVK async should be restored"
        )
        XCTAssertEqual(
            bottle.settings.forceD3D11,
            originalForceD3D11,
            "Force D3D11 should be restored"
        )
    }

    // MARK: - Test 5: Revert Returns Installed Verbs

    @MainActor
    func testRevertReturnsInstalledVerbs() throws {
        let bottle = try makeTestBottle()
        defer { cleanupBottle(bottle) }

        let variant = makeTestVariant(winetricksVerbs: ["vcrun2022", "dotnet48"])
        let entry = makeTestEntry(variant: variant)
        let snapshot = try GameConfigApplicator.apply(entry: entry, variant: variant, to: bottle)

        let verbs = try GameConfigApplicator.revert(bottle: bottle, snapshot: snapshot)

        XCTAssertEqual(verbs, ["vcrun2022", "dotnet48"], "Revert should return the installed verbs list")
    }

    // MARK: - Test 6: Pending Winetricks Verbs Filters Installed

    func testPendingWinetricksVerbsFiltersInstalled() {
        let variant = makeTestVariant(winetricksVerbs: ["vcrun2022", "dotnet48"])

        let installedVerbs: Set<String> = ["vcrun2022"]
        let pending = GameConfigApplicator.pendingWinetricksVerbs(
            variant: variant,
            installedVerbs: installedVerbs
        )

        XCTAssertEqual(pending, ["dotnet48"], "Only uninstalled verbs should be returned")
    }

    // MARK: - Test 7: Preview Changes Shows Diff

    @MainActor
    func testPreviewChangesShowsDiff() throws {
        let bottle = try makeTestBottle()
        defer { cleanupBottle(bottle) }

        // Start with default settings (graphicsBackend = .recommended, enhancedSync = .msync)
        let variant = makeTestVariant(
            graphicsBackend: .dxvk,
            enhancedSync: .esync,
            dllOverrides: [DLLOverrideEntry(dllName: "dxgi", mode: .nativeThenBuiltin)]
        )

        let changes = GameConfigApplicator.previewChanges(variant: variant, bottle: bottle)

        // Should have at least graphics backend change
        let backendChange = changes.first { $0.settingName == "Graphics Backend" }
        XCTAssertNotNil(backendChange, "Should include graphics backend change")
        XCTAssertEqual(backendChange?.newValue, GraphicsBackend.dxvk.displayName)
        XCTAssertTrue(backendChange?.isHighImpact == true, "Graphics backend change should be high impact")

        // Should have enhanced sync change
        let syncChange = changes.first { $0.settingName == "Enhanced Sync" }
        XCTAssertNotNil(syncChange, "Should include enhanced sync change")
        XCTAssertEqual(syncChange?.newValue, "ESync")

        // Should have DLL override change
        let dllChange = changes.first { $0.settingName == "dxgi" }
        XCTAssertNotNil(dllChange, "Should include DLL override change")
        XCTAssertEqual(dllChange?.category, "DLL Overrides")
        XCTAssertTrue(dllChange?.isHighImpact == true, "DLL override additions should be high impact")
    }

    // MARK: - Test: Apply DLL Overrides Deduplicates by Name

    @MainActor
    func testApplyDLLOverridesDeduplicatesByName() throws {
        let bottle = try makeTestBottle()
        defer { cleanupBottle(bottle) }

        // Start with an existing override
        bottle.settings.dllOverrides = [
            DLLOverrideEntry(dllName: "dxgi", mode: .builtin)
        ]

        // Apply variant with a different mode for the same DLL
        let overrides = [
            DLLOverrideEntry(dllName: "dxgi", mode: .nativeThenBuiltin)
        ]
        let variant = makeTestVariant(dllOverrides: overrides)
        let entry = makeTestEntry(variant: variant)

        _ = try GameConfigApplicator.apply(entry: entry, variant: variant, to: bottle)

        // Should still have only one entry for dxgi, with the variant's value
        let dxgiOverrides = bottle.settings.dllOverrides.filter { $0.dllName == "dxgi" }
        XCTAssertEqual(dxgiOverrides.count, 1, "Should deduplicate by DLL name")
        XCTAssertEqual(
            dxgiOverrides.first?.mode,
            .nativeThenBuiltin,
            "Variant value should win during deduplication"
        )
    }

    // MARK: - Test: Preview Changes Returns Empty When No Diff

    @MainActor
    func testPreviewChangesReturnsEmptyWhenNoDiff() throws {
        let bottle = try makeTestBottle()
        defer { cleanupBottle(bottle) }

        // Variant with all nil settings (no changes)
        let variant = makeTestVariant()

        let changes = GameConfigApplicator.previewChanges(variant: variant, bottle: bottle)
        XCTAssertTrue(changes.isEmpty, "No changes should be reported when variant matches bottle")
    }

    // MARK: - Test: Multiple Settings Applied Together

    @MainActor
    func testMultipleSettingsAppliedTogether() throws {
        let bottle = try makeTestBottle()
        defer { cleanupBottle(bottle) }

        let variant = makeTestVariant(
            graphicsBackend: .wined3d,
            dxvkAsync: false,
            enhancedSync: .esync,
            forceD3D11: true,
            performancePreset: "performance",
            shaderCacheEnabled: false,
            avxEnabled: true,
            sequoiaCompatMode: true
        )
        let entry = makeTestEntry(variant: variant)

        _ = try GameConfigApplicator.apply(entry: entry, variant: variant, to: bottle)

        XCTAssertEqual(bottle.settings.graphicsBackend, .wined3d)
        XCTAssertFalse(bottle.settings.dxvkAsync)
        XCTAssertEqual(bottle.settings.enhancedSync, .esync)
        XCTAssertTrue(bottle.settings.forceD3D11)
        XCTAssertEqual(bottle.settings.performancePreset, .performance)
        XCTAssertFalse(bottle.settings.shaderCacheEnabled)
        XCTAssertTrue(bottle.settings.avxEnabled)
        XCTAssertTrue(bottle.settings.sequoiaCompatMode)
    }
}

// MARK: - StalenessChecker Tests (added in Task 2)

// Staleness tests will be added in Task 2

// swiftlint:enable file_length
