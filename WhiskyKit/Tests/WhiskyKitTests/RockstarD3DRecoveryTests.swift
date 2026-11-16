//
//  RockstarD3DRecoveryTests.swift
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

/// The Rockstar swap after a crash part way through, an engine or DXVK
/// update, and a Steam folder that moved: every case converges, and a
/// teardown leaves nothing of the swap behind (#382).
@Suite("Rockstar Direct3D swap recovery")
@MainActor
final class RockstarD3DRecoveryTests {
    private let fixture: RockstarD3DFixture
    private let root: URL

    init() throws {
        fixture = try RockstarD3DFixture(prefix: "rockstar_recovery")
        root = fixture.root
        try fixture.installRockstar(socialClub: false)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    private var copyFolders: [URL] {
        (RockstarD3DFixture.steamCopyKeys + [RockstarD3DFixture.socialClubKey]).map {
            fixture.driveC.appending(path: $0)
        }
    }

    // MARK: - Crashes

    @Test("A crash at any step converges on the next swap, and a teardown leaves no orphans", arguments: [
        ("createFolder", true), ("installCopy cef.win7x64", true), ("enableDXVK(source)", true),
        ("saveRecord(final)", true), ("createFolder", false), ("installCopy cef.win7x64", false),
        ("enableDXVK(source)", false), ("saveRecord(final)", false)
    ])
    func crashConverges(_ step: String, _ swapAgain: Bool) throws {
        let crash = RockstarOpsRecorder()
        crash.crashAt = step
        _ = try fixture.startSteam(ops: crash.ops)
        #expect(crash.crashed)
        // Whatever the crash left is on record.
        #expect(RockstarD3DLayoutRecord.exists(in: fixture.bottle.url))

        if swapAgain {
            #expect(try fixture.startSteam() == .swapped(source: fixture.d3d11Source))
            #expect(Wine.isStrippedCopy(fixture.system32("d3d11.dll"), of: fixture.d3d11Source))
            #expect(copyFolders.allSatisfy { RockstarD3DFixture.holdsDXVKCopies($0) })
            #expect(fixture.record?.system32D3D11 != nil)
        }

        fixture.bottle.settings.rockstarWineD3D = false
        #expect(try fixture.startSteam() == .degraded(.disabledByUser))
        #expect(RockstarD3DFixture.contents(fixture.system32("d3d11.dll"))
            == RockstarD3DFixture.dxvkBytes("x64", "d3d11.dll"))
        #expect(copyFolders.allSatisfy { RockstarD3DFixture.holdsNoCopies($0) })
        #expect(!RockstarD3DFixture.exists(fixture.socialClub))
        #expect(!RockstarD3DLayoutRecord.exists(in: fixture.bottle.url))
    }

    @Test("A crash in the middle of a teardown is finished by the next launch")
    func crashMidTeardown() throws {
        try fixture.startSteam()
        fixture.bottle.settings.rockstarWineD3D = false
        let crash = RockstarOpsRecorder()
        crash.crashAt = "removeCopy cef.win7x64"
        _ = try fixture.startSteam(ops: crash.ops)
        #expect(RockstarD3DLayoutRecord.exists(in: fixture.bottle.url))

        #expect(try fixture.startSteam() == .degraded(.disabledByUser))
        #expect(copyFolders.allSatisfy { RockstarD3DFixture.holdsNoCopies($0) })
        #expect(!RockstarD3DLayoutRecord.exists(in: fixture.bottle.url))
    }

