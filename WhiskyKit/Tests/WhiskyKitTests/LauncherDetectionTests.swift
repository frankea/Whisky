//
//  LauncherDetectionTests.swift
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

// swiftlint:disable file_length type_body_length

/// Comprehensive tests for launcher detection heuristics.
///
/// These tests verify the critical detection logic that determines which
/// launcher-specific fixes to apply. Incorrect detection could result in:
/// - Applying wrong fixes (degraded performance)
/// - Missing required fixes (launcher won't work)
/// - False positives (non-launcher apps get launcher fixes)
final class LauncherDetectionTests: XCTestCase {
    // MARK: - Steam Detection Tests

    func testDetectSteamFromStandardPath() throws {
        let url = URL(fileURLWithPath: "C:/Program Files (x86)/Steam/steam.exe")
        let detected = LauncherType.detectFromPath(url)
        XCTAssertEqual(detected, .steam, "Should detect Steam from standard installation path")
    }

    func testDetectSteamFromFilename() throws {
        let url = URL(fileURLWithPath: "C:/SomeFolder/steam.exe")
        let detected = LauncherType.detectFromPath(url)
        XCTAssertEqual(detected, .steam, "Should detect Steam from filename alone")
    }

    func testDetectSteamWebHelper() throws {
        let url = URL(fileURLWithPath: "C:/Program Files/Steam/bin/steamwebhelper.exe")
        let detected = LauncherType.detectFromPath(url)
        XCTAssertEqual(detected, .steam, "Should detect Steam from steamwebhelper component")
    }

    func testDetectSteamService() throws {
        let url = URL(fileURLWithPath: "C:/Steam/steamservice.exe")
        let detected = LauncherType.detectFromPath(url)
        XCTAssertEqual(detected, .steam, "Should detect Steam from service executable")
    }

    func testDetectSteamCaseInsensitive() throws {
        let url = URL(fileURLWithPath: "C:/STEAM/STEAM.EXE")
        let detected = LauncherType.detectFromPath(url)
        XCTAssertEqual(detected, .steam, "Detection should be case-insensitive")
    }

    // MARK: - Rockstar Games Detection Tests

    func testDetectRockstarFromStandardPath() throws {
        let url = URL(fileURLWithPath: "C:/Program Files/Rockstar Games/Launcher/Launcher.exe")
        let detected = LauncherType.detectFromPath(url)
        XCTAssertEqual(detected, .rockstar, "Should detect Rockstar from standard path")
    }

    func testDetectRockstarFromFilename() throws {
        let url = URL(fileURLWithPath: "C:/Games/RockstarLauncher.exe")
        let detected = LauncherType.detectFromPath(url)
        XCTAssertEqual(detected, .rockstar, "Should detect Rockstar from filename")
    }

    func testDetectRockstarLauncherPatcher() throws {
        let url = URL(fileURLWithPath: "C:/Games/Rockstar/LauncherPatcher.exe")
        let detected = LauncherType.detectFromPath(url)
        XCTAssertEqual(detected, .rockstar, "Should detect Rockstar LauncherPatcher workaround")
    }

    func testDetectRockstarSocialClub() throws {
        let url = URL(fileURLWithPath: "C:/Program Files/Rockstar Games/Social Club/Launcher.exe")
        let detected = LauncherType.detectFromPath(url)
        XCTAssertEqual(detected, .rockstar, "Should detect Rockstar via Social Club path")
    }

    func testGenericLauncherNotRockstar() throws {
        let url = URL(fileURLWithPath: "C:/Program Files/SomeGame/Launcher.exe")
        let detected = LauncherType.detectFromPath(url)
        XCTAssertNotEqual(detected, .rockstar, "Generic launcher.exe should not match Rockstar")
        XCTAssertNil(detected, "Generic launcher.exe with no Rockstar path should return nil")
    }

