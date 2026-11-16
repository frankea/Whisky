//
//  LauncherFixesRockstarTests.swift
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

// MARK: - Rockstar in a bottle with Steam (#382)

/// The Rockstar profile is bottle-wide DXVK, which a bottle with Steam never
/// gets: its games run on D3DMetal.
final class LauncherFixesRockstarTests: LauncherFixesTestCase {
    /// Rockstar's launcher, which ``LauncherType/detect(from:)`` resolves to Rockstar.
    let rockstarExe = URL(fileURLWithPath: "C:/Program Files/Rockstar Games/Launcher/Launcher.exe")

    @MainActor
    func testRockstarLaunchDoesNotTakeASteamBottleOffD3DMetal() throws {
        // Rockstar's launcher from the Programs tab used to replace Steam's
        // profile and switch the bottle to DXVK, taking GTA V Enhanced and every
        // other Steam game off D3DMetal (#382).
        let bottle = makeBottle()
        bottle.settings.launcherCompatibilityMode = true
        bottle.settings.detectedLauncher = .steam

        XCTAssertFalse(LauncherFixes.detectAndApply(from: rockstarExe, for: bottle))

        XCTAssertEqual(bottle.settings.detectedLauncher, .steam)
        XCTAssertEqual(bottle.settings.graphicsBackend, .recommended)
        XCTAssertEqual(try persistedSettings().graphicsBackend, .recommended)
    }

    @MainActor
    func testRockstarLaunchLeavesABottleWithSteamInstalledAlone() throws {
        try installSteam()
        let bottle = makeBottle()
        bottle.settings.launcherCompatibilityMode = true

        XCTAssertFalse(LauncherFixes.detectAndApply(from: rockstarExe, for: bottle))

        XCTAssertNil(bottle.settings.detectedLauncher)
        XCTAssertEqual(bottle.settings.graphicsBackend, .recommended)
    }

    /// The overrides every program in `bottle` runs with, over D3DMetal.
    @MainActor
    func bottleOverrides(_ bottle: Bottle) -> String {
        Wine.constructWineEnvironment(
            for: bottle, recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: true
        )["WINEDLLOVERRIDES"] ?? ""
    }

    @MainActor
    func testRockstarProfileKeepsABottleWithSteamOffDXVK() throws {
        // Applied directly (troubleshooting's forced Apply Launcher Fixes, or
        // manual selection), the profile never reaches a bottle with Steam:
        // Rockstar as the detected launcher would add the DXVK preset to the
        // bottle's overrides, and so to every Steam game's plan.
        try installSteam()
        let bottle = makeBottle()
        let before = bottleOverrides(bottle)
        let compatibilityBefore = bottle.settings.launcherCompatibilityMode

        for force in [false, true] {
            LauncherFixes.apply(to: bottle, launcher: .rockstar, force: force, recommendedBackend: .d3dMetal)

            XCTAssertNil(bottle.settings.detectedLauncher)
            XCTAssertEqual(bottle.settings.graphicsBackend, .recommended)
            XCTAssertFalse(bottle.settings.dxvk)
            XCTAssertEqual(bottleOverrides(bottle), before)
        }
        // Nothing in the bottle's settings changes, compatibility mode included.
        XCTAssertEqual(bottle.settings.launcherCompatibilityMode, compatibilityBefore)
        XCTAssertEqual(try persistedSettings().launcherCompatibilityMode, compatibilityBefore)
        XCTAssertNil(try persistedSettings().detectedLauncher)
    }

    @MainActor
    func testForcedRockstarFixesKeepASteamTunedBottleOnSteam() {
        // Tuned for Steam, with no client installed yet: still a Steam bottle.
        let bottle = makeBottle()
        bottle.settings.launcherCompatibilityMode = true
        bottle.settings.detectedLauncher = .steam
        let before = bottleOverrides(bottle)

        LauncherFixes.apply(to: bottle, launcher: .rockstar, force: true, recommendedBackend: .d3dMetal)

        XCTAssertEqual(bottle.settings.detectedLauncher, .steam)
        XCTAssertFalse(bottle.settings.dxvk)
        XCTAssertEqual(bottleOverrides(bottle), before)
    }

    @MainActor
    func testRockstarStillAppliesInABottleWithoutSteam() {
        let bottle = makeBottle()
        bottle.settings.launcherCompatibilityMode = true

        XCTAssertTrue(LauncherFixes.detectAndApply(from: rockstarExe, for: bottle))

        XCTAssertEqual(bottle.settings.detectedLauncher, .rockstar)
        XCTAssertTrue(bottle.settings.dxvk)
    }

    @MainActor
    func testSteamSettingsForRockstarRestoreOnlyAProfilesDXVK() throws {
        // What Apply Launcher Fixes reapplies for Rockstar in a Steam bottle:
        // a DXVK a profile switched to goes back to Recommended over D3DMetal.
        try installSteam()
        let bottle = makeBottle()
        bottle.settings.detectedLauncher = .rockstar
        bottle.settings.graphicsBackend = .dxvk
        bottle.settings.launcherSwitchedBackend = true

        LauncherFixes.reapplySteamSettings(to: bottle, recommendedBackend: .d3dMetal)

        XCTAssertEqual(bottle.settings.detectedLauncher, .steam)
        XCTAssertTrue(bottle.settings.launcherCompatibilityMode)
        XCTAssertEqual(bottle.settings.graphicsBackend, .recommended)
        XCTAssertTrue(bottle.settings.launcherBackendResetNotice)
        XCTAssertEqual(try persistedSettings().graphicsBackend, .recommended)
    }

    @MainActor
    func testSteamSettingsForRockstarKeepEveryOtherBackend() throws {
        try installSteam()
        let bottle = makeBottle()

        // Without the payload a profile's DXVK stays, and Recommended is never
        // moved to DXVK.
        bottle.settings.graphicsBackend = .dxvk
        bottle.settings.launcherSwitchedBackend = true
        LauncherFixes.reapplySteamSettings(to: bottle, recommendedBackend: .dxmt)
        XCTAssertEqual(bottle.settings.graphicsBackend, .dxvk)

        bottle.settings.graphicsBackend = .recommended
        LauncherFixes.reapplySteamSettings(to: bottle, recommendedBackend: .dxmt)
        XCTAssertEqual(bottle.settings.graphicsBackend, .recommended)
        XCTAssertFalse(bottle.settings.launcherSwitchedBackend)

        // A DXVK the user picked stays over D3DMetal too.
        bottle.settings.graphicsBackend = .dxvk
        LauncherFixes.reapplySteamSettings(to: bottle, recommendedBackend: .d3dMetal)
        XCTAssertEqual(bottle.settings.graphicsBackend, .dxvk)
        XCTAssertEqual(try persistedSettings().graphicsBackend, .dxvk)
    }
}