    @Test("An unreadable record still makes a later launch tear down, leaving unknown files alone")
    func unreadableRecord() throws {
        try fixture.startSteam()
        try Data("not a plist".utf8).write(to: RockstarD3DLayoutRecord.url(in: fixture.bottle.url))
        fixture.bottle.settings.rockstarWineD3D = false

        try fixture.startSteam()

        #expect(RockstarD3DFixture.contents(fixture.system32("d3d11.dll"))
            == RockstarD3DFixture.dxvkBytes("x64", "d3d11.dll"))
        #expect(!RockstarD3DLayoutRecord.exists(in: fixture.bottle.url))
        // Nothing vouches for them any more, so the copies stay.
        #expect(copyFolders.allSatisfy { RockstarD3DFixture.holdsDXVKCopies($0) })
    }

    // MARK: - Updates

    @Test("A new engine makes the system32 copy again from its originals")
    func engineUpdateReinstalls() throws {
        try fixture.startSteam()
        try writeRuntimeVersion(at: fixture.library, 4, 8, 4)
        try fixture.writeOriginals(tag: " 4.8.4", stamp: "4.8.4")

        #expect(try fixture.startSteam() == .swapped(source: fixture.d3d11Source))

        #expect(Wine.isStrippedCopy(fixture.system32("d3d11.dll"), of: fixture.d3d11Source))
        #expect(fixture.record?.engineStamp == "4.8.4")
        #expect(fixture.record?.sourceSHA256 == RockstarD3DLayoutRecord.sha256(of: fixture.d3d11Source))
    }

    @Test("The same engine version with other bytes makes the copy again")
    func recutReinstalls() throws {
        try fixture.startSteam()
        let before = fixture.record?.sourceSHA256
        try fixture.writeOriginals(tag: " recut", stamp: "4.8.3")

        try fixture.startSteam()

        #expect(Wine.isStrippedCopy(fixture.system32("d3d11.dll"), of: fixture.d3d11Source))
        #expect(fixture.record?.sourceSHA256 != before)
        #expect(fixture.record?.system32D3D11 == RockstarD3DLayoutRecord.sha256(of: fixture.system32("d3d11.dll")))
    }

    @Test("Originals stamped for another engine tear the swap down")
    func staleOriginalsTearDown() throws {
        try fixture.startSteam()
        try writeRuntimeVersion(at: fixture.library, 4, 9, 0)

        let layout = try fixture.startSteam()

        guard case .degraded(.sourceUnavailable) = layout else {
            Issue.record("expected sourceUnavailable, got \(String(describing: layout))")
            return
        }
        #expect(!RockstarD3DLayoutRecord.exists(in: fixture.bottle.url))
        #expect(copyFolders.allSatisfy { RockstarD3DFixture.holdsNoCopies($0) })
    }

    @Test("A DXVK update refreshes every copy and records the new bytes")
    func dxvkUpdateRefreshesCopies() throws {
        try fixture.startSteam()
        try fixture.makeDXVK(version: "2")

        try fixture.startSteam()

        #expect(copyFolders.allSatisfy { RockstarD3DFixture.holdsDXVKCopies($0, version: "2") })
        let hash = RockstarD3DLayoutRecord.sha256(RockstarD3DFixture.dxvkBytes("x64", "d3d11.dll", version: "2"))
        #expect(fixture.record?.copies["\(RockstarD3DFixture.steamKey)/d3d11.dll"] == hash)
    }

    @Test("A direct DXMT launch that took system32's d3d11 is healed by the next Steam start")
    func dxmtOverwriteHeals() throws {
        try fixture.startSteam()
        try Data("dxmt d3d11".utf8).write(to: fixture.system32("d3d11.dll"))

        try fixture.startSteam()

        #expect(Wine.isStrippedCopy(fixture.system32("d3d11.dll"), of: fixture.d3d11Source))
    }

    @Test("Steam's Chromium folder moving takes its entries off the record and serves the new one")
    func renamedCefFolder() throws {
        try fixture.startSteam()
        let old = fixture.steamRoot.appending(path: "bin/cef/cef.win7x64")
        let new = fixture.steamRoot.appending(path: "bin/cef/cef.win11x64")
        try FileManager.default.moveItem(at: old, to: new)
        for dll in Wine.rockstarD3DCopyDLLs {
            try FileManager.default.removeItem(at: new.appending(path: dll))
        }

        try fixture.startSteam()

        let keys = try #require(fixture.record).copies.keys
        #expect(!keys.contains { $0.contains("cef.win7x64") })
        #expect(keys.contains { $0.contains("cef.win11x64") })
        #expect(RockstarD3DFixture.holdsDXVKCopies(new))
    }
}
