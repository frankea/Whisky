//
//  BottleProgramDiscoveryTests.swift
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
@testable import WhiskyKit
import XCTest

/// Covers `Bottle.discoverInstalledExecutables`, the pure off-main-actor program
/// scan that powers the async installed-programs loading (whisky-app/whisky#574).
final class BottleProgramDiscoveryTests: XCTestCase {
    private var driveC: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        driveC = FileManager.default.temporaryDirectory
            .appending(path: "program_discovery_\(UUID().uuidString)")
            .appending(path: "drive_c")
        try FileManager.default.createDirectory(at: driveC, withIntermediateDirectories: true)
        // The temp dir lives under /var, a symlink to /private/var. FileManager's
        // directory enumerator canonicalises to /private/var, while URL/NSString
        // `resolvingSymlinksInPath` strip /private back off — so they never agree.
        // Use POSIX realpath to pin `driveC` to the same canonical form the
        // enumerator returns, so constructed and discovered URLs (and the
        // blocklist entry, compared by URL equality inside the helper) match.
        // Real bottles live under ~/Library/Containers, which isn't symlinked.
        driveC = Self.canonicalize(driveC)
    }

    /// Resolves a directory URL to its canonical filesystem path via `realpath`.
    private static func canonicalize(_ url: URL) -> URL {
        guard let resolved = realpath(url.path(percentEncoded: false), nil) else { return url }
        defer { free(resolved) }
        return URL(filePath: String(cString: resolved))
    }

    override func tearDownWithError() throws {
        if let root = driveC?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: root)
        }
        try super.tearDownWithError()
    }

    /// Creates an empty file at `drive_c/<relativePath>`, making parent dirs.
    @discardableResult
    private func touch(_ relativePath: String) throws -> URL {
        let url = driveC.appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: Data()))
        return url
    }

    func testDiscoversExecutablesAcrossBothProgramFilesTrees() throws {
        let game = try touch("Program Files/Game/game.exe")
        let tool = try touch("Program Files (x86)/Tools/tool.exe")

        let found = Bottle.discoverInstalledExecutables(driveC: driveC, blocklist: [])

        XCTAssertEqual(Set(found), [game, tool])
    }

    func testIgnoresNonExecutableFiles() throws {
        let game = try touch("Program Files/Game/game.exe")
        try touch("Program Files/Game/readme.txt")
        try touch("Program Files/Game/data.dll")

        let found = Bottle.discoverInstalledExecutables(driveC: driveC, blocklist: [])

        XCTAssertEqual(found, [game])
    }

    func testExcludesClickOnceCacheExecutables() throws {
        let real = try touch("Program Files/App/app.exe")
        try touch("Program Files/App/Apps/2.0/ABCDEF/cached.exe")

        let found = Bottle.discoverInstalledExecutables(driveC: driveC, blocklist: [])

        XCTAssertEqual(found, [real])
    }

    func testExcludesKnownNoiseExecutablesCaseInsensitively() throws {
        let game = try touch("Program Files/Game/game.exe")
        try touch("Program Files/Game/crashpad_handler.exe")
        // The match lower-cases the basename, so mixed-case noise is still excluded.
        try touch("Program Files/Game/SteamWebHelper.exe")

        let found = Bottle.discoverInstalledExecutables(driveC: driveC, blocklist: [])

        XCTAssertEqual(found, [game])
    }

    func testExcludesBlocklistedExecutables() throws {
        let keep = try touch("Program Files/Game/game.exe")
        let blocked = try touch("Program Files/Game/blocked.exe")

        let found = Bottle.discoverInstalledExecutables(driveC: driveC, blocklist: [blocked])

        XCTAssertEqual(found, [keep])
    }

    func testReturnsEmptyWhenNoProgramFilesPresent() {
        let found = Bottle.discoverInstalledExecutables(driveC: driveC, blocklist: [])

        XCTAssertTrue(found.isEmpty)
    }
}