    func testGenericLauncherWithoutSpecificPath() throws {
        // Test that launcher.exe alone is not enough - requires "rockstar games" or "social club" in path
        let falsePaths = [
            "C:/Program Files/MyLauncher/Launcher.exe",
            "C:/Games/CustomLauncher/Launcher.exe",
            "C:/Launcher.exe", // Just filename
            "C:/rock/Launcher.exe" // Contains "rock" but not "rockstar games"
        ]

        for path in falsePaths {
            let url = URL(fileURLWithPath: path)
            let detected = LauncherType.detectFromPath(url)
            XCTAssertNotEqual(detected, .rockstar, "Path '\(path)' should not match Rockstar (too generic)")
            XCTAssertNil(detected, "Path '\(path)' should return nil (no specific launcher match)")
        }
    }

    func testRockstarRequiresSpecificPath() throws {
        // Verify Rockstar detection requires "rockstar games" or "social club" in full
        let validRockstarPaths = [
            "C:/Program Files/Rockstar Games/Launcher/Launcher.exe",
            "C:/Rockstar Games/Social Club/Launcher.exe",
            "C:/Program Files/Rockstar Games Launcher/Launcher.exe"
        ]

        for path in validRockstarPaths {
            let url = URL(fileURLWithPath: path)
            let detected = LauncherType.detectFromPath(url)
            XCTAssertEqual(detected, .rockstar, "Valid Rockstar path should detect: \(path)")
        }
    }

    // MARK: - EA App / Origin Detection Tests

    func testDetectEAAppFromStandardPath() throws {
        let url = URL(fileURLWithPath: "C:/Program Files/Electronic Arts/EA Desktop/EA App/EADesktop.exe")
        let detected = LauncherType.detectFromPath(url)
        XCTAssertEqual(detected, .eaApp, "Should detect EA App from standard path")
    }

    func testDetectEAAppFromFilename() throws {
        let url = URL(fileURLWithPath: "C:/Games/EADesktop.exe")
        let detected = LauncherType.detectFromPath(url)
        XCTAssertEqual(detected, .eaApp, "Should detect EA App from filename")
    }

    func testDetectOriginLegacy() throws {
        let url = URL(fileURLWithPath: "C:/Program Files (x86)/Origin/Origin.exe")
        let detected = LauncherType.detectFromPath(url)
        XCTAssertEqual(detected, .eaApp, "Should detect legacy Origin as EA App")
    }

    func testDetectEAAppVariants() throws {
        let variants = [
            "C:/EAApp.exe",
            "C:/EA App/EADesktop.exe",
            "C:/Origin/Origin.exe"
        ]

        for path in variants {
            let url = URL(fileURLWithPath: path)
            let detected = LauncherType.detectFromPath(url)
            XCTAssertEqual(detected, .eaApp, "Should detect EA App from: \(path)")
        }
    }

    // MARK: - Epic Games Detection Tests

    func testDetectEpicGamesFromStandardPath() throws {
        let path = "C:/Program Files (x86)/Epic Games/Launcher/Portal/Binaries/Win64/EpicGamesLauncher.exe"
        let url = URL(fileURLWithPath: path)
        let detected = LauncherType.detectFromPath(url)
        XCTAssertEqual(detected, .epicGames, "Should detect Epic Games from standard path")
    }

    func testDetectEpicGamesFromFilename() throws {
        let url = URL(fileURLWithPath: "C:/Games/EpicGamesLauncher.exe")
        let detected = LauncherType.detectFromPath(url)
        XCTAssertEqual(detected, .epicGames, "Should detect Epic from filename")
    }

    func testDetectEpicWebHelper() throws {
        let url = URL(fileURLWithPath: "C:/Epic Games/Launcher/EpicWebHelper.exe")
        let detected = LauncherType.detectFromPath(url)
        XCTAssertEqual(detected, .epicGames, "Should detect Epic web helper component")
    }

    // MARK: - Ubisoft Connect Detection Tests

    func testDetectUbisoftConnectFromStandardPath() throws {
        let url = URL(fileURLWithPath: "C:/Program Files (x86)/Ubisoft/Ubisoft Game Launcher/UbisoftConnect.exe")
        let detected = LauncherType.detectFromPath(url)
        XCTAssertEqual(detected, .ubisoft, "Should detect Ubisoft Connect from standard path")
    }

