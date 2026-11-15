//
//  DXMTGameFolderRecoveryTests.swift
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

/// DXMT's trio beside a game's executables (#378) when something goes wrong
/// or the game spans folders: failed writes, a record that cannot be saved or
/// lost track, an install that moved, and the folders of one game following
/// a launch of any of them.
@Suite("DXMT copies in game folders: recovery and scope")
@MainActor
final class DXMTGameFolderRecoveryTests {
    private let fixture: DXMTGameFolderFixture
    private typealias Fixture = DXMTGameFolderFixture

    init() throws {
        fixture = try DXMTGameFolderFixture(prefix: "dxmt_game_folder_recovery")
    }

    deinit {
        fixture.cleanUp()
    }

    private struct InstallFailure: Error {}

    private func reconcile(
        _ action: DXMTGameFolderAction, _ executables: [URL], _ bottle: Bottle, payload: URL,
        installer: Wine.DXMTFileInstaller? = nil
    ) {
        if let installer {
            Wine.reconcileDXMTGameFolders(
                action, executables: executables, bottleURL: bottle.url, payloadRoot: payload, installer: installer
            )
        } else {
            Wine.reconcileDXMTGameFolders(action, executables: executables, bottleURL: bottle.url, payloadRoot: payload)
        }
    }

    /// An installer that copies like the real one, except into `failing`.
    private func installer(failingFor failing: String) -> Wine.DXMTFileInstaller {
        { destination, source in
            guard destination.lastPathComponent != failing else { throw InstallFailure() }
            _ = try FileManager.default.installFileIfContentDiffers(at: destination, from: source)
        }
    }

    private func write(_ data: Data, _ name: String, besides executable: URL) throws {
        try data.write(to: executable.deletingLastPathComponent().appending(path: name))
    }

    private func recordCount(_ bottle: Bottle) -> Int {
        DXMTGameFolderRecord.load(from: bottle.url).copies.count
    }

    // MARK: - Failed writes

    @Test("A write that fails after another succeeded takes the written copy back")
    func failedSecondWriteRollsBackTheFirst() throws {
        let bottle = try fixture.makeBottle()
        let game = try fixture.makeGame(in: bottle)

        try reconcile(
            .deploy, [game], bottle, payload: fixture.makeDXMTPayload(),
            installer: installer(failingFor: "d3d10core.dll")
        )

        #expect(Fixture.holdsNoTrio(game.deletingLastPathComponent()))
        #expect(recordCount(bottle) == 0)
    }

    @Test("A refresh whose last write fails takes back the new copies and the old one")
    func failedRefreshRollsBackEveryCopy() throws {
        let bottle = try fixture.makeBottle()
        let game = try fixture.makeGame(in: bottle)
        try reconcile(.deploy, [game], bottle, payload: fixture.makeDXMTPayload())

        try reconcile(
            .deploy, [game], bottle, payload: fixture.makeDXMTPayload(version: "2"),
            installer: installer(failingFor: "dxgi.dll")
        )

        #expect(Fixture.holdsNoTrio(game.deletingLastPathComponent()))
        #expect(recordCount(bottle) == 0)
    }

    @Test("Copies whose record cannot be saved are taken back")
    func unsavableRecordTakesBackThePlacedCopies() throws {
        let bottle = try fixture.makeBottle()
        let game = try fixture.makeGame(in: bottle)
        // A folder where the record goes, which no write can replace.
        let blocker = DXMTGameFolderRecord.url(in: bottle.url)
        try FileManager.default.createDirectory(at: blocker, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: blocker.appending(path: "keep"))

        try reconcile(.deploy, [game], bottle, payload: fixture.makeDXMTPayload())

        #expect(Fixture.holdsNoTrio(game.deletingLastPathComponent()))
    }

    // MARK: - A record that lost track

    @Test("A deploy after the record was lost adopts the copies, so a later removal takes them back")
    func lostRecordIsRebuiltByTheNextDeploy() throws {
        let bottle = try fixture.makeBottle()
        let game = try fixture.makeGame(in: bottle, folder: "Games/Other")
        let payload = try fixture.makeDXMTPayload()
        reconcile(.deploy, [game], bottle, payload: payload)
        try Data("not a plist".utf8).write(to: DXMTGameFolderRecord.url(in: bottle.url))

        reconcile(.deploy, [game], bottle, payload: payload)
        #expect(recordCount(bottle) == 3)

        reconcile(.remove, [game], bottle, payload: payload)
        #expect(Fixture.holdsNoTrio(game.deletingLastPathComponent()))
    }

    @Test("A moved install keeps its copies tracked under the new path, and the old entries go")
    func movedInstallIsTrackedAtItsNewPath() throws {
        let bottle = try fixture.makeBottle()
        let game = try fixture.makeGame(in: bottle)
        let payload = try fixture.makeDXMTPayload()
        reconcile(.deploy, [game], bottle, payload: payload)
        let moved = bottle.url.appending(path: "drive_c/SteamLibrary/steamapps/common/Game")
        try FileManager.default.createDirectory(
            at: moved.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: game.deletingLastPathComponent(), to: moved)
        let movedGame = moved.appending(path: "Game.exe")

        reconcile(.deploy, [movedGame], bottle, payload: payload)
        let keys = DXMTGameFolderRecord.load(from: bottle.url).copies.keys
        #expect(keys.count == 3)
        #expect(keys.allSatisfy { $0.hasPrefix("SteamLibrary/") })

        reconcile(.remove, [movedGame], bottle, payload: payload)
        #expect(Fixture.holdsNoTrio(moved))
    }

