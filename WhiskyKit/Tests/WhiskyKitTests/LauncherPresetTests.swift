//
//  LauncherPresetTests.swift
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

final class LauncherPresetTests: XCTestCase {
    func testSteamPresetIncludesLocale() throws {
        let env = LauncherType.steam.environmentOverrides()

        // Steam should set en_US locale to fix steamwebhelper crashes
        XCTAssertEqual(env["LC_ALL"], "en_US.UTF-8")
        XCTAssertEqual(env["LANG"], "en_US.UTF-8")

        // Should force C locale for time/numeric to avoid ICU issues
        XCTAssertEqual(env["LC_TIME"], "C")
        XCTAssertEqual(env["LC_NUMERIC"], "C")
    }

    func testSteamPresetDisablesSandbox() throws {
        let env = LauncherType.steam.environmentOverrides()

        // Steam-specific CEF sandbox disable
        XCTAssertEqual(env["STEAM_DISABLE_CEF_SANDBOX"], "1")

        // Note: CEF_DISABLE_SANDBOX is set globally in MacOSCompatibility.swift
        // for all launchers, not in individual presets. This provides single
        // point of control for the security-sensitive setting.
        XCTAssertNil(env["CEF_DISABLE_SANDBOX"], "Should be set globally, not in preset")

        // Steam runtime causes issues under Wine
        XCTAssertEqual(env["STEAM_RUNTIME"], "0")
    }

    func testSteamPresetIncludesNetworkFixes() throws {
        let env = LauncherType.steam.environmentOverrides()

        // Network timeouts are now configured via bottle.settings.networkTimeout
        // instead of directly in launcher presets. This allows user customization.
        // Verify Steam preset doesn't set them (they're set by BottleSettings)
        XCTAssertNil(env["WINHTTP_CONNECT_TIMEOUT"])
        XCTAssertNil(env["WINHTTP_RECEIVE_TIMEOUT"])

        // Steam should still set other important fixes
        XCTAssertEqual(env["STEAM_DISABLE_CEF_SANDBOX"], "1")
        XCTAssertEqual(env["DXVK_ASYNC"], "1")
    }

    func testRockstarRequiresDXVK() throws {
        let launcher = LauncherType.rockstar

        // Rockstar Launcher requires DXVK to display logo
        XCTAssertTrue(launcher.requiresDXVK)

        let env = launcher.environmentOverrides()
        XCTAssertEqual(env["DXVK_REQUIRED"], "1")
        XCTAssertEqual(env["D3DM_FORCE_D3D11"], "1")
    }

    func testEAAppRequiresGPUDetection() throws {
        let env = LauncherType.eaApp.environmentOverrides()

        // EA App needs D3D feature level reporting
        XCTAssertEqual(env["D3DM_FEATURE_LEVEL_12_1"], "1")

        // Note: CEF_DISABLE_SANDBOX is set globally in MacOSCompatibility.swift
        XCTAssertNil(env["CEF_DISABLE_SANDBOX"], "Should be set globally, not in preset")
    }

    func testEpicGamesPreset() throws {
        let env = LauncherType.epicGames.environmentOverrides()

        // Note: CEF_DISABLE_SANDBOX is set globally in MacOSCompatibility.swift
        XCTAssertNil(env["CEF_DISABLE_SANDBOX"], "Should be set globally, not in preset")

        // Epic-specific settings
        XCTAssertEqual(env["LC_ALL"], "en_US.UTF-8")
        XCTAssertEqual(env["WINE_DISABLE_NTDLL_THREAD_REGS"], "1")
        XCTAssertEqual(env["D3DM_FORCE_D3D11"], "1")
    }

    func testUbisoftPreset() throws {
        let env = LauncherType.ubisoft.environmentOverrides()

        // Ubisoft Connect requires D3D11 mode
        XCTAssertEqual(env["D3DM_FORCE_D3D11"], "1")
        XCTAssertEqual(env["DXVK_ASYNC"], "1")
    }

    func testBattleNetPreset() throws {
        let env = LauncherType.battleNet.environmentOverrides()

        // Note: CEF_DISABLE_SANDBOX is set globally in MacOSCompatibility.swift
        XCTAssertNil(env["CEF_DISABLE_SANDBOX"], "Should be set globally, not in preset")

        // Battle.net-specific settings
        XCTAssertEqual(env["LC_ALL"], "en_US.UTF-8")
        XCTAssertEqual(env["WINE_CPU_TOPOLOGY"], "8:8")
    }

    func testParadoxPreset() throws {
        let env = LauncherType.paradox.environmentOverrides()

        // Paradox Launcher resource lookup workaround
        XCTAssertEqual(env["WINE_DISABLE_FAST_PATH"], "1")
        XCTAssertEqual(env["D3DM_FORCE_D3D11"], "1")
    }

    func testRecommendedLocales() throws {
        // Steam, EA App, Epic Games, Battle.net should recommend English
        XCTAssertEqual(LauncherType.steam.recommendedLocale, .english)
        XCTAssertEqual(LauncherType.eaApp.recommendedLocale, .english)
        XCTAssertEqual(LauncherType.epicGames.recommendedLocale, .english)
        XCTAssertEqual(LauncherType.battleNet.recommendedLocale, .english)

        // Others can use auto
        XCTAssertEqual(LauncherType.rockstar.recommendedLocale, .auto)
        XCTAssertEqual(LauncherType.ubisoft.recommendedLocale, .auto)
    }

    func testFixesDescription() throws {
        // Each launcher should have a description of fixes
        for launcher in LauncherType.allCases {
            XCTAssertFalse(
                launcher.fixesDescription.isEmpty,
                "\(launcher.rawValue) should have fixes description"
            )
        }
    }

    func testLauncherTypeIdentifiable() throws {
        // LauncherType conforms to Identifiable for SwiftUI
        let launcher = LauncherType.steam
        XCTAssertEqual(launcher.id, launcher.rawValue)
    }
}
