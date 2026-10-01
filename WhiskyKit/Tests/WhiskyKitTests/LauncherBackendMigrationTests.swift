//
//  LauncherBackendMigrationTests.swift
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

// MARK: - Migration of bottles the old Steam profile switched (#276)

final class LauncherBackendMigrationTests: LauncherFixesTestCase {
    /// A bottle as 3.7.0's Steam profile left it, without the migration stamp.
    @MainActor
    private func makeSwitchedBottle() throws -> Bottle {
        let bottle = makeBottle()
        bottle.settings.launcherCompatibilityMode = true
        bottle.settings.detectedLauncher = .steam
        bottle.settings.graphicsBackend = .dxvk
        bottle.settings.launcherBackendMigration = 0
        // Reloaded from disk, the way the app meets it after the update.
        return Bottle(bottleUrl: bottleURL)
    }

    @MainActor
    func testSwitchedBottleGoesBackToRecommendedOnce() throws {
        let bottle = try makeSwitchedBottle()

        XCTAssertTrue(LauncherBackendMigration.migrateIfNeeded(bottle, d3dMetalInstalled: true))

        XCTAssertEqual(bottle.settings.graphicsBackend, .recommended)
        XCTAssertTrue(bottle.settings.launcherBackendResetNotice)
        let persisted = try persistedSettings()
        XCTAssertEqual(persisted.graphicsBackend, .recommended)
        XCTAssertEqual(persisted.launcherBackendMigration, LauncherBackendMigration.current)
        XCTAssertTrue(persisted.launcherBackendResetNotice)

        // DXVK picked again afterwards is the user's choice and stays.
        bottle.settings.graphicsBackend = .dxvk
        XCTAssertFalse(LauncherBackendMigration.migrateIfNeeded(bottle, d3dMetalInstalled: true))
        XCTAssertEqual(bottle.settings.graphicsBackend, .dxvk)
    }

    @MainActor
    func testManualModeIsNeverTouchedButIsStamped() throws {
        let bottle = try makeSwitchedBottle()
        bottle.settings.launcherMode = .manual

        XCTAssertFalse(LauncherBackendMigration.migrateIfNeeded(bottle, d3dMetalInstalled: true))

        XCTAssertEqual(bottle.settings.graphicsBackend, .dxvk)
        XCTAssertFalse(bottle.settings.launcherBackendResetNotice)
        XCTAssertEqual(try persistedSettings().launcherBackendMigration, LauncherBackendMigration.current)
    }

    @MainActor
    func testWithoutD3DMetalTheBottleKeepsDXVK() throws {
        let bottle = try makeSwitchedBottle()

        XCTAssertFalse(LauncherBackendMigration.migrateIfNeeded(bottle, d3dMetalInstalled: false))

        XCTAssertEqual(bottle.settings.graphicsBackend, .dxvk)
        XCTAssertEqual(try persistedSettings().launcherBackendMigration, LauncherBackendMigration.current)
    }

    @MainActor
    func testAnOldSwitchSeenWithoutD3DMetalGoesBackOnceThePayloadArrives() throws {
        let bottle = try makeSwitchedBottle()
        XCTAssertFalse(LauncherBackendMigration.migrateIfNeeded(bottle, d3dMetalInstalled: false))

        // GPTK imported later, or the app relaunched with it deployed.
        let reloaded = Bottle(bottleUrl: bottleURL)
        XCTAssertTrue(LauncherBackendMigration.migrateIfNeeded(reloaded, d3dMetalInstalled: true))

        XCTAssertEqual(reloaded.settings.graphicsBackend, .recommended)
        XCTAssertTrue(reloaded.settings.launcherBackendResetNotice)
        XCTAssertFalse(LauncherBackendMigration.migrateIfNeeded(reloaded, d3dMetalInstalled: true))
    }

    @MainActor
    func testAProfileSwitchOnARuntimeWithoutThePayloadGoesBackOnceItArrives() throws {
        // A bottle created now, switched by today's profile because its games
        // resolve to DXMT, then GPTK is imported.
        let bottle = makeBottle()
        LauncherFixes.apply(to: bottle, launcher: .steam, recommendedBackend: .dxmt)
        XCTAssertEqual(bottle.settings.graphicsBackend, .dxvk)
        XCTAssertFalse(LauncherBackendMigration.migrateIfNeeded(bottle, d3dMetalInstalled: false))

        let reloaded = Bottle(bottleUrl: bottleURL)
        XCTAssertTrue(LauncherBackendMigration.migrateIfNeeded(reloaded, d3dMetalInstalled: true))

        XCTAssertEqual(reloaded.settings.graphicsBackend, .recommended)
        XCTAssertTrue(reloaded.settings.launcherBackendResetNotice)
        XCTAssertEqual(try persistedSettings().graphicsBackend, .recommended)
    }

