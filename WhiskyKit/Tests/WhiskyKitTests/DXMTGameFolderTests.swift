//
//  DXMTGameFolderTests.swift
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

/// DXMT's trio beside a game's executables, for a launcher whose `system32`
/// has to keep DXVK (#378): which folders get it, which never do, and how the
/// copies Whisky placed are kept current and taken back.
@Suite("DXMT copies in game folders")
@MainActor
final class DXMTGameFolderTests {
    private let fixture: DXMTGameFolderFixture
    private typealias Fixture = DXMTGameFolderFixture

    init() throws {
        fixture = try DXMTGameFolderFixture(prefix: "dxmt_game_folder")
    }

    deinit {
        fixture.cleanUp()
    }

    private func reconcile(
        _ action: DXMTGameFolderAction, _ executables: [URL], _ bottle: Bottle, payload: URL
    ) {
        Wine.reconcileDXMTGameFolders(action, executables: executables, bottleURL: bottle.url, payloadRoot: payload)
    }

    private func write(_ data: Data, _ name: String, besides executable: URL) throws {
        try data.write(to: executable.deletingLastPathComponent().appending(path: name))
    }

    // MARK: - Architecture

    @Test("A 64-bit game gets the x64 trio, and nothing else lands beside it")
    func x64GameGetsTheX64Trio() throws {
        let bottle = try fixture.makeBottle()
        let game = try fixture.makeGame(in: bottle, arch: .x64)

        try reconcile(.deploy, [game], bottle, payload: fixture.makeDXMTPayload())

        let folder = game.deletingLastPathComponent()
        #expect(Fixture.holdsDXMT(folder, arch: "x64"))
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "winemetal.dll").path))
    }

    @Test("A 32-bit game gets the x32 trio")
    func x32GameGetsTheX32Trio() throws {
        let bottle = try fixture.makeBottle()
        let game = try fixture.makeGame(in: bottle, arch: .x32)

        try reconcile(.deploy, [game], bottle, payload: fixture.makeDXMTPayload())

        #expect(Fixture.holdsDXMT(game.deletingLastPathComponent(), arch: "x32"))
    }

    @Test("A payload without the game's architecture leaves the folder alone")
    func missingArchitectureSkipsTheFolder() throws {
        let bottle = try fixture.makeBottle()
        let game = try fixture.makeGame(in: bottle, arch: .x32)

        try reconcile(.deploy, [game], bottle, payload: fixture.makeDXMTPayload(arches: ["x64"]))

        #expect(Fixture.holdsNoTrio(game.deletingLastPathComponent()))
    }

    @Test("A folder whose executables disagree on architecture gets the largest one's")
    func mixedArchitectureFollowsTheLargestExecutable() throws {
        let bottle = try fixture.makeBottle()
        let game = try fixture.makeGame(in: bottle, arch: .x64, padding: 4_096)
        _ = try fixture.makeGame(in: bottle, name: "Launcher.exe", arch: .x32)
        let tool = try fixture.makeGame(in: bottle, folder: "Games/Tools", name: "Tool.exe", arch: .x32, padding: 4_096)
        _ = try fixture.makeGame(in: bottle, folder: "Games/Tools", name: "Helper.exe", arch: .x64)
        let payload = try fixture.makeDXMTPayload()

        reconcile(
            .deploy,
            [bottle.url.appending(path: "drive_c/\(Fixture.gameFolder)/Launcher.exe"), game],
            bottle,
            payload: payload
        )
        reconcile(
            .deploy,
            [tool, tool.deletingLastPathComponent().appending(path: "Helper.exe")],
            bottle,
            payload: payload
        )

        #expect(Fixture.holdsDXMT(game.deletingLastPathComponent(), arch: "x64"))
        #expect(Fixture.holdsDXMT(tool.deletingLastPathComponent(), arch: "x32"))
    }

    // MARK: - The game's own files

    @Test("A game that ships its own d3d11 keeps it, and gets none of the trio")
    func gamesOwnDLLIsNeverClobbered() throws {
        let bottle = try fixture.makeBottle()
        let game = try fixture.makeGame(in: bottle)
        let own = Fixture.nativeFake("the game's own d3d11")
        try write(own, "d3d11.dll", besides: game)

        try reconcile(.deploy, [game], bottle, payload: fixture.makeDXMTPayload())

        let folder = game.deletingLastPathComponent()
        #expect(Fixture.contents(folder.appending(path: "d3d11.dll")) == own)
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "dxgi.dll").path))
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "d3d10core.dll").path))
    }

    @Test("A game that ships only its own dxgi gets no partial set")
    func partialSetIsRefused() throws {
        let bottle = try fixture.makeBottle()
        let game = try fixture.makeGame(in: bottle)
        let own = Fixture.nativeFake("the game's own dxgi")
        try write(own, "dxgi.dll", besides: game)

        try reconcile(.deploy, [game], bottle, payload: fixture.makeDXMTPayload())

        let folder = game.deletingLastPathComponent()
        #expect(Fixture.contents(folder.appending(path: "dxgi.dll")) == own)
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "d3d11.dll").path))
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "d3d10core.dll").path))
    }

    @Test("A copy of DXMT already there is adopted, and taken back with the rest")
    func identicalCopyIsAdopted() throws {
        let bottle = try fixture.makeBottle()
        let game = try fixture.makeGame(in: bottle)
        let payload = try fixture.makeDXMTPayload()
        try write(Fixture.dxmtFake("x64", "d3d11.dll"), "d3d11.dll", besides: game)

        reconcile(.deploy, [game], bottle, payload: payload)
        let folder = game.deletingLastPathComponent()
        #expect(Fixture.holdsDXMT(folder))
        #expect(DXMTGameFolderRecord.load(from: bottle.url).copies.count == 3)

        reconcile(.remove, [game], bottle, payload: payload)
        #expect(Fixture.holdsNoTrio(folder))
    }

    @Test("When a game update replaces one copy, the rest of Whisky's copies go and the game's file stays")
    func gameUpdateOverOneCopyRetractsTheRest() throws {
        let bottle = try fixture.makeBottle()
        let game = try fixture.makeGame(in: bottle)
        let payload = try fixture.makeDXMTPayload()
        reconcile(.deploy, [game], bottle, payload: payload)
        let updated = Fixture.nativeFake("the game's updated d3d11")
        try write(updated, "d3d11.dll", besides: game)

        reconcile(.deploy, [game], bottle, payload: payload)

        let folder = game.deletingLastPathComponent()
        #expect(Fixture.contents(folder.appending(path: "d3d11.dll")) == updated)
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "dxgi.dll").path))
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "d3d10core.dll").path))
    }

    // MARK: - Taking the copies back

    @Test("A launch on another plan removes the copies Whisky placed, and the record with them")
    func removalFollowsTheRecord() throws {
        let bottle = try fixture.makeBottle()
        let game = try fixture.makeGame(in: bottle)
        let payload = try fixture.makeDXMTPayload()
        reconcile(.deploy, [game], bottle, payload: payload)
        #expect(DXMTGameFolderRecord.load(from: bottle.url).copies.count == 3)

        reconcile(.remove, [game], bottle, payload: payload)

        #expect(Fixture.holdsNoTrio(game.deletingLastPathComponent()))
        #expect(DXMTGameFolderRecord.load(from: bottle.url).copies.isEmpty)
        #expect(FileManager.default.fileExists(atPath: game.path), "the game itself stays")
    }

    @Test("A copy whose content changed since Whisky placed it is kept")
    func changedCopyIsKept() throws {
        let bottle = try fixture.makeBottle()
        let game = try fixture.makeGame(in: bottle)
        let payload = try fixture.makeDXMTPayload()
        reconcile(.deploy, [game], bottle, payload: payload)
        let replaced = Fixture.nativeFake("someone else's d3d11")
        try write(replaced, "d3d11.dll", besides: game)

        reconcile(.remove, [game], bottle, payload: payload)

        let folder = game.deletingLastPathComponent()
        #expect(Fixture.contents(folder.appending(path: "d3d11.dll")) == replaced)
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "dxgi.dll").path))
        #expect(DXMTGameFolderRecord.load(from: bottle.url).copies.isEmpty)
    }

    @Test("Removal outside a Steam game leaves an untracked trio alone")
    func removalWithoutARecordOutsideSteamTouchesNothing() throws {
        let bottle = try fixture.makeBottle()
        let game = try fixture.makeGame(in: bottle, folder: "Games/Other")
        for dll in Fixture.trio {
            try write(Fixture.dxmtFake("x64", dll), dll, besides: game)
        }

        try reconcile(.remove, [game], bottle, payload: fixture.makeDXMTPayload())

        #expect(Fixture.holdsDXMT(game.deletingLastPathComponent()))
    }

    // MARK: - Keeping the copies current

    @Test("A new DXMT payload replaces the copies, and the record follows it")
    func payloadChangeRefreshesTheCopies() throws {
        let bottle = try fixture.makeBottle()
        let game = try fixture.makeGame(in: bottle)
        try reconcile(.deploy, [game], bottle, payload: fixture.makeDXMTPayload())

        let newer = try fixture.makeDXMTPayload(version: "2")
        reconcile(.deploy, [game], bottle, payload: newer)

        let folder = game.deletingLastPathComponent()
        #expect(Fixture.holdsDXMT(folder, version: "2"))
        reconcile(.remove, [game], bottle, payload: newer)
        #expect(Fixture.holdsNoTrio(folder))
    }

    @Test("Copies a game update deleted come back on the next DXMT launch")
    func deletedCopiesAreRedeployed() throws {
        let bottle = try fixture.makeBottle()
        let game = try fixture.makeGame(in: bottle)
        let payload = try fixture.makeDXMTPayload()
        reconcile(.deploy, [game], bottle, payload: payload)
        let folder = game.deletingLastPathComponent()
        for dll in Fixture.trio {
            try FileManager.default.removeItem(at: folder.appending(path: dll))
        }

        reconcile(.deploy, [game], bottle, payload: payload)

        #expect(Fixture.holdsDXMT(folder))
    }

    @Test("A direct DXMT launch refreshes copies already there and places none")
    func refreshOnlyTouchesTrackedFolders() throws {
        let bottle = try fixture.makeBottle()
        let tracked = try fixture.makeGame(in: bottle)
        let untracked = try fixture.makeGame(in: bottle, folder: "Games/Other", name: "Other.exe")
        try reconcile(.deploy, [tracked], bottle, payload: fixture.makeDXMTPayload())

        let newer = try fixture.makeDXMTPayload(version: "2")
        reconcile(.refresh, [tracked, untracked], bottle, payload: newer)

        #expect(Fixture.holdsDXMT(tracked.deletingLastPathComponent(), version: "2"))
        #expect(Fixture.holdsNoTrio(untracked.deletingLastPathComponent()))
    }

    // MARK: - Where Whisky never writes

    @Test("A game folder that is a symbolic link out of drive_c gets nothing")
    func symlinkedFolderOutsideDriveCIsRejected() throws {
        let bottle = try fixture.makeBottle()
        let outside = fixture.root.appending(path: "Outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try PEBuilder.createMinimalPE32Plus().write(to: outside.appending(path: "Game.exe"))
        let link = bottle.url.appending(path: "drive_c/Games/Linked")
        try FileManager.default.createDirectory(
            at: link.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        try reconcile(.deploy, [link.appending(path: "Game.exe")], bottle, payload: fixture.makeDXMTPayload())

        #expect(Fixture.holdsNoTrio(outside))
        #expect(DXMTGameFolderRecord.load(from: bottle.url).copies.isEmpty)
    }

    @Test("An executable outside the bottle, or under drive_c/windows, gets nothing")
    func foldersOutsideTheGameAreaAreRejected() throws {
        let bottle = try fixture.makeBottle()
        let inWindows = try fixture.makeGame(in: bottle, folder: "windows/Games")
        let inSystem32 = try fixture.makeGame(in: bottle, folder: "WINDOWS/system32", name: "tool.exe")
        let outside = fixture.root.appending(path: "Elsewhere/Game.exe")
        try FileManager.default.createDirectory(
            at: outside.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try PEBuilder.createMinimalPE32Plus().write(to: outside)
        let escaping = bottle.url.appending(path: "drive_c/Games/../../../Elsewhere/Game.exe")

        try reconcile(.deploy, [inWindows, inSystem32, outside, escaping], bottle, payload: fixture.makeDXMTPayload())

        #expect(Fixture.holdsNoTrio(inWindows.deletingLastPathComponent()))
        #expect(Fixture.holdsNoTrio(inSystem32.deletingLastPathComponent()))
        #expect(Fixture.holdsNoTrio(outside.deletingLastPathComponent()))
    }

    @Test("A trio file that is a symbolic link counts as the game's own")
    func symlinkedDLLIsNeverWrittenThrough() throws {
        let bottle = try fixture.makeBottle()
        let game = try fixture.makeGame(in: bottle)
        // The payload's own bytes, so only the link itself marks it as not Whisky's.
        let target = fixture.root.appending(path: "target.dll")
        let original = Fixture.dxmtFake("x64", "dxgi.dll")
        try original.write(to: target)
        try FileManager.default.createSymbolicLink(
            at: game.deletingLastPathComponent().appending(path: "dxgi.dll"), withDestinationURL: target
        )

        try reconcile(.deploy, [game], bottle, payload: fixture.makeDXMTPayload())

        let folder = game.deletingLastPathComponent()
        #expect(Fixture.contents(target) == original)
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "d3d11.dll").path))
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "d3d10core.dll").path))
        #expect(DXMTGameFolderRecord.load(from: bottle.url).copies.isEmpty)
    }

    @Test("A folder that cannot be written leaves no partial set and no record")
    func failedDeployLeavesNothing() throws {
        let bottle = try fixture.makeBottle()
        let game = try fixture.makeGame(in: bottle)
        let folder = game.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)

        try reconcile(.deploy, [game], bottle, payload: fixture.makeDXMTPayload())

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        #expect(Fixture.holdsNoTrio(folder))
        #expect(DXMTGameFolderRecord.load(from: bottle.url).copies.isEmpty)
    }
}