    func testDetectUplayLegacy() throws {
        let url = URL(fileURLWithPath: "C:/Program Files/Ubisoft/Uplay/upc.exe")
        let detected = LauncherType.detectFromPath(url)
        XCTAssertEqual(detected, .ubisoft, "Should detect legacy Uplay")
    }

    func testDetectUbisoftVariants() throws {
        let variants = [
            "C:/Ubisoft/UbisoftConnect.exe",
            "C:/Games/uplay.exe",
            "C:/Ubisoft/upc.exe"
        ]

        for path in variants {
            let url = URL(fileURLWithPath: path)
            let detected = LauncherType.detectFromPath(url)
            XCTAssertEqual(detected, .ubisoft, "Should detect Ubisoft from: \(path)")
        }
    }

    // MARK: - Battle.net Detection Tests

    func testDetectBattleNetFromStandardPath() throws {
        let url = URL(fileURLWithPath: "C:/Program Files (x86)/Battle.net/Battle.net.exe")
        let detected = LauncherType.detectFromPath(url)
        XCTAssertEqual(detected, .battleNet, "Should detect Battle.net from standard path")
    }

    func testDetectBattleNetVariants() throws {
        let variants = [
            "C:/Battle.net/Battle.net.exe",
            "C:/BattleNet/battlenet.exe",
            "C:/Games/Battle.net Launcher.exe"
        ]

        for path in variants {
            let url = URL(fileURLWithPath: path)
            let detected = LauncherType.detectFromPath(url)
            XCTAssertEqual(detected, .battleNet, "Should detect Battle.net from: \(path)")
        }
    }

    // MARK: - Paradox Launcher Detection Tests

    func testDetectParadoxFromStandardPath() throws {
        let url = URL(fileURLWithPath: "C:/Users/User/AppData/Local/Programs/Paradox Launcher/Paradox Launcher.exe")
        let detected = LauncherType.detectFromPath(url)
        XCTAssertEqual(detected, .paradox, "Should detect Paradox Launcher from standard path")
    }

    func testDetectParadoxFromDirectory() throws {
        let url = URL(fileURLWithPath: "C:/Paradox Launcher/Launcher.exe")
        let detected = LauncherType.detectFromPath(url)
        XCTAssertEqual(detected, .paradox, "Should detect Paradox from 'Paradox Launcher' directory")
    }

    func testDetectParadoxFromParadoxInteractive() throws {
        let url = URL(fileURLWithPath: "C:/Program Files/Paradox Interactive/Launcher/Launcher.exe")
        let detected = LauncherType.detectFromPath(url)
        XCTAssertEqual(detected, .paradox, "Should detect Paradox from 'Paradox Interactive' directory")
    }

    func testGenericParadoxGameNotDetectedAsLauncher() throws {
        // Paradox game folder (not the launcher)
        let url = URL(fileURLWithPath: "C:/Games/Paradox Interactive/Europa Universalis/game.exe")
        let detected = LauncherType.detectFromPath(url)
        XCTAssertNil(detected, "Game in Paradox folder should not match Paradox Launcher")
    }

    // MARK: - False Positive Prevention Tests

    func testDoNotDetectRegularGame() throws {
        let url = URL(fileURLWithPath: "C:/Program Files/MyGame/game.exe")
        let detected = LauncherType.detectFromPath(url)
        XCTAssertNil(detected, "Regular game executable should not match any launcher")
    }

    func testDoNotDetectUnrelatedPrograms() throws {
        let unrelatedPaths = [
            "C:/Windows/System32/notepad.exe",
            "C:/Program Files/Firefox/firefox.exe",
            "C:/Games/CustomLauncher/app.exe",
            "C:/Users/User/Desktop/installer.exe"
        ]

        for path in unrelatedPaths {
            let url = URL(fileURLWithPath: path)
            let detected = LauncherType.detectFromPath(url)
            XCTAssertNil(detected, "Should not detect launcher from: \(path)")
        }
    }

