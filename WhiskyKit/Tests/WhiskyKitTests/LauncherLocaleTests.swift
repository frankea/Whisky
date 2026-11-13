//
//  LauncherLocaleTests.swift
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
import Testing
@testable import WhiskyKit

/// The launcher presets whose environment sets `LC_ALL`.
private let presetsWithLocale: [LauncherType] = LauncherType.allCases.filter {
    $0.environmentOverrides()["LC_ALL"] != nil
}

/// Resolves the launcher layer of a bottle in compatibility mode.
private func launcherEnvironment(
    _ launcher: LauncherType?, locale: Locales
) -> (environment: [String: String], provenance: EnvironmentProvenance) {
    var settings = BottleSettings()
    settings.launcherCompatibilityMode = true
    settings.detectedLauncher = launcher
    settings.launcherLocale = locale
    var builder = EnvironmentBuilder()
    _ = settings.populateLauncherManagedLayer(builder: &builder, builtinD3D12IsD3DMetal: false)
    return builder.resolve()
}

@Suite("Launcher locale override (#330)")
struct LauncherLocaleTests {
    @Test("The presets that set a locale are the four Chromium launchers other than Steam")
    func presetsSettingALocale() {
        #expect(Set(presetsWithLocale) == [.rockstar, .eaApp, .epicGames, .battleNet])
    }

    @Test("A Steam bottle on Auto leaves the locale to the Mac")
    func steamAutoFollowsTheMac() {
        let env = launcherEnvironment(.steam, locale: .auto).environment
        for key in ["LC_ALL", "LANG", "LC_TIME", "LC_NUMERIC"] {
            #expect(env[key] == nil, "\(key)")
        }
    }

    @Test("A full Steam launch on Auto carries no locale variables")
    @MainActor
    func steamAutoFullLaunch() {
        let bottle = Bottle(bottleUrl: FileManager.default.temporaryDirectory.appending(path: "steam_locale"))
        bottle.settings.launcherCompatibilityMode = true
        bottle.settings.detectedLauncher = .steam
        let env = Wine.constructWineEnvironment(for: bottle, builtinD3D12IsD3DMetal: false)
        for key in ["LC_ALL", "LANG", "LC_TIME", "LC_NUMERIC"] {
            #expect(env[key] == nil, "\(key)")
        }
        // The rest of the Steam preset still applies.
        #expect(env["STEAM_DISABLE_CEF_SANDBOX"] == "1")
    }

    @Test("A Steam bottle set to Japanese resolves the Japanese locale")
    func steamJapanese() {
        let env = launcherEnvironment(.steam, locale: .japanese).environment
        #expect(env["LC_ALL"] == "ja_JP.UTF-8")
        #expect(env["LANG"] == "ja_JP.UTF-8")
        // The ICU workaround stays.
        #expect(env["LC_TIME"] == "C")
        #expect(env["LC_NUMERIC"] == "C")
    }

    @Test("An explicit locale wins over every preset's en_US", arguments: presetsWithLocale)
    func explicitLocaleWins(_ launcher: LauncherType) {
        let env = launcherEnvironment(launcher, locale: .korean).environment
        #expect(env["LC_ALL"] == "ko_KR.UTF-8")
        #expect(env["LANG"] == "ko_KR.UTF-8")
    }

    @Test("Auto keeps the preset's locale", arguments: presetsWithLocale)
    func autoKeepsPreset(_ launcher: LauncherType) {
        let env = launcherEnvironment(launcher, locale: .auto).environment
        #expect(env["LC_ALL"] == "en_US.UTF-8")
    }

    @Test("Auto with no launcher leaves the locale to the Mac")
    func autoWithoutLauncher() {
        let env = launcherEnvironment(nil, locale: .auto).environment
        #expect(env["LC_ALL"] == nil)
        #expect(env["LANG"] == nil)
    }

    @Test("The overridden locale is attributed to the override, not the preset")
    func provenanceNamesTheOverride() throws {
        let provenance = launcherEnvironment(.steam, locale: .japanese).provenance
        let entry = try #require(provenance.entries["LC_ALL"])
        #expect(entry.reason == "Set by the bottle's Locale Override")
    }

    @Test("Applying launcher fixes keeps the user's locale", arguments: LauncherType.allCases)
    @MainActor
    func applyKeepsTheLocale(_ launcher: LauncherType) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "launcher_locale_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let bottleURL = root.appending(path: "Bottle")
        try FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)

        for locale in [Locales.auto, .japanese] {
            let bottle = Bottle(bottleUrl: bottleURL)
            bottle.settings.launcherLocale = locale

            // Steam's orchestrator applies the fixes on every client start.
            LauncherFixes.apply(to: bottle, launcher: launcher, recommendedBackend: .d3dMetal)
            LauncherFixes.apply(to: bottle, launcher: launcher, force: true, recommendedBackend: .d3dMetal)

            #expect(bottle.settings.launcherLocale == locale)
            let persisted = try BottleSettings.decode(from: bottleURL.appending(path: "Metadata.plist"))
            #expect(persisted.launcherLocale == locale)
        }
    }
}