    @Test("A folder with no readable executable is left alone")
    func unreadableExecutablesSkipTheFolder() throws {
        let bottle = try fixture.makeBottle()
        let stub = bottle.url.appending(path: "drive_c/Games/Stub/Stub.exe")
        try FileManager.default.createDirectory(at: stub.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("MZ".utf8).write(to: stub)

        try reconcile(.deploy, [stub], bottle, payload: fixture.makeDXMTPayload())

        #expect(Fixture.holdsNoTrio(stub.deletingLastPathComponent()))
    }

    @Test("Removal in a Steam game keeps files the record does not name, even with the payload's bytes")
    func removalInSteamGameKeepsUnrecordedPayloadCopies() throws {
        let bottle = try fixture.makeBottle()
        let game = try fixture.makeGame(in: bottle)
        let own = Fixture.nativeFake("the game's own dxgi")
        try write(Fixture.dxmtFake("x64", "d3d11.dll"), "d3d11.dll", besides: game)
        try write(Fixture.dxmtFake("x32", "d3d10core.dll"), "d3d10core.dll", besides: game)
        try write(own, "dxgi.dll", besides: game)

        try reconcile(.remove, [game], bottle, payload: fixture.makeDXMTPayload())

        // Whisky cannot tell a copy whose record was lost from one the user put
        // there, so neither goes.
        let folder = game.deletingLastPathComponent()
        #expect(Fixture.contents(folder.appending(path: "d3d11.dll")) == Fixture.dxmtFake("x64", "d3d11.dll"))
        #expect(Fixture.contents(folder.appending(path: "d3d10core.dll")) == Fixture.dxmtFake("x32", "d3d10core.dll"))
        #expect(Fixture.contents(folder.appending(path: "dxgi.dll")) == own)
    }

    // MARK: - The game's own files

    @Test("A trio file spelled differently is the game's, even with the payload's bytes")
    func differentlySpelledDLLCountsAsTheGamesOwn() throws {
        let bottle = try fixture.makeBottle()
        let game = try fixture.makeGame(in: bottle)
        let folder = game.deletingLastPathComponent()
        try Fixture.dxmtFake("x64", "dxgi.dll").write(to: folder.appending(path: "DXGI.dll"))

        try reconcile(.deploy, [game], bottle, payload: fixture.makeDXMTPayload())

        let entries = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        #expect(entries.sorted() == ["DXGI.dll", "Game.exe"])
        #expect(recordCount(bottle) == 0)
    }

    // MARK: - One game, several folders

    /// An Unreal layout: a bootstrap stub at the root, the game three folders down.
    private func makeUnrealGame(_ bottle: Bottle) throws -> (stub: URL, shipping: URL) {
        let stub = try fixture.makeGame(in: bottle)
        let shipping = try fixture.makeGame(
            in: bottle, folder: "\(Fixture.gameFolder)/Game/Binaries/Win64", name: "Game-Win64-Shipping.exe"
        )
        return (stub, shipping)
    }

    @Test("Removing for the stub also takes back the copies in the game's Binaries folder")
    func removalForTheStubReachesTheWholeGame() throws {
        let bottle = try fixture.makeBottle()
        let game = try makeUnrealGame(bottle)
        let payload = try fixture.makeDXMTPayload()
        reconcile(.deploy, [game.stub, game.shipping], bottle, payload: payload)
        #expect(Fixture.holdsDXMT(game.shipping.deletingLastPathComponent()))

        reconcile(.remove, [game.stub], bottle, payload: payload)

        #expect(Fixture.holdsNoTrio(game.stub.deletingLastPathComponent()))
        #expect(Fixture.holdsNoTrio(game.shipping.deletingLastPathComponent()))
        #expect(recordCount(bottle) == 0)
    }

    @Test("Refreshing for the stub also refreshes the game's Binaries folder")
    func refreshForTheStubReachesTheWholeGame() throws {
        let bottle = try fixture.makeBottle()
        let game = try makeUnrealGame(bottle)
        try reconcile(.deploy, [game.stub, game.shipping], bottle, payload: fixture.makeDXMTPayload())

        try reconcile(.refresh, [game.stub], bottle, payload: fixture.makeDXMTPayload(version: "2"))

        #expect(Fixture.holdsDXMT(game.stub.deletingLastPathComponent(), version: "2"))
        #expect(Fixture.holdsDXMT(game.shipping.deletingLastPathComponent(), version: "2"))
    }

    @Test("Another game in the same library, and Steam's own folder, keep their copies")
    func removalStaysInsideTheGame() throws {
        let bottle = try fixture.makeBottle()
        let game = try fixture.makeGame(in: bottle)
        let other = try fixture.makeGame(in: bottle, folder: "Program Files (x86)/Steam/steamapps/common/Other")
        let steam = try fixture.steam(in: bottle)
        let payload = try fixture.makeDXMTPayload()
        reconcile(.deploy, [game, other], bottle, payload: payload)

        reconcile(.remove, [other], bottle, payload: payload)
        reconcile(.remove, [steam], bottle, payload: payload)

        #expect(Fixture.holdsDXMT(game.deletingLastPathComponent()))
        #expect(Fixture.holdsNoTrio(other.deletingLastPathComponent()))
    }
}
