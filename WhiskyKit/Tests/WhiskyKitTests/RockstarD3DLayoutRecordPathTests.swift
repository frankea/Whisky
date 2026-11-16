//
//  RockstarD3DLayoutRecordPathTests.swift
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

/// The layout record is a file in the bottle that anyone can edit, so its
/// paths must never lead a teardown or a diagnostics report out of `drive_c`.
@Suite("Rockstar layout record paths stay inside drive_c")
struct RockstarD3DLayoutRecordPathTests {
    let bottle: URL
    let driveC: URL
    let outside: URL

    init() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "rockstar-record-\(UUID().uuidString)")
        bottle = root.appending(path: "bottle")
        driveC = bottle.appending(path: "drive_c")
        outside = root.appending(path: "outside")
        for dir in [driveC.appending(path: "Program Files/Rockstar Games/Social Club"), outside] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        // What Wine does for drive_c/users/<name>/Documents: a link out of the bottle.
        try FileManager.default.createDirectory(
            at: driveC.appending(path: "users/crossover"), withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: driveC.appending(path: "users/crossover/Documents"), withDestinationURL: outside
        )
    }

    @Test("Keys Whisky writes are kept")
    func ownKeysAreKept() {
        for key in [
            "Program Files (x86)/Steam/bin/cef/cef.win64/d3d11.dll",
            "Program Files/Rockstar Games/Social Club/d3d10core.dll",
            "Program Files/Rockstar Games/Social Club"
        ] {
            #expect(DriveCRecordKey.isContained(key, in: driveC), "\(key)")
        }
    }

    @Test("Keys that leave drive_c are refused", arguments: [
        "", "/etc/hosts", "../outside/d3d11.dll", "Program Files/../../outside/d3d11.dll",
        "Program Files/./d3d11.dll", "Program Files//d3d11.dll", "Program Files\\d3d11.dll",
        "Program Files/d3d11.dll\n", "users/crossover/Documents/d3d11.dll",
        "users/crossover/Documents"
    ])
    func escapingKeysAreRefused(key: String) {
        #expect(!DriveCRecordKey.isContained(key, in: driveC))
    }

    @Test("Loading drops every entry that leaves drive_c, so a teardown never sees it")
    func loadDropsEscapingEntries() throws {
        let kept = "Program Files/Rockstar Games/Social Club/d3d11.dll"
        var record = RockstarD3DLayoutRecord(engineStamp: "11.19.0", sourceSHA256: "abc")
        record.copies = [
            kept: "1111",
            "../outside/d3d11.dll": "2222",
            "users/crossover/Documents/d3d11.dll": "3333",
            "/tmp/d3d11.dll": "4444"
        ]
        record.createdFolders = ["Program Files/Rockstar Games/Social Club", "../outside", "users/crossover/Documents"]
        try record.save(to: bottle)

        let loaded = try #require(RockstarD3DLayoutRecord.load(from: bottle))

        #expect(loaded.copies == [kept: "1111"])
        #expect(loaded.createdFolders == ["Program Files/Rockstar Games/Social Club"])
        #expect(loaded.engineStamp == "11.19.0")
    }
}
