//
//  LegacyBottleImportTests.swift
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
import SemanticVersion
@testable import WhiskyKit
import XCTest

final class LegacyBottleImportTests: XCTestCase {
    private var container: URL!

    override func setUpWithError() throws {
        container = FileManager.default.temporaryDirectory.appending(path: "legacy_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: container)
    }

    /// Creates a directory under `parent`; when `valid` it also gets the `Metadata.plist`
    /// marker that identifies a real bottle on disk.
    @discardableResult
    private func makeBottle(_ name: String, in parent: URL, valid: Bool = true) throws -> URL {
        let dir = parent.appending(path: name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if valid {
            let metadata = dir.appending(path: "Metadata").appendingPathExtension("plist")
            try Data("<plist></plist>".utf8).write(to: metadata)
        }
        return dir.standardizedFileURL
    }

    /// Matches the on-disk shape of the original app's `BottleVM.plist` (we only need `paths`).
    private struct Registry: Encodable { var paths: [URL] }

    private func writeRegistry(_ paths: [URL]) throws {
        let url = container.appending(path: "BottleVM").appendingPathExtension("plist")
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        try encoder.encode(Registry(paths: paths)).write(to: url)
    }

    private func bottlesDir() throws -> URL {
        let dir = container.appending(path: "Bottles")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testDiscoversValidBottlesAndSkipsNonBottles() throws {
        let bottles = try bottlesDir()
        let valid1 = try makeBottle("a", in: bottles)
        let valid2 = try makeBottle("b", in: bottles)
        try makeBottle("not-a-bottle", in: bottles, valid: false)

        let found = LegacyBottleImport.importableBottleURLs(legacyContainer: container, existingPaths: [])
        XCTAssertEqual(Set(found), Set([valid1, valid2]))
    }

    func testExcludesAlreadyImportedPaths() throws {
        let bottles = try bottlesDir()
        let alreadyHave = try makeBottle("a", in: bottles)
        let fresh = try makeBottle("b", in: bottles)

        let found = LegacyBottleImport.importableBottleURLs(
            legacyContainer: container,
            existingPaths: [alreadyHave]
        )
        XCTAssertEqual(found, [fresh])
    }

    func testIncludesCustomPathBottlesKnownOnlyToTheRegistry() throws {
        // A bottle stored outside the default Bottles directory — discoverable only via the registry.
        let custom = try makeBottle("custom-location", in: container)
        try writeRegistry([custom])

        let found = LegacyBottleImport.importableBottleURLs(legacyContainer: container, existingPaths: [])
        XCTAssertEqual(found, [custom])
    }

    func testDeduplicatesAcrossRegistryAndScan() throws {
        let bottles = try bottlesDir()
        let shared = try makeBottle("a", in: bottles)
        try writeRegistry([shared]) // present in both the registry and the directory scan

        let found = LegacyBottleImport.importableBottleURLs(legacyContainer: container, existingPaths: [])
        XCTAssertEqual(found, [shared])
    }

    func testImportableBottlesCarryNamesWithDirectoryFallback() throws {
        let bottles = try bottlesDir()
        // The dummy Metadata.plist isn't a decodable BottleSettings, so the name should
        // fall back to the directory name (and crucially, the read must not rewrite metadata).
        let bottle = try makeBottle("my-bottle", in: bottles)
        let metadata = bottle.appending(path: "Metadata").appendingPathExtension("plist")
        let before = try Data(contentsOf: metadata)

        let discovered = LegacyBottleImport.importableBottles(legacyContainer: container, existingPaths: [])
        XCTAssertEqual(discovered.map(\.url), [bottle])
        XCTAssertEqual(discovered.first?.name, "my-bottle")

        // Discovery is non-destructive: the original metadata is untouched.
        XCTAssertEqual(try Data(contentsOf: metadata), before)
    }

    func testReadsRealNameWithoutRewritingMetadata() throws {
        let bottles = try bottlesDir()
        let dir = bottles.appending(path: "real-bottle")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let metadata = dir.appending(path: "Metadata").appendingPathExtension("plist")

        var settings = BottleSettings()
        settings.name = "My Real Bottle"
        // Deliberately differ from the current default so the writing BottleSettings.decode(from:)
        // path would rewrite this file — discovery must not.
        settings.wineVersion = SemanticVersion(0, 0, 1)
        try settings.encode(to: metadata)
        let before = try Data(contentsOf: metadata)

        let discovered = LegacyBottleImport.importableBottles(legacyContainer: container, existingPaths: [])
        XCTAssertEqual(discovered.map(\.url), [dir.standardizedFileURL])
        XCTAssertEqual(discovered.first?.name, "My Real Bottle")
        XCTAssertEqual(
            try Data(contentsOf: metadata),
            before,
            "discovery must not rewrite the original bottle's metadata"
        )
    }

    func testExcludesRegistryEntriesWhoseDirectoryIsGone() throws {
        // The original registry can list a bottle whose directory was since deleted; it must
        // not be offered for import (no Metadata.plist marker to validate).
        let bottles = try bottlesDir()
        let present = try makeBottle("present", in: bottles)
        let deleted = container.appending(path: "Bottles").appending(path: "deleted").standardizedFileURL
        try writeRegistry([present, deleted])

        let found = LegacyBottleImport.importableBottleURLs(legacyContainer: container, existingPaths: [])
        XCTAssertEqual(found, [present])
    }

    func testReturnsEmptyWhenContainerMissing() {
        let missing = FileManager.default.temporaryDirectory.appending(path: "missing_\(UUID().uuidString)")
        XCTAssertEqual(LegacyBottleImport.importableBottleURLs(legacyContainer: missing, existingPaths: []), [])
        XCTAssertFalse(LegacyBottleImport.legacyContainerExists(at: missing))
    }

    func testLegacyContainerExists() {
        XCTAssertTrue(LegacyBottleImport.legacyContainerExists(at: container))
    }
}
