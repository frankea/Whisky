//
//  ExistingBottleTests.swift
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

@testable import WhiskyKit
import XCTest

final class ExistingBottleTests: XCTestCase {
    private var root = URL(filePath: "/dev/null")

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory.appending(path: "ExistingBottleTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    private func contents(of directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).sorted()
    }

    private func assertThrows(_ expected: ExistingBottleError, at url: URL, line: UInt = #line) {
        XCTAssertThrowsError(try BottleData.existingBottleSettings(at: url), line: line) { error in
            XCTAssertEqual(error as? ExistingBottleError, expected, line: line)
        }
    }

    // MARK: - existingBottleSettings

    func testReadsTheBottleNameFromMetadata() throws {
        let bottle = root.appending(path: "Bottle")
        try FileManager.default.createDirectory(at: bottle, withIntermediateDirectories: true)
        var settings = BottleSettings()
        settings.name = "Games"
        try PropertyListEncoder().encode(settings).write(to: bottle.appending(path: "Metadata.plist"))
        let before = try Data(contentsOf: bottle.appending(path: "Metadata.plist"))

        XCTAssertEqual(try BottleData.existingBottleSettings(at: bottle).name, "Games")
        // Reading never rewrites the bottle's metadata.
        XCTAssertEqual(try Data(contentsOf: bottle.appending(path: "Metadata.plist")), before)
        XCTAssertEqual(try contents(of: bottle), ["Metadata.plist"])
    }

    func testMissingPathIsRefusedAndNothingIsCreated() throws {
        let missing = root.appending(path: "Nope")
        assertThrows(.notFound, at: missing)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path(percentEncoded: false)))
        XCTAssertEqual(try contents(of: root), [])
    }

    func testFileIsRefused() throws {
        let file = root.appending(path: "file.txt")
        try Data("hi".utf8).write(to: file)
        assertThrows(.notADirectory, at: file)
    }

    func testDirectoryWithoutMetadataIsRefusedAndLeftAlone() throws {
        let folder = root.appending(path: "Folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        assertThrows(.missingMetadata, at: folder)
        XCTAssertEqual(try contents(of: folder), [])
    }

    func testUnreadableMetadataIsRefused() throws {
        let folder = root.appending(path: "Broken")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not a plist".utf8).write(to: folder.appending(path: "Metadata.plist"))
        assertThrows(.unreadableMetadata, at: folder)
    }

    // MARK: - bottleURL(forPath:currentDirectory:)

    func testAbsolutePathIsStandardized() {
        let url = BottleData.bottleURL(forPath: "/Users/me/Bottles/../Bottles/Games/", currentDirectory: "/tmp")
        XCTAssertEqual(url.path(percentEncoded: false), "/Users/me/Bottles/Games")
    }

    func testRelativePathResolvesAgainstTheCurrentDirectory() {
        let url = BottleData.bottleURL(forPath: "Bottles/Games", currentDirectory: "/Users/me")
        XCTAssertEqual(url.path(percentEncoded: false), "/Users/me/Bottles/Games")
    }

    func testTildeExpandsToHome() {
        let url = BottleData.bottleURL(forPath: "~/Games", currentDirectory: "/tmp")
        let home = (NSHomeDirectory() as NSString).appendingPathComponent("Games")
        XCTAssertEqual(url.path(percentEncoded: false), home)
    }
}
