//
//  RockstarSocialClubPrecreationTests.swift
//  WhiskyKit
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

/// Social Club's folder, made ahead of the Rockstar Games Launcher's first
/// start: the launcher installs Social Club itself then, and its sign-in
/// window stays blank unless DXVK is already beside `SocialClubHelper.exe`.
/// Rockstar's installer leaves the two copies in place (#382).
@Suite("Rockstar Social Club pre-creation")
@MainActor
final class RockstarSocialClubPrecreationTests {
    private let fixture: RockstarD3DFixture
    private let root: URL

    init() throws {
        fixture = try RockstarD3DFixture(prefix: "rockstar_social_club")
        root = fixture.root
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    private var rockstarGames: URL {
        fixture.driveC.appending(path: "Program Files/Rockstar Games")
    }

    /// The first `-applaunch` of a Rockstar title, before its launcher is installed.
    private func firstRun() throws -> RockstarD3DLayout? {
        try fixture.startSteam(descendants: [.rockstar])
    }

    @Test("A Rockstar title's first run creates Social Club's folder with DXVK in it and records both folders")
    func firstRunCreatesSocialClub() throws {
        #expect(!RockstarD3DFixture.exists(rockstarGames))

        #expect(try firstRun() == .swapped(source: fixture.d3d11Source))

        #expect(RockstarD3DFixture.holdsDXVKCopies(fixture.socialClub))
        let entries = try FileManager.default
            .contentsOfDirectory(atPath: fixture.socialClub.path(percentEncoded: false))
        #expect(entries.sorted() == ["d3d10core.dll", "d3d11.dll"])
        #expect(fixture.record?.createdFolders == [RockstarD3DFixture.socialClubKey, "Program Files/Rockstar Games"])
    }

    @Test("Without Steam starting a Rockstar title, a bottle without Rockstar gets no folder")
    func noRockstarNoFolder() throws {
        #expect(try fixture.startSteam() == nil)

        #expect(!RockstarD3DFixture.exists(rockstarGames))
        #expect(!RockstarD3DLayoutRecord.exists(in: fixture.bottle.url))
    }

    @Test("The copies survive Rockstar's installer filling the folder, and stay current after")
    func copiesSurviveTheInstaller() throws {
        try firstRun()
        // What Social-Club-Setup.exe /silent /forceinstall writes around them.
        try fixture.installRockstar()
        try fixture.write(Data("cef".utf8), to: fixture.socialClub.appending(path: "libcef.dll"))

        #expect(try fixture.startSteam() == .swapped(source: fixture.d3d11Source))

        #expect(RockstarD3DFixture.holdsDXVKCopies(fixture.socialClub))
        #expect(RockstarD3DFixture.exists(fixture.socialClub.appending(path: "SocialClubHelper.exe")))
    }

    @Test("A teardown keeps the folders once Rockstar's installer filled them")
    func teardownKeepsAFilledFolder() throws {
        try firstRun()
        try fixture.installRockstar()
        fixture.bottle.settings.rockstarWineD3D = false

        try fixture.startSteam()

        #expect(RockstarD3DFixture.holdsNoCopies(fixture.socialClub))
        #expect(RockstarD3DFixture.exists(fixture.socialClub.appending(path: "SocialClubHelper.exe")))
        #expect(RockstarD3DFixture.exists(fixture.rockstarLauncher))
        #expect(!RockstarD3DLayoutRecord.exists(in: fixture.bottle.url))
    }

    @Test("A first run that never installed the launcher does not make the bottle Rockstar's")
    func unfinishedFirstRunIsTakenBack() throws {
        try firstRun()
        #expect(!Wine.rockstarInstalled(bottleURL: fixture.bottle.url))
        #expect(Wine.chainExecutables(for: .steam, bottleURL: fixture.bottle.url).isEmpty)

        #expect(try fixture.startSteam() == nil)

        #expect(!RockstarD3DFixture.exists(rockstarGames))
        #expect(!RockstarD3DLayoutRecord.exists(in: fixture.bottle.url))
        #expect(RockstarD3DFixture.contents(fixture.system32("d3d11.dll"))
            == RockstarD3DFixture.dxvkBytes("x64", "d3d11.dll"))
        #expect(fixture.bottle.rockstarWineD3DStatus(payloadDeployed: true) == nil)
    }

    @Test("Once Rockstar's uninstaller leaves only Whisky's copies, the swap is taken back for good")
    func uninstalledRockstarIsTakenBack() throws {
        try fixture.installRockstar()
        #expect(try fixture.startSteam() == .swapped(source: fixture.d3d11Source))
        try fixture.uninstallRockstar()
        #expect(!Wine.rockstarInstalled(bottleURL: fixture.bottle.url))

        #expect(try fixture.startSteam() == nil)

        #expect(RockstarD3DFixture.holdsNoCopies(fixture.socialClub))
        #expect(!RockstarD3DLayoutRecord.exists(in: fixture.bottle.url))
        // Rockstar made the folder, so it stays; empty, it is no install either.
        #expect(RockstarD3DFixture.exists(fixture.socialClub))
        #expect(try fixture.startSteam() == nil)
        #expect(!RockstarD3DLayoutRecord.exists(in: fixture.bottle.url))
        #expect(RockstarD3DFixture.holdsNoCopies(fixture.socialClub))
    }

    @Test("A Rockstar Games folder with anything of Rockstar's in it is an install")
    func anythingOfRockstarsIsAnInstall() throws {
        let copy = fixture.socialClub.appending(path: "d3d11.dll")
        try fixture.write(RockstarD3DFixture.dxvkBytes("x64", "d3d11.dll"), to: copy)
        #expect(!Wine.rockstarInstalled(bottleURL: fixture.bottle.url))

        try fixture.write(Data("cef".utf8), to: fixture.socialClub.appending(path: "libcef.dll"))
        #expect(Wine.rockstarInstalled(bottleURL: fixture.bottle.url))
        try FileManager.default.removeItem(at: fixture.socialClub.appending(path: "libcef.dll"))

        try FileManager.default.createDirectory(
            at: rockstarGames.appending(path: "Grand Theft Auto V"), withIntermediateDirectories: true
        )
        #expect(Wine.rockstarInstalled(bottleURL: fixture.bottle.url))
    }

    @Test("A teardown before Rockstar installed anything removes both folders it created")
    func teardownRemovesEmptyFolders() throws {
        try firstRun()
        fixture.bottle.settings.rockstarWineD3D = false

        try fixture.startSteam(descendants: [.rockstar])

        #expect(!RockstarD3DFixture.exists(rockstarGames))
        #expect(!RockstarD3DLayoutRecord.exists(in: fixture.bottle.url))
    }
}
