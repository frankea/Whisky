//
//  DXMTGameFolderAdoptionTests.swift
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

/// A trio file that was already in a game folder with the payload's own bytes
/// before a deploy, put there by the user or another tool: a deploy that does
/// not complete, or leaves the folder to the game, takes back only what it
/// wrote and leaves that file where it was.
@Suite("DXMT copies in game folders: files that were there before")
@MainActor
final class DXMTGameFolderAdoptionTests {
    private let fixture: DXMTGameFolderFixture
    private typealias Fixture = DXMTGameFolderFixture

    /// A game folder outside Steam.
    private static let otherFolder = "Games/Other"

    init() throws {
        fixture = try DXMTGameFolderFixture(prefix: "dxmt_game_folder_adoption")
    }

    deinit {
        fixture.cleanUp()
    }

    private struct InstallFailure: Error {}

    /// An installer that copies like the real one, except into `failing`.
    private func installer(failingFor failing: String) -> Wine.DXMTFileInstaller {
        { destination, source in
            guard destination.lastPathComponent != failing else { throw InstallFailure() }
            _ = try FileManager.default.installFileIfContentDiffers(at: destination, from: source)
        }
    }

    private func deploy(
        _ game: URL, _ bottle: Bottle, payload: URL, failingFor failing: String? = nil
    ) {
        if let failing {
            Wine.reconcileDXMTGameFolders(
                .deploy, executables: [game], bottleURL: bottle.url, payloadRoot: payload,
                installer: installer(failingFor: failing)
            )
        } else {
            Wine.reconcileDXMTGameFolders(.deploy, executables: [game], bottleURL: bottle.url, payloadRoot: payload)
        }
    }

    /// Puts the payload's own `dll` beside `game`, as the user or another tool would.
    @discardableResult
    private func placeByHand(_ dll: String, besides game: URL) throws -> URL {
        let url = game.deletingLastPathComponent().appending(path: dll)
        try Fixture.dxmtFake("x64", dll).write(to: url)
        return url
    }

    private func exists(_ folder: URL, _ dll: String) -> Bool {
        FileManager.default.fileExists(atPath: folder.appending(path: dll).path(percentEncoded: false))
    }

    private func recordCount(_ bottle: Bottle) -> Int {
        DXMTGameFolderRecord.load(from: bottle.url).copies.count
    }

    // MARK: - A write that fails

    @Test("A payload copy already there stays when a later write fails", arguments: [
        (folder: "Games/Other", failing: "dxgi.dll"),
        (folder: DXMTGameFolderFixture.gameFolder, failing: "d3d10core.dll")
    ])
    func preExistingCopySurvivesALaterFailedWrite(folder: String, failing: String) throws {
        let bottle = try fixture.makeBottle()
        let game = try fixture.makeGame(in: bottle, folder: folder)
        let target = try placeByHand("d3d11.dll", besides: game)

        try deploy(game, bottle, payload: fixture.makeDXMTPayload(), failingFor: failing)

        let gameFolder = game.deletingLastPathComponent()
        #expect(Fixture.contents(target) == Fixture.dxmtFake("x64", "d3d11.dll"))
        #expect(!exists(gameFolder, "d3d10core.dll"))
        #expect(!exists(gameFolder, "dxgi.dll"))
        #expect(recordCount(bottle) == 0)
    }

    @Test("A payload copy already there stays when an earlier write fails before reaching it")
    func preExistingCopySurvivesAnEarlierFailedWrite() throws {
        let bottle = try fixture.makeBottle()
        let game = try fixture.makeGame(in: bottle, folder: Self.otherFolder)
        let target = try placeByHand("dxgi.dll", besides: game)

        try deploy(game, bottle, payload: fixture.makeDXMTPayload(), failingFor: "d3d10core.dll")

        #expect(Fixture.contents(target) == Fixture.dxmtFake("x64", "dxgi.dll"))
        #expect(!exists(game.deletingLastPathComponent(), "d3d11.dll"))
        #expect(recordCount(bottle) == 0)
    }

    // MARK: - A record that cannot be saved

    @Test("A payload copy already there stays when the record cannot be saved, and Whisky's copies go")
    func preExistingCopySurvivesAnUnsavableRecord() throws {
        let bottle = try fixture.makeBottle()
        let game = try fixture.makeGame(in: bottle, folder: Self.otherFolder)
        let target = try placeByHand("d3d11.dll", besides: game)
        // A folder where the record goes, which no write can replace.
        let blocker = DXMTGameFolderRecord.url(in: bottle.url)
        try FileManager.default.createDirectory(at: blocker, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: blocker.appending(path: "keep"))

        try deploy(game, bottle, payload: fixture.makeDXMTPayload())

        let gameFolder = game.deletingLastPathComponent()
        #expect(Fixture.contents(target) == Fixture.dxmtFake("x64", "d3d11.dll"))
        #expect(!exists(gameFolder, "d3d10core.dll"))
        #expect(!exists(gameFolder, "dxgi.dll"))
    }

    // MARK: - A folder left to the game

    @Test("A deploy leaving a Steam game's folder to the game keeps a payload copy it never placed")
    func folderLeftToTheGameKeepsAnUnplacedPayloadCopy() throws {
        let bottle = try fixture.makeBottle()
        let game = try fixture.makeGame(in: bottle)
        let target = try placeByHand("d3d11.dll", besides: game)
        let own = Fixture.nativeFake("the game's own dxgi")
        try own.write(to: game.deletingLastPathComponent().appending(path: "dxgi.dll"))

        try deploy(game, bottle, payload: fixture.makeDXMTPayload())

        let gameFolder = game.deletingLastPathComponent()
        #expect(Fixture.contents(target) == Fixture.dxmtFake("x64", "d3d11.dll"))
        #expect(Fixture.contents(gameFolder.appending(path: "dxgi.dll")) == own)
        #expect(!exists(gameFolder, "d3d10core.dll"))
        #expect(recordCount(bottle) == 0)
    }

    // MARK: - Once adopted

    @Test("A copy adopted by a deploy that completed is Whisky's, so a failed refresh takes it back")
    func adoptedCopyIsTakenBackByAFailedRefresh() throws {
        let bottle = try fixture.makeBottle()
        let game = try fixture.makeGame(in: bottle, folder: Self.otherFolder)
        try placeByHand("d3d11.dll", besides: game)
        try deploy(game, bottle, payload: fixture.makeDXMTPayload())
        #expect(recordCount(bottle) == 3)

        try deploy(game, bottle, payload: fixture.makeDXMTPayload(version: "2"), failingFor: "dxgi.dll")

        #expect(Fixture.holdsNoTrio(game.deletingLastPathComponent()))
        #expect(recordCount(bottle) == 0)
    }
}