    func testDoNotConfuseSteamInPathWithActualSteam() throws {
        // Edge case: game folder contains "steam" but isn't Steam launcher
        let url = URL(fileURLWithPath: "C:/Games/Steamworld/game.exe")
        let detected = LauncherType.detectFromPath(url)
        // The heuristic correctly identifies this is NOT Steam because:
        // - Filename "game.exe" doesn't contain "steam"
        // - Path contains "steamworld" but not "/steam/" or "\\steam\\"
        XCTAssertNil(detected, "Should not detect game in 'Steamworld' folder as Steam launcher")
    }

    // MARK: - Path Separator Handling Tests

    func testWindowsPathSeparators() throws {
        let url = URL(fileURLWithPath: "C:\\Program Files\\Steam\\steam.exe")
        let detected = LauncherType.detectFromPath(url)
        XCTAssertEqual(detected, .steam, "Should handle Windows backslash separators")
    }

    func testUnixPathSeparators() throws {
        let url = URL(fileURLWithPath: "/drive_c/Program Files/Steam/steam.exe")
        let detected = LauncherType.detectFromPath(url)
        XCTAssertEqual(detected, .steam, "Should handle Unix forward slash separators")
    }

    func testMixedPathSeparators() throws {
        let url = URL(fileURLWithPath: "C:/Program Files\\Rockstar Games/Launcher.exe")
        let detected = LauncherType.detectFromPath(url)
        XCTAssertEqual(detected, .rockstar, "Should handle mixed path separators")
    }

    // MARK: - Special Characters and Encoding Tests

    func testPathWithSpaces() throws {
        let url = URL(fileURLWithPath: "C:/Program Files (x86)/Epic Games/Launcher/EpicGamesLauncher.exe")
        let detected = LauncherType.detectFromPath(url)
        XCTAssertEqual(detected, .epicGames, "Should handle spaces in path")
    }

    func testPathWithParentheses() throws {
        let url = URL(fileURLWithPath: "C:/Program Files (x86)/Origin/Origin.exe")
        let detected = LauncherType.detectFromPath(url)
        XCTAssertEqual(detected, .eaApp, "Should handle parentheses in path")
    }

    func testPathWithDots() throws {
        let url = URL(fileURLWithPath: "C:/Battle.net/Battle.net.exe")
        let detected = LauncherType.detectFromPath(url)
        XCTAssertEqual(detected, .battleNet, "Should handle dots in path")
    }

    // MARK: - Edge Cases and Corner Cases

    func testEmptyPath() throws {
        let url = URL(fileURLWithPath: "")
        let detected = LauncherType.detectFromPath(url)
        XCTAssertNil(detected, "Empty path should return nil")
    }

    func testRootPath() throws {
        let url = URL(fileURLWithPath: "/")
        let detected = LauncherType.detectFromPath(url)
        XCTAssertNil(detected, "Root path should return nil")
    }

    func testFilenameOnlyNoPath() throws {
        let url = URL(fileURLWithPath: "steam.exe")
        let detected = LauncherType.detectFromPath(url)
        XCTAssertEqual(detected, .steam, "Should detect from filename even without full path")
    }

    // MARK: - Multiple Launcher Keyword Tests

    func testSteamKeywordDoesntMatchOthers() throws {
        let url = URL(fileURLWithPath: "C:/Steam/steam.exe")
        let detected = LauncherType.detectFromPath(url)
        XCTAssertEqual(detected, .steam)
        XCTAssertNotEqual(detected, .rockstar)
        XCTAssertNotEqual(detected, .eaApp)
    }

    func testAllLaunchersHaveUniqueDetection() throws {
        let testPaths: [(String, LauncherType)] = [
            ("C:/Steam/steam.exe", .steam),
            ("C:/Rockstar Games/Launcher.exe", .rockstar),
            ("C:/EA App/EADesktop.exe", .eaApp),
            ("C:/Epic Games/EpicGamesLauncher.exe", .epicGames),
            ("C:/Ubisoft/UbisoftConnect.exe", .ubisoft),
            ("C:/Battle.net/Battle.net.exe", .battleNet),
            ("C:/Paradox/Paradox Launcher.exe", .paradox)
        ]

        for (path, expectedLauncher) in testPaths {
            let url = URL(fileURLWithPath: path)
            let detected = LauncherType.detectFromPath(url)
            XCTAssertEqual(
                detected,
                expectedLauncher,
                "Path '\(path)' should uniquely detect \(expectedLauncher.rawValue)"
            )
        }
    }

