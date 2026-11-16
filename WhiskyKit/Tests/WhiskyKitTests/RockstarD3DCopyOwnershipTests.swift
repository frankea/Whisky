//
//  RockstarD3DCopyOwnershipTests.swift
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

/// Which of the Rockstar swap's copies a launch puts back, removes or leaves
/// alone: only files that are still Whisky's are ever removed, and a copy
/// that went missing is placed again (#382).
@Suite("Rockstar Direct3D copy ownership")
@MainActor
final class RockstarD3DCopyOwnershipTests {
    private let fixture: RockstarD3DFixture
    private let root: URL

    init() throws {
        fixture = try RockstarD3DFixture(prefix: "rockstar_ownership")
        root = fixture.root
        try fixture.installRockstar(socialClub: false)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    private func folder(_ key: String) -> URL {
        fixture.driveC.appending(path: key)
    }

    private var cef64: URL {
        folder(RockstarD3DFixture.steamCopyKeys[0])
    }

    private var cef7x64: URL {
        folder(RockstarD3DFixture.steamCopyKeys[1])
    }

    private func entries(_ folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).sorted()
    }

    // MARK: - Teardown

    @Test("A teardown removes only copies that are still Whisky's, by exact name, file and bytes")
    func teardownLeavesWhatIsNoLongerWhiskys() throws {
        try fixture.startSteam()
        // Something else's d3d11.dll where Whisky's copy was.
        let foreign = Data("steam's own".utf8)
        try foreign.write(to: cef64.appending(path: "d3d11.dll"))
        // A symbolic link, even one to DXVK's own file.
        let link = cef7x64.appending(path: "d3d10core.dll")
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(
            at: link, withDestinationURL: fixture.dxvk.appending(path: "x64/d3d10core.dll")
        )
        // DXVK's bytes under another spelling.
        let steamRoot = fixture.steamRoot
        try FileManager.default.removeItem(at: steamRoot.appending(path: "d3d11.dll"))
        try RockstarD3DFixture.dxvkBytes("x64", "d3d11.dll").write(to: steamRoot.appending(path: "D3D11.dll"))
        // A copy of a newer DXVK than the recorded one, as a swap that died
        // between placing it and saving its record leaves: the payload's bytes.
        try fixture.makeDXVK(version: "2")
        let newer = fixture.socialClub.appending(path: "d3d11.dll")
        try RockstarD3DFixture.dxvkBytes("x64", "d3d11.dll", version: "2").write(to: newer)
        fixture.bottle.settings.rockstarWineD3D = false

        try fixture.startSteam()

        #expect(RockstarD3DFixture.contents(cef64.appending(path: "d3d11.dll")) == foreign)
        #expect(Wine.rockstarIsSymbolicLink(link))
        #expect(try entries(steamRoot).contains("D3D11.dll"))
        #expect(!RockstarD3DFixture.exists(newer))
        for gone in [
            cef64.appending(path: "d3d10core.dll"), cef7x64.appending(path: "d3d11.dll"),
            steamRoot.appending(path: "d3d10core.dll"), fixture.socialClub.appending(path: "d3d10core.dll")
        ] {
            #expect(!RockstarD3DFixture.exists(gone), "\(gone.path(percentEncoded: false))")
        }
        // What was left is no longer on record, and nothing else is.
        #expect(!RockstarD3DLayoutRecord.exists(in: fixture.bottle.url))
    }

    @Test("A copy whose removal fails keeps its entry and the record, and the next launch removes it")
    func failedRemovalKeepsItsEntry() throws {
        try fixture.startSteam()
        fixture.bottle.settings.rockstarWineD3D = false
        let recorder = RockstarOpsRecorder()
        recorder.failAt = "removeCopy cef.win64"

        try fixture.startSteam(ops: recorder.ops)

        let record = try #require(fixture.record)
        #expect(record.copies.keys.sorted() == Wine.rockstarD3DCopyDLLs.map {
            RockstarD3DLayoutRecord.key(RockstarD3DFixture.steamCopyKeys[0], $0)
        }.sorted())
        #expect(RockstarD3DFixture.holdsDXVKCopies(cef64))
        #expect(RockstarD3DFixture.holdsNoCopies(cef7x64))

        try fixture.startSteam()

        #expect(RockstarD3DFixture.holdsNoCopies(cef64))
        #expect(!RockstarD3DLayoutRecord.exists(in: fixture.bottle.url))
    }

    // MARK: - Swap

    @Test("A copy deleted from a folder that is still there is placed again")
    func deletedCopyIsPlacedAgain() throws {
        try fixture.startSteam()
        let record = fixture.record
        try FileManager.default.removeItem(at: cef64.appending(path: "d3d11.dll"))

        #expect(try fixture.startSteam() == .swapped(source: fixture.d3d11Source))

        #expect(RockstarD3DFixture.holdsDXVKCopies(cef64))
        #expect(fixture.record == record)
    }

    @Test("Copies in a folder that no longer needs them are removed and taken off the record")
    func staleCopiesAreRemoved() throws {
        try fixture.startSteam()
        let kept = [cef64, cef7x64, fixture.socialClub].flatMap { folder in
            Wine.rockstarD3DCopyDLLs.map { folder.appending(path: $0) }
        }
        let before = kept.map(RockstarD3DFixture.identity)
        // Without a 64-bit overlay, the Steam root is no copy folder.
        try FileManager.default.removeItem(at: fixture.steamRoot.appending(path: "gameoverlayui64.exe"))

        #expect(try fixture.startSteam() == .swapped(source: fixture.d3d11Source))

        #expect(RockstarD3DFixture.holdsNoCopies(fixture.steamRoot))
        let keys = try #require(fixture.record).copies.keys
        #expect(!keys.contains { DXMTGameFolder.folderKey(ofCopy: $0) == RockstarD3DFixture.steamKey })
        #expect(keys.count == 6)
        #expect(kept.map(RockstarD3DFixture.identity) == before)
    }
}
