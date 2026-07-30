//
//  BottleDataTests.swift
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

final class BottleDataTests: XCTestCase {
    private var tempDir: URL!
    private var entriesFile: URL!

    /// Mirror of the paths-only fallback shape `encodeFallback()` writes,
    /// which the full decoder cannot read back on its own.
    private struct MinimalShape: Codable {
        var paths: [URL]
    }

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        entriesFile = tempDir.appendingPathComponent("BottleVM.plist")
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        tempDir = nil
        entriesFile = nil
    }

    // MARK: - First run

    func testFirstRunCreatesEmptyRegistryFile() {
        let data = BottleData(entriesFile: entriesFile)

        XCTAssertTrue(data.paths.isEmpty)
        XCTAssertNil(data.corruptRegistryBackupURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: entriesFile.path(percentEncoded: false)))
    }

    // MARK: - Round trip

    func testRegisterBottlePathPersistsAndRoundTrips() {
        var data = BottleData(entriesFile: entriesFile)
        let bottle = tempDir.appendingPathComponent("Bottles").appendingPathComponent(UUID().uuidString)

        XCTAssertTrue(data.registerBottlePath(bottle))

        let reloaded = BottleData(entriesFile: entriesFile)
        XCTAssertEqual(reloaded.paths, [bottle])
        XCTAssertNil(reloaded.corruptRegistryBackupURL)
    }

    func testRegisterBottlePathIsIdempotent() {
        var data = BottleData(entriesFile: entriesFile)
        let bottle = tempDir.appendingPathComponent("Bottle")

        XCTAssertTrue(data.registerBottlePath(bottle))
        XCTAssertTrue(data.registerBottlePath(bottle))

        XCTAssertEqual(data.paths, [bottle])
        XCTAssertEqual(BottleData(entriesFile: entriesFile).paths, [bottle])
    }

    // MARK: - Corrupt registry (issue #61)

    func testCorruptRegistryIsBackedUpNotOverwritten() throws {
        let garbage = Data("definitely not a plist".utf8)
        try garbage.write(to: entriesFile)

        let data = BottleData(entriesFile: entriesFile)

        // The unreadable registry must be preserved, byte for byte, in a
        // sibling backup file — not silently clobbered by the fresh registry.
        XCTAssertTrue(data.paths.isEmpty)
        let backupURL = try XCTUnwrap(data.corruptRegistryBackupURL)
        XCTAssertTrue(backupURL.lastPathComponent.hasPrefix("BottleVM.corrupt-"))
        XCTAssertEqual(backupURL.deletingLastPathComponent(), entriesFile.deletingLastPathComponent())
        XCTAssertEqual(try Data(contentsOf: backupURL), garbage)

        // A fresh, readable registry takes the corrupt file's place.
        let reloaded = BottleData(entriesFile: entriesFile)
        XCTAssertTrue(reloaded.paths.isEmpty)
        XCTAssertNil(reloaded.corruptRegistryBackupURL)
    }

    // MARK: - Orphaned bottle scan (issue #145)

    /// Creates a bottle directory with a decodable Metadata.plist, mirroring
    /// what a real creation leaves on disk.
    @discardableResult
    private func makeBottleDir(named name: String, in dir: URL) throws -> URL {
        let bottleDir = dir.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: bottleDir, withIntermediateDirectories: true)
        var settings = BottleSettings()
        settings.name = name
        try settings.encode(to: bottleDir.appendingPathComponent("Metadata.plist"))
        return bottleDir
    }

    func testOrphanScanFindsUnregisteredBottle() throws {
        let scanDir = tempDir.appendingPathComponent("Bottles")
        let bottleDir = try makeBottleDir(named: "Steam Stuff", in: scanDir)

        let data = BottleData(entriesFile: entriesFile)
        let orphans = data.orphanedBottles(in: scanDir)

        XCTAssertEqual(orphans.map(\.name), ["Steam Stuff"])
        // Compare resolved paths: the listing yields /private/var-style URLs
        // where the test constructed /var-style ones.
        XCTAssertEqual(
            orphans.map { $0.url.resolvingSymlinksInPath().path },
            [bottleDir.resolvingSymlinksInPath().path]
        )
    }

    func testOrphanScanSkipsRegisteredBottles() throws {
        let scanDir = tempDir.appendingPathComponent("Bottles")
        let bottleDir = try makeBottleDir(named: "Registered", in: scanDir)

        var data = BottleData(entriesFile: entriesFile)
        XCTAssertTrue(data.registerBottlePath(bottleDir))

        XCTAssertTrue(data.orphanedBottles(in: scanDir).isEmpty)
    }

    func testOrphanScanMatchesRegistrationDespiteTrailingSlash() throws {
        // contentsOfDirectory yields directory URLs with a trailing slash;
        // registered paths are stored without one. The comparison must not
        // report a registered bottle as orphaned over that difference.
        let scanDir = tempDir.appendingPathComponent("Bottles")
        let bottleDir = try makeBottleDir(named: "Slashed", in: scanDir)

        var data = BottleData(entriesFile: entriesFile)
        XCTAssertTrue(data.registerBottlePath(URL(fileURLWithPath: bottleDir.path + "/", isDirectory: true)))

        XCTAssertTrue(data.orphanedBottles(in: scanDir).isEmpty)
    }

    func testOrphanScanSkipsDirsWithoutMetadataAndPlainFiles() throws {
        let scanDir = tempDir.appendingPathComponent("Bottles")
        try FileManager.default.createDirectory(
            at: scanDir.appendingPathComponent("no-metadata"),
            withIntermediateDirectories: true
        )
        try Data("not a bottle".utf8).write(to: scanDir.appendingPathComponent("stray-file"))

        let data = BottleData(entriesFile: entriesFile)
        XCTAssertTrue(data.orphanedBottles(in: scanDir).isEmpty)
    }

    func testOrphanScanSkipsCorruptMetadata() throws {
        let scanDir = tempDir.appendingPathComponent("Bottles")
        let bottleDir = scanDir.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: bottleDir, withIntermediateDirectories: true)
        let metadataURL = bottleDir.appendingPathComponent("Metadata.plist")
        let garbage = Data("garbage".utf8)
        try garbage.write(to: metadataURL)

        let data = BottleData(entriesFile: entriesFile)

        XCTAssertTrue(data.orphanedBottles(in: scanDir).isEmpty)
        // The probe must be side-effect free: no quarantine, no default rewrite.
        XCTAssertEqual(try Data(contentsOf: metadataURL), garbage)
    }

    func testOrphanScanSortsByName() throws {
        let scanDir = tempDir.appendingPathComponent("Bottles")
        try makeBottleDir(named: "zeta", in: scanDir)
        try makeBottleDir(named: "Alpha", in: scanDir)

        let data = BottleData(entriesFile: entriesFile)
        XCTAssertEqual(data.orphanedBottles(in: scanDir).map(\.name), ["Alpha", "zeta"])
    }

    func testOrphanScanMissingDirectoryReturnsEmpty() {
        let data = BottleData(entriesFile: entriesFile)
        XCTAssertTrue(data.orphanedBottles(in: tempDir.appendingPathComponent("nope")).isEmpty)
    }

    // MARK: - Fallback-format salvage

    func testMinimalFallbackFormatIsSalvagedWithoutBackup() throws {
        // Simulate a registry left behind by encodeFallback(): paths only,
        // no fileVersion, unreadable by the primary decoder.
        let bottle = tempDir.appendingPathComponent("SalvagedBottle")
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        try encoder.encode(MinimalShape(paths: [bottle])).write(to: entriesFile)

        let data = BottleData(entriesFile: entriesFile)

        // The registered path survives, nothing is treated as corrupt, and
        // the file is upgraded in place to the full format.
        XCTAssertEqual(data.paths, [bottle])
        XCTAssertNil(data.corruptRegistryBackupURL)

        let reloaded = BottleData(entriesFile: entriesFile)
        XCTAssertEqual(reloaded.paths, [bottle])
        XCTAssertNil(reloaded.corruptRegistryBackupURL)
    }
}
