//
//  LauncherLocaleMigrationTests.swift
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

import Foundation
@testable import WhiskyKit
import XCTest

// MARK: - Migration of the English older Steam fixes wrote (#330)

final class LauncherLocaleMigrationTests: LauncherFixesTestCase {
    /// A bottle as 3.8.0's Steam fixes left it, without the migration stamp.
    @MainActor
    private func makeLegacyBottle(
        launcher: LauncherType = .steam, locale: Locales = .english
    ) -> Bottle {
        let bottle = makeBottle()
        bottle.settings.launcherCompatibilityMode = true
        bottle.settings.detectedLauncher = launcher
        bottle.settings.launcherLocale = locale
        bottle.settings.launcherLocaleMigration = 0
        // Reloaded from disk, the way the app meets it after the update.
        return Bottle(bottleUrl: bottleURL)
    }

    @MainActor
    func testLegacySteamEnglishGoesBackToAutoOnce() throws {
        let bottle = makeLegacyBottle()

        XCTAssertTrue(LauncherLocaleMigration.migrateIfNeeded(bottle))

        XCTAssertEqual(bottle.settings.launcherLocale, .auto)
        let persisted = try persistedSettings()
        XCTAssertEqual(persisted.launcherLocale, .auto)
        XCTAssertEqual(persisted.launcherLocaleMigration, LauncherLocaleMigration.current)

        // English picked again afterwards is the user's choice and stays.
        bottle.settings.launcherLocale = .english
        XCTAssertFalse(LauncherLocaleMigration.migrateIfNeeded(bottle))
        XCTAssertEqual(bottle.settings.launcherLocale, .english)
    }

    @MainActor
    func testLegacySteamBottleThenLaunchesWithoutALocale() {
        let bottle = makeLegacyBottle()
        LauncherLocaleMigration.migrateIfNeeded(bottle)

        let env = Wine.constructWineEnvironment(for: bottle, builtinD3D12IsD3DMetal: false)

        XCTAssertNil(env["LC_ALL"])
        XCTAssertNil(env["LANG"])
    }

    @MainActor
    func testAnotherLocaleIsKeptButStamped() throws {
        let bottle = makeLegacyBottle(locale: .japanese)

        XCTAssertFalse(LauncherLocaleMigration.migrateIfNeeded(bottle))

        XCTAssertEqual(bottle.settings.launcherLocale, .japanese)
        XCTAssertEqual(try persistedSettings().launcherLocaleMigration, LauncherLocaleMigration.current)
    }

    @MainActor
    func testTheOtherPresetLaunchersGoBackToAutoAndKeepTheirEnUS() {
        for launcher in [LauncherType.eaApp, .epicGames, .battleNet, .rockstar] {
            let bottle = makeLegacyBottle(launcher: launcher)

            XCTAssertTrue(LauncherLocaleMigration.migrateIfNeeded(bottle), "\(launcher.rawValue)")

            XCTAssertEqual(bottle.settings.launcherLocale, .auto, "\(launcher.rawValue)")
            // Their presets still carry en_US, so Auto launches the same.
            let env = Wine.constructWineEnvironment(for: bottle, builtinD3D12IsD3DMetal: false)
            XCTAssertEqual(env["LC_ALL"], "en_US.UTF-8", "\(launcher.rawValue)")
        }
    }

    @MainActor
    func testLaunchersWhoseFixesNeverWroteEnglishKeepIt() throws {
        for launcher in [LauncherType.ubisoft, .paradox] {
            let bottle = makeLegacyBottle(launcher: launcher)

            XCTAssertFalse(LauncherLocaleMigration.migrateIfNeeded(bottle), "\(launcher.rawValue)")

            XCTAssertEqual(bottle.settings.launcherLocale, .english, "\(launcher.rawValue)")
            XCTAssertEqual(
                try persistedSettings().launcherLocaleMigration, LauncherLocaleMigration.current,
                "\(launcher.rawValue)"
            )
        }
    }

    @MainActor
    func testEnglishLeftUnderAnotherLauncherDoesNotComeBackToSteam() {
        // Steam's fixes wrote English, then EA App was configured in the same bottle.
        let bottle = makeLegacyBottle(launcher: .eaApp)
        LauncherLocaleMigration.migrateIfNeeded(bottle)

        // The next Steam client start applies the Steam fixes again.
        LauncherFixes.apply(to: bottle, launcher: .steam, recommendedBackend: .d3dMetal)

        XCTAssertEqual(bottle.settings.detectedLauncher, .steam)
        let env = Wine.constructWineEnvironment(for: bottle, builtinD3D12IsD3DMetal: false)
        XCTAssertNil(env["LC_ALL"])
        XCTAssertNil(env["LANG"])
    }

    @MainActor
    func testANewBottleIsAlreadyStamped() {
        let bottle = makeBottle()
        bottle.settings.detectedLauncher = .steam
        bottle.settings.launcherLocale = .english

        XCTAssertEqual(bottle.settings.launcherLocaleMigration, LauncherLocaleMigration.current)
        XCTAssertFalse(LauncherLocaleMigration.migrateIfNeeded(bottle))
        XCTAssertEqual(bottle.settings.launcherLocale, .english)
    }

    @MainActor
    func testAFileWithoutTheStampDecodesAsUnmigrated() throws {
        let bottle = makeBottle()
        bottle.settings.detectedLauncher = .steam
        bottle.settings.launcherLocale = .english

        // Strip the key, the way a Metadata.plist from 3.9.0 or earlier reads.
        let data = try Data(contentsOf: metadataURL)
        var plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        var launcherConfig = try XCTUnwrap(plist["launcherConfig"] as? [String: Any])
        XCTAssertNotNil(launcherConfig.removeValue(forKey: "localeMigration"))
        plist["launcherConfig"] = launcherConfig
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: metadataURL)

        let reloaded = Bottle(bottleUrl: bottleURL)
        XCTAssertEqual(reloaded.settings.launcherLocaleMigration, 0)
        XCTAssertTrue(LauncherLocaleMigration.migrateIfNeeded(reloaded))
        XCTAssertEqual(reloaded.settings.launcherLocale, .auto)
    }
}
