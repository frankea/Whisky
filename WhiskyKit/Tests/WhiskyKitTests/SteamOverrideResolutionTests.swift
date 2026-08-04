//
//  SteamOverrideResolutionTests.swift
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

/// Pins the read-only contract of Play's override resolution: only persisted
/// settings decide the launch, and resolving them never writes settings
/// plists for executables that don't win.
@Suite("Steam Override Resolution Tests")
struct SteamOverrideResolutionTests {
    private let tempRoot: URL

    init() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "steamoverrides_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    /// A bottle holding a Steam install with `appId` fully installed and the
    /// given executables (install-relative paths) inside its install folder.
    private func makeGameBottle(
        appId: Int, executables: [String]
    ) throws -> (bottleURL: URL, installURL: URL) {
        let bottle = tempRoot.appending(path: "bottle-\(UUID().uuidString)")
        let steamRoot = bottle.appending(path: "drive_c")
            .appending(path: "Program Files (x86)").appending(path: "Steam")
        let steamApps = steamRoot.appending(path: "steamapps")
        try FileManager.default.createDirectory(at: steamApps, withIntermediateDirectories: true)
        try Data().write(to: steamRoot.appending(path: "steam.exe"))

        let installDir = "Game\(appId)"
        let installURL = steamApps.appending(path: "common").appending(path: installDir)
        try FileManager.default.createDirectory(at: installURL, withIntermediateDirectories: true)
        for relative in executables {
            let url = installURL.appending(path: relative)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data().write(to: url)
        }

        let manifest = """
        "AppState"
        {
            "appid"        "\(appId)"
            "name"        "Game \(appId)"
            "installdir"        "\(installDir)"
            "StateFlags"        "4"
        }
        """
        try Data(manifest.utf8).write(to: steamApps.appending(path: "appmanifest_\(appId).acf"))
        return (bottle, installURL)
    }

    /// The plist filenames currently in the bottle's Program Settings folder.
    private func settingsPlists(inBottle bottleURL: URL) -> Set<String> {
        let folder = bottleURL.appending(path: "Program Settings")
        let contents = (try? FileManager.default
            .contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        return Set(contents.filter { $0.hasSuffix(".plist") })
    }

    @Test("Resolution writes no settings plists for the losing executables")
    @MainActor func losersGetNoSettingsPlists() throws {
        let fixture = try makeGameBottle(appId: 1_245_620, executables: [
            "Game.exe", "bin/Helper.exe", "bin/UnityCrashHandler64.exe"
        ])
        let bottle = Bottle(bottleUrl: fixture.bottleURL)
        let winner = fixture.installURL.appending(path: "Game.exe")

        var tuned = ProgramOverrides()
        tuned.forceD3D11 = true
        let program = Program(url: winner, bottle: bottle, peFile: nil)
        program.settings.overrides = tuned

        let installURL = try #require(
            SteamLibrary.enumerate(bottleURL: bottle.url).first { $0.appId == 1_245_620 }?.installURL
        )
        let resolved = SteamLauncher.userOverrides(forInstallURL: installURL, bottle: bottle)

        #expect(resolved == tuned)
        // Only the winner's plist exists; the helpers never got defaults written.
        let winnerPlist = Program.settingsLocations(
            for: winner, bottleURL: bottle.url, legacyName: winner.lastPathComponent
        ).identity.lastPathComponent
        #expect(settingsPlists(inBottle: bottle.url) == [winnerPlist])
        // A real Program still reads the winner back byte-identical.
        #expect(Program(url: winner, bottle: bottle, peFile: nil).settings.overrides == tuned)
    }

    @Test("A game with nothing tuned resolves nil and writes nothing")
    @MainActor func untouchedGameResolvesNilAndWritesNothing() throws {
        let fixture = try makeGameBottle(appId: 4_576_510, executables: [
            "Game.exe", "bin/Helper.exe"
        ])
        let bottle = Bottle(bottleUrl: fixture.bottleURL)

        let resolved = SteamLauncher.userOverrides(forInstallURL: fixture.installURL, bottle: bottle)

        #expect(resolved == nil)
        #expect(settingsPlists(inBottle: bottle.url).isEmpty)
    }

    @Test("A legacy filename-keyed plist is honored in place, not migrated")
    @MainActor func legacyPlistHonoredWithoutMigration() throws {
        let fixture = try makeGameBottle(appId: 2_357_570, executables: ["bin/Helper.exe"])
        let bottle = Bottle(bottleUrl: fixture.bottleURL)
        let helper = fixture.installURL.appending(path: "bin").appending(path: "Helper.exe")

        var tuned = ProgramOverrides()
        tuned.dxvk = true
        var settings = ProgramSettings()
        settings.overrides = tuned
        let locations = Program.settingsLocations(
            for: helper, bottleURL: bottle.url, legacyName: helper.lastPathComponent
        )
        try FileManager.default.createDirectory(
            at: locations.legacy.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try settings.encode(to: locations.legacy)

        let resolved = SteamLauncher.userOverrides(forInstallURL: fixture.installURL, bottle: bottle)

        #expect(resolved == tuned)
        // Migration to the identity-keyed name stays with Program init.
        #expect(settingsPlists(inBottle: bottle.url) == [locations.legacy.lastPathComponent])
    }

    @Test("The shallowest tuned executable's overrides win")
    @MainActor func shallowestTunedExecutableWins() throws {
        let fixture = try makeGameBottle(appId: 1_086_940, executables: [
            "Game.exe", "bin/Helper.exe"
        ])
        let bottle = Bottle(bottleUrl: fixture.bottleURL)

        var deep = ProgramOverrides()
        deep.dxvk = true
        var shallow = ProgramOverrides()
        shallow.forceD3D11 = true
        let helper = Program(
            url: fixture.installURL.appending(path: "bin").appending(path: "Helper.exe"),
            bottle: bottle, peFile: nil
        )
        helper.settings.overrides = deep
        let game = Program(
            url: fixture.installURL.appending(path: "Game.exe"), bottle: bottle, peFile: nil
        )
        game.settings.overrides = shallow

        let resolved = SteamLauncher.userOverrides(forInstallURL: fixture.installURL, bottle: bottle)

        #expect(resolved == shallow)
    }

    @Test("An unreadable plist reads as no overrides and is left untouched")
    @MainActor func unreadablePlistSkippedAndLeftAlone() throws {
        let fixture = try makeGameBottle(appId: 632_360, executables: [
            "Game.exe", "bin/Helper.exe"
        ])
        let bottle = Bottle(bottleUrl: fixture.bottleURL)
        let game = fixture.installURL.appending(path: "Game.exe")

        let corruptURL = Program.settingsLocations(
            for: game, bottleURL: bottle.url, legacyName: game.lastPathComponent
        ).identity
        try FileManager.default.createDirectory(
            at: corruptURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let garbage = Data("not a plist".utf8)
        try garbage.write(to: corruptURL)

        var tuned = ProgramOverrides()
        tuned.dxvkAsync = true
        let helper = Program(
            url: fixture.installURL.appending(path: "bin").appending(path: "Helper.exe"),
            bottle: bottle, peFile: nil
        )
        helper.settings.overrides = tuned

        let resolved = SteamLauncher.userOverrides(forInstallURL: fixture.installURL, bottle: bottle)

        #expect(resolved == tuned)
        // Read-only resolution neither quarantines nor rewrites the file.
        #expect(try Data(contentsOf: corruptURL) == garbage)
    }
}
