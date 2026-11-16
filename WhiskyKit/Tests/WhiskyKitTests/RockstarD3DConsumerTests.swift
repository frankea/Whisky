//
//  RockstarD3DConsumerTests.swift
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

/// Who in a bottle would load `system32\d3d11.dll` native first once it is
/// Wine's, and which of them a DXVK copy beside them keeps on DXVK (#382).
@Suite("Rockstar Direct3D consumers")
@MainActor
final class RockstarD3DConsumerTests {
    private let fixture: RockstarD3DFixture
    private let root: URL

    init() throws {
        fixture = try RockstarD3DFixture(prefix: "rockstar_consumers")
        root = fixture.root
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    private func scan(record: RockstarD3DLayoutRecord? = nil) -> RockstarD3DConsumerScan {
        Wine.rockstarD3DConsumers(
            bottle: fixture.bottle, recommendedBackend: .d3dMetal, dxvkFolder: fixture.dxvk, record: record
        )
    }

    private var copyKeys: [String] {
        scan().copyFolders.map(\.key)
    }

    // MARK: - Steam and Social Club

    @Test("Steam's 64-bit Chromium folders and its root are served; the 32-bit cef.win7 is not")
    func steamFolders() throws {
        // A folder without the helper is not Chromium's.
        try FileManager.default.createDirectory(
            at: fixture.steamRoot.appending(path: "bin/cef/cef.empty"), withIntermediateDirectories: true
        )

        let keys = copyKeys
        #expect(Array(keys.prefix(3)) == RockstarD3DFixture.steamCopyKeys)
        #expect(!keys.contains { $0.hasSuffix("cef.win7") || $0.hasSuffix("cef.empty") })
        #expect(scan().unserved.isEmpty)
    }

    @Test("The Steam root is served only for a 64-bit overlay", arguments: [false, true])
    func steamRootNeedsA64BitOverlay(_ thirtyTwoBit: Bool) throws {
        let overlay = fixture.steamRoot.appending(path: "gameoverlayui64.exe")
        if thirtyTwoBit {
            try fixture.write(PEBuilder.createMinimalPE32(), to: overlay)
        } else {
            try FileManager.default.removeItem(at: overlay)
        }

        #expect(!copyKeys.contains(RockstarD3DFixture.steamKey))
    }

    @Test("Social Club is always served, created ahead of Rockstar's installer when missing")
    func socialClubIsCreatedWhenMissing() throws {
        var folder = try #require(scan().copyFolders.first { $0.key == RockstarD3DFixture.socialClubKey })
        #expect(folder.create == ["Program Files/Rockstar Games", RockstarD3DFixture.socialClubKey])

        try FileManager.default.createDirectory(
            at: fixture.driveC.appending(path: "Program Files/Rockstar Games/Launcher"),
            withIntermediateDirectories: true
        )
        folder = try #require(scan().copyFolders.first { $0.key == RockstarD3DFixture.socialClubKey })
        #expect(folder.create == [RockstarD3DFixture.socialClubKey])

        try fixture.installRockstar()
        folder = try #require(scan().copyFolders.first { $0.key == RockstarD3DFixture.socialClubKey })
        #expect(folder.create.isEmpty)
    }

    // MARK: - Front ends and Chromium hosts

    private var threeDMark: URL {
        fixture.steamRoot.appending(path: "steamapps/common/3DMark/bin/x64/3DMark.exe")
    }

    @Test("A front end from the table under Recommended is served in its own folder")
    func frontEndIsServed() throws {
        try fixture.write(PEBuilder.createMinimalPE32Plus(), to: threeDMark)

        #expect(copyKeys.contains("\(RockstarD3DFixture.steamKey)/steamapps/common/3DMark/bin/x64"))
    }

    @Test("A front end the user put on D3DMetal is no consumer")
    func frontEndOnD3DMetalIsNoConsumer() throws {
        try fixture.write(PEBuilder.createMinimalPE32Plus(), to: threeDMark)
        try fixture.setBackend(.d3dMetal, for: threeDMark)

        #expect(!copyKeys.contains { $0.contains("3DMark") })
        #expect(scan().unserved.isEmpty)
    }

    @Test("A front end sharing its folder with a game executable is unserved")
    func frontEndBesideAGameIsUnserved() throws {
        try fixture.addGame(appId: 223_850, name: "3DMark", installDir: "3DMark", exe: "bin/x64/Benchmark.exe")
        try fixture.write(PEBuilder.createMinimalPE32Plus(), to: threeDMark)

        let result = scan()
        #expect(!result.copyFolders.contains { $0.key.contains("3DMark") })
        #expect(result.unserved == ["3DMark.exe"])
    }

    /// A library game whose `bin/x64` ships CEF, with a Chromium host there.
    private func chromiumHost() throws -> URL {
        try fixture.addGame(appId: 2, name: "Bench", installDir: "Bench", exe: "Bench.exe")
        let folder = fixture.steamRoot.appending(path: "steamapps/common/Bench/bin/x64")
        try fixture.write(Data("cef".utf8), to: folder.appending(path: "libcef.dll"))
        let host = folder.appending(path: "BenchUI.exe")
        try fixture.write(PEBuilder.createMinimalPE32Plus(), to: host)
        return host
    }

    @Test("A Chromium host is served only when its own override is DXVK")
    func chromiumHostOnDXVKIsServed() throws {
        let host = try chromiumHost()
        let key = "\(RockstarD3DFixture.steamKey)/steamapps/common/Bench/bin/x64"
        #expect(!copyKeys.contains(key))

        try fixture.setBackend(.dxvk, for: host)

        #expect(copyKeys.contains(key))
    }

    @Test("A Chromium host whose own overrides ask for native d3d11 some other way is served", arguments: [
        "legacy", "custom"
    ])
    func chromiumHostOnNativeOverridesIsServed(_ kind: String) throws {
        let host = try chromiumHost()
        var overrides = ProgramOverrides()
        if kind == "legacy" {
            overrides.dxvk = true
        } else {
            overrides.dllOverrides = [DLLOverrideEntry(dllName: "d3d11", mode: .nativeThenBuiltin)]
        }
        try fixture.setOverrides(overrides, for: host)

        #expect(copyKeys.contains("\(RockstarD3DFixture.steamKey)/steamapps/common/Bench/bin/x64"))
    }

    @Test("A folder holding DXMT's game copies is unserved")
    func dxmtFolderIsUnserved() throws {
        let host = try chromiumHost()
        try fixture.setBackend(.dxvk, for: host)
        let key = "\(RockstarD3DFixture.steamKey)/steamapps/common/Bench/bin/x64"
        try DXMTGameFolderRecord(copies: ["\(key)/d3d11.dll": "abc"]).save(to: fixture.bottle.url)

        let result = scan()
        #expect(!result.copyFolders.contains { $0.key == key })
        #expect(result.unserved == ["BenchUI.exe"])
    }

    @Test("Rockstar's launcher folder never takes a copy", arguments: [
        ("Program Files/Rockstar Games/Launcher", true),
        ("program files/ROCKSTAR GAMES/launcher/sub", true),
        ("Program Files/Rockstar Games/Social Club", false),
        ("Program Files/Launcher/Rockstar Games", false)
    ])
    func rockstarLauncherFolderIsRefused(_ key: String, _ refused: Bool) {
        #expect(Wine.isUnderRockstarLauncher(key) == refused)
    }

    // MARK: - Files already there

    @Test("A folder holding a d3d11.dll that is not DXVK's is left to its program")
    func foreignFileIsUnserved() throws {
        let cef64 = fixture.steamRoot.appending(path: "bin/cef/cef.win64")
        try Data("steam's own".utf8).write(to: cef64.appending(path: "d3d11.dll"))
        let cef7x64 = fixture.steamRoot.appending(path: "bin/cef/cef.win7x64")
        try FileManager.default.createSymbolicLink(
            at: cef7x64.appending(path: "d3d10core.dll"),
            withDestinationURL: fixture.dxvk.appending(path: "x64/d3d10core.dll")
        )
        // DXVK's own bytes, so only the spelling makes it someone else's.
        try RockstarD3DFixture.dxvkBytes("x64", "d3d11.dll").write(to: fixture.steamRoot.appending(path: "D3D11.dll"))

        let result = scan()
        #expect(result.unserved.sorted() == RockstarD3DFixture.steamCopyKeys.sorted())
        #expect(result.copyFolders.map(\.key) == [RockstarD3DFixture.socialClubKey])
    }

    @Test("DXVK's own bytes and Whisky's recorded copy are not foreign")
    func dxvkAndRecordedCopiesAreNotForeign() throws {
        let cef64 = fixture.steamRoot.appending(path: "bin/cef/cef.win64")
        try RockstarD3DFixture.dxvkBytes("x64", "d3d11.dll").write(to: cef64.appending(path: "d3d11.dll"))
        let older = Data("older dxvk".utf8)
        try older.write(to: cef64.appending(path: "d3d10core.dll"))
        let record = RockstarD3DLayoutRecord(
            engineStamp: "4.8.3", sourceSHA256: "x",
            copies: ["\(RockstarD3DFixture.steamCopyKeys[0])/d3d10core.dll": RockstarD3DLayoutRecord.sha256(older)]
        )

        #expect(scan(record: record).unserved.isEmpty)
        #expect(scan().unserved == [RockstarD3DFixture.steamCopyKeys[0]])
    }

    // MARK: - Library games and other launchers

    @Test("Library games on DXVK are listed by name; one on Recommended's D3DMetal is not")
    func dxvkPlanGames() throws {
        // Age of Empires II: Definitive Edition, whose GameDB default variant is DXVK.
        #expect(LaunchResolver.plan(steamAppId: 813_780).overrides.graphicsBackend == .dxvk)
        try fixture.addGame(appId: 813_780, name: "Age of Empires II", installDir: "AoE2DE", exe: "AoE2DE.exe")
        let overridden = try fixture.addGame(
            appId: 5,
            name: "Overridden",
            installDir: "Overridden",
            exe: "Overridden.exe"
        )
        try fixture.setBackend(.dxvk, for: overridden)
        try fixture.addGame(appId: 6, name: "Recommended", installDir: "Recommended", exe: "Recommended.exe")

        #expect(scan().dxvkPlanGames.sorted() == ["Age of Empires II", "Overridden"])
    }

    @Test("Other launchers with a native-first d3d11 entry are unserved; a stale game entry is not")
    func otherLaunchers() throws {
        let userReg = #"""
        WINE REGISTRY Version 2

        [Software\\Wine\\AppDefaults\\EADesktop.exe\\DllOverrides] 1731628800
        "d3d11"="n,b"

        [Software\\Wine\\AppDefaults\\EABackgroundService.exe\\DllOverrides] 1731628800
        "d3d11"="n,b"

        [Software\\Wine\\AppDefaults\\EpicGamesLauncher.exe\\DllOverrides] 1731628800
        "d3d11"="b"

        [Software\\Wine\\AppDefaults\\EADesktop.exe\\Extra\\DllOverrides] 1731628800
        "d3d11"="n,b"

        [Software\\Wine\\AppDefaults\\SomeGame.exe\\DllOverrides] 1731628800
        "d3d11"="n,b"

        [Software\\Wine\\AppDefaults\\steamwebhelper.exe\\DllOverrides] 1731628800
        "d3d11"="n,b"

        """#
        try userReg.write(to: fixture.bottle.url.appending(path: "user.reg"), atomically: true, encoding: .utf8)

        #expect(Wine.otherLauncherConsumers(bottleURL: fixture.bottle.url) == [
            "EADesktop.exe", "EABackgroundService.exe"
        ])
        #expect(scan().unserved == ["EADesktop.exe", "EABackgroundService.exe"])
    }

    // MARK: - The bottle scope

    @Test("The bottle scope asks for d3d11 native first on DXVK, DXMT, the Rockstar preset or an override")
    func bottleUsesNativeD3D11() {
        let bottle = fixture.bottle
        func native() -> Bool {
            Wine.rockstarBottleUsesNativeD3D11(
                bottle: bottle, recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: true
            )
        }
        #expect(!native())

        for backend in [GraphicsBackend.dxvk, .dxmt] {
            bottle.settings.graphicsBackend = backend
            #expect(native(), "\(backend)")
        }
        bottle.settings.graphicsBackend = .recommended

        bottle.settings.launcherCompatibilityMode = true
        bottle.settings.detectedLauncher = .rockstar
        bottle.settings.autoEnableDXVK = true
        #expect(native())
        bottle.settings.launcherCompatibilityMode = false
        #expect(!native())

        bottle.settings.dllOverrides = [DLLOverrideEntry(dllName: "d3d11", mode: .nativeThenBuiltin)]
        #expect(native())
    }

    @Test("A native-first clause is read the way Wine reads it", arguments: [
        ("d3d11=n,b", true), ("d3d11=b", false), ("dxgi,d3d11=n", true), ("d3d11=n;d3d11=b", false),
        ("D3D11 = n,b", true), ("d3d11=", false), ("d3d12=n", false)
    ])
    func nativeFirstParsing(_ overrides: String, _ expected: Bool) {
        #expect(Wine.asksNativeFirst("d3d11", in: overrides) == expected)
    }
}
