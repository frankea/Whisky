//
//  DXMTGameFolderRecordPathTests.swift
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

import CryptoKit
import Foundation
import Testing
@testable import WhiskyKit

/// The DXMT game folder record is a file in the bottle that anyone can edit,
/// so its paths must never lead a removal out of `drive_c`.
@Suite("DXMT game folder record paths stay inside drive_c")
@MainActor
final class DXMTGameFolderRecordPathTests {
    private let fixture: DXMTGameFolderFixture
    private typealias Fixture = DXMTGameFolderFixture

    init() throws {
        fixture = try DXMTGameFolderFixture(prefix: "dxmt_record_paths")
    }

    deinit {
        fixture.cleanUp()
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// A folder outside the bottle holding DXMT's trio, as a removal would find it.
    private func outsideTrio() throws -> URL {
        let outside = fixture.root.appending(path: "outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        for dll in Fixture.trio {
            try Fixture.dxmtFake("x64", dll).write(to: outside.appending(path: dll))
        }
        return outside
    }

    /// Record keys that name `outside`'s trio from inside the test game's
    /// Steam install, so the game's launches treat them as the game's own.
    private func escapingCopies(_ bottle: Bottle, outside: URL) throws -> [String: String] {
        // What Wine does for drive_c/users/<name>/Documents: a link out of the bottle.
        let link = bottle.url.appending(path: "drive_c").appending(path: Fixture.gameFolder).appending(path: "link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let upward = Fixture.gameFolder + "/../../../../../../../outside"
        var copies: [String: String] = [:]
        for dll in Fixture.trio {
            let hash = Self.sha256(Fixture.dxmtFake("x64", dll))
            copies["\(Fixture.gameFolder)/link/\(dll)"] = hash
            copies["\(upward)/\(dll)"] = hash
            copies[outside.appending(path: dll).path(percentEncoded: false)] = hash
        }
        return copies
    }

    @Test("A removal leaves files outside drive_c alone, whatever the record names")
    func removalStaysInsideDriveC() throws {
        let bottle = try fixture.makeBottle(.dxmt)
        let game = try fixture.makeGame(in: bottle)
        let payload = try fixture.makeDXMTPayload()
        let outside = try outsideTrio()
        Wine.reconcileDXMTGameFolders(.deploy, executables: [game], bottleURL: bottle.url, payloadRoot: payload)
        #expect(Fixture.holdsDXMT(game.deletingLastPathComponent()))

        var record = DXMTGameFolderRecord.load(from: bottle.url)
        try record.copies.merge(escapingCopies(bottle, outside: outside)) { own, _ in own }
        try record.save(to: bottle.url)

        Wine.reconcileDXMTGameFolders(.remove, executables: [game], bottleURL: bottle.url, payloadRoot: payload)

        #expect(Fixture.holdsNoTrio(game.deletingLastPathComponent()))
        #expect(Fixture.holdsDXMT(outside))
    }

    @Test("A deploy writes nothing outside drive_c, whatever the record names")
    func deployStaysInsideDriveC() throws {
        let bottle = try fixture.makeBottle(.dxmt)
        let game = try fixture.makeGame(in: bottle)
        let payload = try fixture.makeDXMTPayload(version: "2")
        let outside = try outsideTrio()
        try DXMTGameFolderRecord(copies: escapingCopies(bottle, outside: outside)).save(to: bottle.url)

        Wine.reconcileDXMTGameFolders(.deploy, executables: [game], bottleURL: bottle.url, payloadRoot: payload)

        #expect(Fixture.holdsDXMT(game.deletingLastPathComponent(), version: "2"))
        #expect(Fixture.holdsDXMT(outside))
    }

    @Test("Loading drops every copy that leaves drive_c")
    func loadDropsEscapingCopies() throws {
        let bottle = try fixture.makeBottle(.dxmt)
        _ = try fixture.makeGame(in: bottle)
        let outside = try outsideTrio()
        let kept = [
            "\(Fixture.gameFolder)/d3d11.dll": "1111",
            "d3d11.dll": "2222"
        ]
        let escaping = try escapingCopies(bottle, outside: outside).merging([
            "": "3333",
            "\(Fixture.gameFolder)/./d3d11.dll": "4444",
            "\(Fixture.gameFolder)//d3d11.dll": "5555",
            "\(Fixture.gameFolder)\\d3d11.dll": "6666"
        ]) { first, _ in first }
        try DXMTGameFolderRecord(copies: kept.merging(escaping) { first, _ in first }).save(to: bottle.url)

        #expect(DXMTGameFolderRecord.load(from: bottle.url).copies == kept)
    }
}