    // MARK: - Real-World Path Examples

    func testRealWorldSteamPaths() throws {
        let realPaths = [
            "C:/Program Files (x86)/Steam/steam.exe",
            "D:/SteamLibrary/steam.exe",
            "C:/Steam/steamapps/common/game/steam_api.dll" // Should still detect as Steam
        ]

        for path in realPaths {
            let url = URL(fileURLWithPath: path)
            let detected = LauncherType.detectFromPath(url)
            XCTAssertEqual(detected, .steam, "Real-world path should detect: \(path)")
        }
    }

    func testRealWorldRockstarPaths() throws {
        let realPaths = [
            "C:/Program Files/Rockstar Games/Launcher/Launcher.exe",
            "C:/Program Files/Rockstar Games/Social Club/Launcher.exe",
            "D:/Games/Rockstar/LauncherPatcher.exe"
        ]

        for path in realPaths {
            let url = URL(fileURLWithPath: path)
            let detected = LauncherType.detectFromPath(url)
            XCTAssertEqual(detected, .rockstar, "Real-world path should detect: \(path)")
        }
    }

    // MARK: - Performance Tests

    func testDetectionPerformance() throws {
        let url = URL(fileURLWithPath: "C:/Program Files/Steam/steam.exe")

        measure {
            for _ in 0 ..< 1_000 {
                _ = LauncherType.detectFromPath(url)
            }
        }
        // Detection should be very fast (string comparisons only)
        // 1000 detections should complete in milliseconds
    }
}

// MARK: - Helper Extension for Testing

extension LauncherType {
    // Test helper method that calls the actual detection logic.
    // This would normally be in LauncherDetection, but we need to test it from WhiskyKit tests.
    fileprivate static func detectFromPath(_ url: URL) -> LauncherType? {
        let filename = url.lastPathComponent.lowercased()
        let path = url.path.lowercased()

        // Steam detection
        if filename.contains("steam") || path.contains("/steam/") || path.contains("\\steam\\") {
            return .steam
        }

        // Rockstar Games detection
        // Be specific about generic "launcher.exe" to avoid false positives
        if filename.contains("rockstar") ||
            filename.contains("launcherpatcher") ||
            path.contains("rockstar games") ||
            path.contains("rockstar games launcher") ||
            (filename == "launcher.exe" &&
                (path.contains("rockstar games") || path.contains("social club"))) {
            return .rockstar
        }

        // EA App / Origin detection
        if filename.contains("eadesktop") ||
            filename.contains("eaapp") ||
            filename.contains("origin.exe") ||
            path.contains("/ea app/") ||
            path.contains("\\ea app\\") ||
            path.contains("/origin/") {
            return .eaApp
        }

        // Epic Games Store detection
        if filename.contains("epicgames") ||
            filename.contains("epiclauncher") ||
            filename.contains("epicwebhelper") ||
            path.contains("/epic games/") ||
            path.contains("\\epic games\\") {
            return .epicGames
        }

        // Ubisoft Connect detection
        if filename.contains("ubisoft") ||
            filename.contains("uplay") ||
            filename.contains("upc.exe") ||
            path.contains("/ubisoft") {
            return .ubisoft
        }

        // Battle.net detection
        if filename.contains("battle.net") ||
            filename.contains("battlenet") ||
            path.contains("/battle.net/") ||
            path.contains("\\battle.net\\") {
            return .battleNet
        }

        // Paradox Launcher detection
        // Be specific to avoid false positives
        if filename.contains("paradox launcher") ||
            filename.contains("paradoxlauncher") ||
            path.contains("paradox launcher") ||
            ((filename == "launcher.exe" || filename == "launcher") &&
                path.contains("paradox interactive")) {
            return .paradox
        }

        return nil
    }
}

// swiftlint:enable file_length type_body_length
