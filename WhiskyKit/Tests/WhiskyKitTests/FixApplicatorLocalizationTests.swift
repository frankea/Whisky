//
//  FixApplicatorLocalizationTests.swift
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

/// The text a fix preview puts on screen: every setting name and value it
/// builds from a lookup has to name a catalog key with English, while the
/// values that come from the bottle (verbs, registry names, game titles)
/// pass through unchanged, and the attempt the apply step records stays raw.
@MainActor
final class FixApplicatorLocalizationTests: XCTestCase {
    private var tempDir: URL!
    private var bottle: Bottle!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        bottle = Bottle(bottleUrl: tempDir, inFlight: false, isAvailable: true)
    }

    override func tearDownWithError() throws {
        bottle = nil
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        tempDir = nil
    }

    private func preview(
        _ fixId: String,
        params: [String: String] = [:],
        program: Program? = nil
    ) throws -> FixPreview {
        try XCTUnwrap(FixApplicator.preview(fixId: fixId, params: params, bottle: bottle, program: program))
    }

    private func makeProgram(_ relativePath: String) throws -> Program {
        let url = tempDir.appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        return Program(url: url, bottle: bottle)
    }

    /// Asserts that `key`, a key that is its own English, is in the catalog.
    private func assertPlainCatalogKey(_ key: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotNil(
            StringCatalog.english[key], "\"\(key)\" is not a key in Localizable.xcstrings", file: file, line: line
        )
    }

    // MARK: - Scope

    func testDisplayScopeLocalizesBottleAndProgram() {
        let bottleScope = FixPreview(
            settingName: "s", currentValue: "a", newValue: "b", scope: "bottle", isReversible: true
        )
        let programScope = FixPreview(
            settingName: "s", currentValue: "a", newValue: "b", scope: "program", isReversible: true
        )

        XCTAssertEqual(bottleScope.displayScope, String(localized: "Bottle"))
        XCTAssertEqual(programScope.displayScope, String(localized: "Program"))
        XCTAssertNotEqual(bottleScope.displayScope, programScope.displayScope)
        assertPlainCatalogKey(bottleScope.displayScope)
        assertPlainCatalogKey(programScope.displayScope)
        // The stored scope stays the raw identifier.
        XCTAssertEqual(bottleScope.scope, "bottle")
        XCTAssertEqual(programScope.scope, "program")
    }

    func testDisplayScopeFallsBackToTheRawScope() {
        let preview = FixPreview(
            settingName: "s", currentValue: "a", newValue: "b", scope: "prefix", isReversible: false
        )

        XCTAssertEqual(preview.displayScope, "prefix")
    }

    func testEveryPreviewHasALocalizedScope() throws {
        let program = try makeProgram("Steam/steam.exe")
        for fixId in FixApplicator.knownFixIds.sorted() where fixId != "apply-game-config" {
            let fix = try XCTUnwrap(
                FixApplicator.preview(fixId: fixId, params: [:], bottle: bottle, program: program), fixId
            )
            XCTAssertTrue(["bottle", "program"].contains(fix.scope), "\(fixId) has scope \(fix.scope)")
            XCTAssertNotEqual(fix.displayScope, fix.scope, "\(fixId) shows its raw scope")
            assertPlainCatalogKey(fix.displayScope)
        }
    }

    // MARK: - Setting names

    func testBottleSettingNamesAreCatalogKeys() throws {
        let fixIds = [
            "switch-backend", "enable-dxvk-async", "set-audio-driver", "set-buffer-size",
            "enable-esync", "enable-controller-compat", "install-winetricks-verb",
            "set-registry-value", "apply-launcher-fixes"
        ]
        var names: Set<String> = []
        for fixId in fixIds {
            let name = try preview(fixId).settingName
            assertCatalogKey(name)
            names.insert(name)
        }
        XCTAssertEqual(names.count, fixIds.count, "two fixes share a setting name")
    }

    // MARK: - On/off states

    func testDXVKAsyncPreviewShowsOffThenOn() throws {
        bottle.settings.dxvkAsync = false

        let fix = try preview("enable-dxvk-async")

        XCTAssertEqual(fix.currentValue, String(localized: "config.retinaMode.off"))
        XCTAssertEqual(fix.newValue, String(localized: "config.retinaMode.on"))
        assertCatalogKey(fix.currentValue)
        assertCatalogKey(fix.newValue)
    }

    func testDXVKAsyncPreviewWhenAlreadyOn() throws {
        bottle.settings.dxvkAsync = true

        let fix = try preview("enable-dxvk-async")

        XCTAssertEqual(fix.currentValue, fix.newValue)
        XCTAssertEqual(fix.currentValue, String(localized: "config.retinaMode.on"))
    }

    func testControllerCompatPreviewFollowsTheSetting() throws {
        bottle.settings.controllerCompatibilityMode = false
        let whenOff = try preview("enable-controller-compat")
        bottle.settings.controllerCompatibilityMode = true
        let whenOn = try preview("enable-controller-compat")

        XCTAssertNotEqual(whenOff.currentValue, whenOn.currentValue)
        XCTAssertEqual(whenOff.currentValue, String(localized: "config.retinaMode.off"))
        XCTAssertEqual(whenOn.currentValue, String(localized: "config.retinaMode.on"))
        XCTAssertEqual(whenOff.newValue, whenOn.currentValue)
        assertCatalogKey(whenOff.currentValue)
        assertCatalogKey(whenOn.currentValue)
    }

    // MARK: - Enhanced sync

    func testEsyncPreviewNamesEachModeWithItsOwnKey() throws {
        var currentValues: [String] = []
        for mode in [EnhancedSync.none, .esync, .msync] {
            bottle.settings.enhancedSync = mode
            let fix = try preview("enable-esync")
            assertCatalogKey(fix.currentValue)
            XCTAssertEqual(fix.newValue, String(localized: "config.enhancedSync.esync"))
            currentValues.append(fix.currentValue)
        }

        XCTAssertEqual(currentValues, [
            String(localized: "config.enhancedSync.none"),
            String(localized: "config.enhancedSync.esync"),
            String(localized: "config.enhancedSync.msync")
        ])
        XCTAssertEqual(Set(currentValues).count, 3)
    }

    func testEsyncApplyStillRecordsTheRawMode() {
        bottle.settings.enhancedSync = .msync

        let attempt = FixApplicator.apply(fixId: "enable-esync", params: [:], bottle: bottle, program: nil)

        XCTAssertEqual(attempt.beforeValue, "msync")
        XCTAssertEqual(attempt.afterValue, "esync")
    }

    // MARK: - Winetricks

    func testWinetricksPreviewKeepsTheVerbAndLocalizesTheRest() throws {
        let fix = try preview("install-winetricks-verb", params: ["verb": "d3dx9"])

        XCTAssertEqual(fix.newValue, "d3dx9")
        XCTAssertEqual(fix.currentValue, String(localized: "gameConfig.preview.winetricksMissing"))
        XCTAssertEqual(fix.settingName, String(localized: "troubleshooting.fix.setting.winetricksVerb"))
    }

    func testWinetricksPreviewWithoutAVerbSaysUnknown() throws {
        let fix = try preview("install-winetricks-verb")

        XCTAssertEqual(fix.newValue, String(localized: "troubleshooting.fix.value.unknown"))
        assertCatalogKey(fix.newValue)
    }

    // MARK: - Enhanced diagnostics

    func testEnhancedDiagnosticsPreviewNamesThePresets() throws {
        let program = try makeProgram("game.exe")
        program.settings.activeWineDebugPreset = nil

        let fix = try preview("run-enhanced-diagnostics", program: program)

        XCTAssertEqual(fix.settingName, String(localized: "WINEDEBUG Preset"))
        assertPlainCatalogKey(fix.settingName)
        XCTAssertEqual(fix.currentValue, WineDebugPreset.normal.displayName)
        XCTAssertEqual(fix.newValue, WineDebugPreset.verbose.displayName)
        assertCatalogKey(fix.currentValue)
        assertCatalogKey(fix.newValue)
        XCTAssertEqual(fix.scope, "program")
        XCTAssertEqual(fix.displayScope, String(localized: "Program"))
    }

    func testEnhancedDiagnosticsPreviewUsesTheRequestedAndActivePresets() throws {
        let program = try makeProgram("game.exe")
        program.settings.activeWineDebugPreset = .dllLoad

        let fix = try preview("run-enhanced-diagnostics", params: ["preset": "crash"], program: program)

        XCTAssertEqual(fix.currentValue, WineDebugPreset.dllLoad.displayName)
        XCTAssertEqual(fix.newValue, WineDebugPreset.crash.displayName)
        XCTAssertNotEqual(fix.currentValue, fix.newValue)
    }

    func testEnhancedDiagnosticsApplyRecordsRawValuesNotDisplayNames() throws {
        let program = try makeProgram("game.exe")
        program.settings.activeWineDebugPreset = nil
        let fix = try preview("run-enhanced-diagnostics", program: program)

        let attempt = FixApplicator.apply(
            fixId: "run-enhanced-diagnostics", params: [:], bottle: bottle, program: program
        )

        XCTAssertEqual(attempt.beforeValue, "default")
        XCTAssertEqual(attempt.afterValue, WineDebugPreset.verbose.rawValue)
        XCTAssertNotEqual(attempt.afterValue, fix.newValue)
    }

    // MARK: - Registry value

    func testRegistryPreviewWithoutParamsUsesFallbackNames() throws {
        let fix = try preview("set-registry-value")

        XCTAssertEqual(fix.settingName, String(localized: "troubleshooting.fix.setting.registryValue"))
        XCTAssertEqual(fix.currentValue, String(localized: "troubleshooting.fix.value.unknown"))
        XCTAssertEqual(fix.newValue, String(localized: "config.buildVersion.notSet"))
        assertCatalogKey(fix.settingName)
        assertCatalogKey(fix.currentValue)
        assertCatalogKey(fix.newValue)
    }

    func testRegistryPreviewNamesTheValueWhenNoSettingNameIsGiven() throws {
        let fix = try preview(
            "set-registry-value",
            params: ["valueName": "NameServer", "value": "1.1.1.1"]
        )

        XCTAssertEqual(fix.settingName, "NameServer")
        // A value name alone, with no key, can't be read.
        XCTAssertEqual(fix.currentValue, String(localized: "troubleshooting.fix.value.unknown"))
        XCTAssertEqual(fix.newValue, "1.1.1.1")
    }

    // MARK: - Launcher fixes

    func testLauncherPreviewWithoutAProgramSaysNoLauncher() throws {
        let fix = try preview("apply-launcher-fixes")

        XCTAssertEqual(fix.currentValue, String(localized: "troubleshooting.fix.value.noLauncher"))
        XCTAssertEqual(fix.newValue, String(localized: "troubleshooting.fix.value.reapplied"))
        assertCatalogKey(fix.currentValue)
        assertCatalogKey(fix.newValue)
    }

    func testLauncherPreviewNamesTheDetectedLauncher() throws {
        let program = try makeProgram("Steam/steam.exe")

        let fix = try preview("apply-launcher-fixes", program: program)

        XCTAssertEqual(fix.currentValue, LauncherType.steam.displayName)
        XCTAssertEqual(fix.newValue, String(localized: "troubleshooting.fix.value.reapplied"))
    }

    // MARK: - Wineserver

    func testRestartWineserverPreviewIsLocalized() throws {
        let fix = try preview("restart-wineserver")

        XCTAssertEqual(fix.currentValue, String(localized: "console.running"))
        XCTAssertEqual(fix.newValue, String(localized: "troubleshooting.fix.value.restarted"))
        assertCatalogKey(fix.currentValue)
        assertCatalogKey(fix.newValue)
        XCTAssertNotEqual(fix.currentValue, fix.newValue)
    }

    // MARK: - Game configuration

    private func defaultVariant(of entryId: String) throws -> (GameDBEntry, GameConfigVariant) {
        let entry = try XCTUnwrap(GameDBLoader.loadDefaults().first { $0.id == entryId }, entryId)
        return try (entry, XCTUnwrap(entry.defaultVariant, entryId))
    }

    func testGameConfigPreviewCountsTheSettingsThatDiffer() throws {
        let (entry, variant) = try defaultVariant(of: "aoe2-de")
        let program = try makeProgram("AoE2DE/AoE2DE_s.exe")
        let changes = GameConfigApplicator.previewChanges(variant: variant, bottle: bottle)
        XCTAssertFalse(changes.isEmpty, "the variant installs winetricks verbs, so something always differs")

        let fix = try preview("apply-game-config", program: program)

        XCTAssertEqual(
            fix.settingName,
            String(localized: "troubleshooting.fix.setting.gameConfig \(entry.title)")
        )
        XCTAssertTrue(fix.settingName.hasSuffix(entry.title))
        assertCatalogKey(fix.settingName)
        XCTAssertEqual(
            fix.currentValue,
            String(localized: "troubleshooting.fix.value.settingsDiffer \(changes.count)")
        )
        assertCatalogKey(fix.currentValue)
        XCTAssertEqual(fix.newValue, variant.label)
    }

    func testGameConfigPreviewSaysAlreadyMatchesWhenNothingDiffers() throws {
        // Celeste's default variant has no verbs, overrides or variables, so
        // copying its settings onto the bottle leaves nothing to change.
        let (_, variant) = try defaultVariant(of: "celeste")
        let settings = variant.settings
        if let backend = settings.graphicsBackend {
            bottle.settings.graphicsBackend = GameConfigApplicator.effectiveBackend(backend)
        }
        if let dxvk = settings.dxvk { bottle.settings.dxvk = dxvk }
        if let dxvkAsync = settings.dxvkAsync { bottle.settings.dxvkAsync = dxvkAsync }
        if let enhancedSync = settings.enhancedSync { bottle.settings.enhancedSync = enhancedSync }
        if let shaderCache = settings.shaderCacheEnabled { bottle.settings.shaderCacheEnabled = shaderCache }
        if let avx = settings.avxEnabled { bottle.settings.avxEnabled = avx }
        XCTAssertTrue(GameConfigApplicator.previewChanges(variant: variant, bottle: bottle).isEmpty)
        let program = try makeProgram("Celeste/Celeste.exe")

        let fix = try preview("apply-game-config", program: program)

        XCTAssertEqual(fix.currentValue, String(localized: "troubleshooting.fix.value.alreadyMatches"))
        assertCatalogKey(fix.currentValue)
        XCTAssertEqual(fix.newValue, variant.label)
    }
}
