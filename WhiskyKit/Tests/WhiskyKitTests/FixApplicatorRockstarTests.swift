//
//  FixApplicatorRockstarTests.swift
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

/// Apply Launcher Fixes for Rockstar's launcher in a bottle with Steam, where
/// Rockstar's profile never lands (#382).
@MainActor
final class FixApplicatorRockstarTests: XCTestCase {
    private var tempDir: URL!
    private var bottle: Bottle!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let steam = tempDir.appending(path: "drive_c/Program Files (x86)/Steam")
        try FileManager.default.createDirectory(at: steam, withIntermediateDirectories: true)
        try Data("MZ".utf8).write(to: steam.appending(path: "steam.exe"))
        bottle = Bottle(bottleUrl: tempDir, inFlight: false, isAvailable: true)
    }

    override func tearDownWithError() throws {
        bottle = nil
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        tempDir = nil
    }

    private var rockstarLauncher: Program {
        Program(
            url: tempDir.appending(path: "drive_c/Program Files/Rockstar Games/Launcher/Launcher.exe"),
            bottle: bottle
        )
    }

    private func applyLauncherFixes(program: Program) -> FixAttempt {
        FixApplicator.apply(fixId: "apply-launcher-fixes", params: [:], bottle: bottle, program: program)
    }

    func testRockstarInASteamBottleReappliesSteamsSettings() throws {
        // The fix names and reapplies the profile that lands, Steam's, instead
        // of reporting Rockstar's as applied.
        let preview = try XCTUnwrap(FixApplicator.preview(
            fixId: "apply-launcher-fixes", params: [:], bottle: bottle, program: rockstarLauncher
        ))
        XCTAssertEqual(preview.currentValue, LauncherType.steam.displayName)

        let attempt = applyLauncherFixes(program: rockstarLauncher)

        XCTAssertEqual(attempt.result, .applied)
        XCTAssertEqual(attempt.afterValue, LauncherType.steam.rawValue)
        XCTAssertEqual(bottle.settings.detectedLauncher, .steam)
        XCTAssertTrue(bottle.settings.launcherCompatibilityMode)
        // With or without the payload, Recommended stays: a Steam start in a
        // bottle set up for Steam never moves it either.
        XCTAssertEqual(bottle.settings.graphicsBackend, .recommended)
        XCTAssertFalse(bottle.settings.launcherSwitchedBackend)
    }

    func testRockstarInASteamBottleKeepsAnExplicitBackend() {
        // A forced Steam apply put these on bottle-wide DXVK, unmarked, and
        // nothing ever put them back.
        for backend in [GraphicsBackend.d3dMetal, .dxmt, .wined3d] {
            bottle.settings.launcherCompatibilityMode = true
            bottle.settings.detectedLauncher = .steam
            bottle.settings.graphicsBackend = backend

            let attempt = applyLauncherFixes(program: rockstarLauncher)

            XCTAssertEqual(attempt.result, .applied, "\(backend)")
            XCTAssertEqual(bottle.settings.graphicsBackend, backend, "\(backend)")
            XCTAssertFalse(bottle.settings.dxvk, "\(backend)")
        }
    }

    func testDetectedRockstarInAnAutoSteamBottleKeepsAnExplicitBackend() {
        // The bottle's detected launcher stands in for a program that is not a
        // launcher, and gets the same treatment.
        bottle.settings.detectedLauncher = .rockstar
        bottle.settings.graphicsBackend = .d3dMetal
        let game = Program(url: tempDir.appending(path: "drive_c/Games/foo.exe"), bottle: bottle)

        let attempt = applyLauncherFixes(program: game)

        XCTAssertEqual(attempt.result, .applied)
        XCTAssertEqual(bottle.settings.detectedLauncher, .steam)
        XCTAssertEqual(bottle.settings.graphicsBackend, .d3dMetal)
    }

    func testManualRockstarChoiceInASteamBottleIsLeftAlone() throws {
        // The Launcher Type the user picked is never swapped for Steam, and
        // the fix does not report a profile as applied that never landed.
        bottle.settings.launcherMode = .manual
        bottle.settings.detectedLauncher = .rockstar
        bottle.settings.graphicsBackend = .wined3d
        let compatibilityBefore = bottle.settings.launcherCompatibilityMode

        for program in [
            rockstarLauncher,
            Program(url: tempDir.appending(path: "drive_c/Games/foo.exe"), bottle: bottle)
        ] {
            let preview = try XCTUnwrap(FixApplicator.preview(
                fixId: "apply-launcher-fixes", params: [:], bottle: bottle, program: program
            ))
            XCTAssertEqual(preview.currentValue, LauncherType.rockstar.displayName)

            let attempt = applyLauncherFixes(program: program)

            XCTAssertEqual(attempt.result, .failed)
            XCTAssertNil(attempt.afterValue)
            XCTAssertEqual(bottle.settings.launcherMode, .manual)
            XCTAssertEqual(bottle.settings.detectedLauncher, .rockstar)
            XCTAssertEqual(bottle.settings.graphicsBackend, .wined3d)
            XCTAssertEqual(bottle.settings.launcherCompatibilityMode, compatibilityBefore)
        }
    }

    func testSteamItselfStillGetsTheForcedProfile() {
        // Only the Rockstar redirect skips the backend step: Apply Launcher
        // Fixes on steam.exe keeps its forced profile.
        bottle.settings.graphicsBackend = .wined3d
        let steam = Program(
            url: tempDir.appending(path: "drive_c/Program Files (x86)/Steam/steam.exe"), bottle: bottle
        )

        let attempt = applyLauncherFixes(program: steam)

        XCTAssertEqual(attempt.result, .applied)
        XCTAssertEqual(bottle.settings.detectedLauncher, .steam)
        XCTAssertTrue(bottle.settings.dxvk)
    }
}