    @MainActor
    func testADXVKPickedByTheUserIsNeverPutBack() {
        // Picked before Steam's profile ran: the profile leaves it alone.
        let picked = makeBottle()
        picked.settings.graphicsBackend = .dxvk
        LauncherFixes.apply(to: picked, launcher: .steam, recommendedBackend: .dxmt)
        XCTAssertFalse(LauncherBackendMigration.migrateIfNeeded(picked, d3dMetalInstalled: true))
        XCTAssertEqual(picked.settings.graphicsBackend, .dxvk)

        // Picked again after the profile switched it: the user's now.
        let repicked = makeBottle()
        LauncherFixes.apply(to: repicked, launcher: .steam, recommendedBackend: .dxmt)
        repicked.settings.graphicsBackend = .wined3d
        repicked.settings.graphicsBackend = .dxvk
        XCTAssertFalse(LauncherBackendMigration.migrateIfNeeded(repicked, d3dMetalInstalled: true))
        XCTAssertEqual(repicked.settings.graphicsBackend, .dxvk)
    }

    @MainActor
    func testAnExplicitBackendTheProfileSwitchedIsNotPutOnRecommended() {
        // It was not on Recommended before, so Recommended is not where it goes back to.
        let bottle = makeBottle()
        bottle.settings.graphicsBackend = .wined3d
        LauncherFixes.apply(to: bottle, launcher: .steam, recommendedBackend: .dxmt)
        XCTAssertEqual(bottle.settings.graphicsBackend, .dxvk)

        XCTAssertFalse(LauncherBackendMigration.migrateIfNeeded(bottle, d3dMetalInstalled: true))
        XCTAssertEqual(bottle.settings.graphicsBackend, .dxvk)
    }

    @MainActor
    func testOtherLaunchersAreNotMigrated() throws {
        let bottle = try makeSwitchedBottle()
        bottle.settings.detectedLauncher = .battleNet

        XCTAssertFalse(LauncherBackendMigration.migrateIfNeeded(bottle, d3dMetalInstalled: true))

        XCTAssertEqual(bottle.settings.graphicsBackend, .dxvk)
    }

    @MainActor
    func testAStampedBottleIsNotWrittenAgain() throws {
        let bottle = try makeSwitchedBottle()
        LauncherBackendMigration.migrateIfNeeded(bottle, d3dMetalInstalled: true)
        try FileManager.default.removeItem(at: metadataURL)

        XCTAssertFalse(LauncherBackendMigration.migrateIfNeeded(bottle, d3dMetalInstalled: true))

        XCTAssertFalse(FileManager.default.fileExists(atPath: metadataURL.path(percentEncoded: false)))
    }

    @MainActor
    func testANewBottleStartsStamped() throws {
        // A bottle created now never had the old profile applied, so a DXVK
        // choice made in it later is never mistaken for one.
        XCTAssertEqual(BottleSettings().launcherBackendMigration, LauncherBackendMigration.current)
        let bottle = makeBottle()
        try FileManager.default.removeItem(at: metadataURL)
        bottle.settings.detectedLauncher = .steam
        bottle.settings.graphicsBackend = .dxvk

        XCTAssertFalse(LauncherBackendMigration.migrateIfNeeded(bottle, d3dMetalInstalled: true))
        XCTAssertEqual(bottle.settings.graphicsBackend, .dxvk)
    }

    @MainActor
    func testSettingsFromBeforeTheMigrationDecodeUnstamped() throws {
        let bottle = makeBottle()
        bottle.settings.detectedLauncher = .steam
        // Strip the stamp the way an older version's file lacks it.
        let data = try Data(contentsOf: metadataURL)
        var plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        var launcher = try XCTUnwrap(plist["launcherConfig"] as? [String: Any])
        launcher.removeValue(forKey: "backendMigration")
        launcher.removeValue(forKey: "backendResetNotice")
        plist["launcherConfig"] = launcher
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: metadataURL)

        let decoded = try persistedSettings()

        XCTAssertEqual(decoded.launcherBackendMigration, 0)
        XCTAssertFalse(decoded.launcherBackendResetNotice)
        XCTAssertEqual(decoded.detectedLauncher, .steam)
    }
}
