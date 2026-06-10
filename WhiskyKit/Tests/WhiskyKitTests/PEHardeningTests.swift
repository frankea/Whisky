//
//  PEHardeningTests.swift
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

// MARK: - Malformed PE Hardening

/// PE files are untrusted input (WhiskyThumbnail parses them automatically), so
/// crafted headers must never trap or hang the parser.
final class MalformedPEHardeningTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appending(path: "pe_hardening_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeSection(
        virtualSize: UInt32,
        virtualAddress: UInt32,
        pointerToRawData: UInt32
    ) throws -> PEFile.Section {
        let data = PEBuilder.createSectionHeader(
            name: ".rsrc",
            virtualSize: virtualSize,
            virtualAddress: virtualAddress,
            pointerToRawData: pointerToRawData
        )
        let fileURL = tempDir.appending(path: "section_\(UUID().uuidString).bin")
        try data.write(to: fileURL)
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        return try XCTUnwrap(PEFile.Section(handle: handle, offset: 0))
    }

    private func makeDataEntry(dataRVA: UInt32, size: UInt32) throws -> ResourceDataEntry {
        var data = Data()
        data.append(contentsOf: withUnsafeBytes(of: dataRVA.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: size.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) }) // codePage
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) }) // reserved
        let fileURL = tempDir.appending(path: "entry_\(UUID().uuidString).bin")
        try data.write(to: fileURL)
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        return try XCTUnwrap(ResourceDataEntry(handle: handle, offset: 0))
    }

    func testResolveRVASectionBoundsOverflowDoesNotTrap() throws {
        // virtualAddress + virtualSize exceeds UInt32.max in a crafted section header.
        let section = try makeSection(virtualSize: 0x20, virtualAddress: 0xFFFF_FFF0, pointerToRawData: 0x200)
        let entry = try makeDataEntry(dataRVA: 0xFFFF_FFF5, size: 16)
        XCTAssertEqual(entry.resolveRVA(sections: [section]), 0x205)
    }

    func testResolveRVAFileOffsetOverflowReturnsNil() throws {
        // pointerToRawData + (dataRVA - virtualAddress) exceeds UInt32.max.
        let section = try makeSection(virtualSize: 0x100, virtualAddress: 0x1000, pointerToRawData: 0xFFFF_FFF0)
        let entry = try makeDataEntry(dataRVA: 0x1080, size: 16)
        XCTAssertNil(entry.resolveRVA(sections: [section]))
    }

    func testCyclicResourceDirectoryTerminates() throws {
        // Root table whose single directory entry points back at the root (offset 0).
        var data = Data()
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) }) // characteristics
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) }) // timestamp
        data.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) }) // major version
        data.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) }) // minor version
        data.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) }) // name entries
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // id entries: 1

        // Directory entry (high bit set) whose subtable offset is 0 — the root itself.
        data.append(contentsOf: withUnsafeBytes(of: UInt32(3).littleEndian) { Array($0) }) // type: icon
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0x8000_0000).littleEndian) { Array($0) })

        let fileURL = tempDir.appending(path: "cyclic_table.bin")
        try data.write(to: fileURL)
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let table = ResourceDirectoryTable(handle: handle, pointerToRawData: 0, types: nil)
        XCTAssertTrue(table.allEntries.isEmpty)
    }

    // MARK: - Resource tree shape (recursion guard boundaries)

    private func tableHeader(idEntries: UInt16) -> Data {
        var data = Data()
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) }) // characteristics
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) }) // timestamp
        data.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) }) // major version
        data.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) }) // minor version
        data.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) }) // name entries
        data.append(contentsOf: withUnsafeBytes(of: idEntries.littleEndian) { Array($0) }) // id entries
        return data
    }

    private func idEntry(id: UInt32, offset: UInt32, isDirectory: Bool) -> Data {
        var data = Data()
        data.append(contentsOf: withUnsafeBytes(of: id.littleEndian) { Array($0) })
        let encodedOffset = isDirectory ? (offset | 0x8000_0000) : offset
        data.append(contentsOf: withUnsafeBytes(of: encodedOffset.littleEndian) { Array($0) })
        return data
    }

    private func dataEntryBytes(dataRVA: UInt32, size: UInt32) -> Data {
        var data = Data()
        data.append(contentsOf: withUnsafeBytes(of: dataRVA.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: size.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) }) // codePage
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) }) // reserved
        return data
    }

    private func parseTable(_ data: Data, name: String) throws -> ResourceDirectoryTable {
        let fileURL = tempDir.appending(path: "\(name)_\(UUID().uuidString).bin")
        try data.write(to: fileURL)
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        return ResourceDirectoryTable(handle: handle, pointerToRawData: 0, types: nil)
    }

    func testLegitimateThreeLevelTreeParses() throws {
        // The conventional icon layout: type → name → language → data entry.
        // The recursion guards must NOT truncate this legal three-level tree.
        var data = Data()
        data.append(tableHeader(idEntries: 1)) // root (type) @0
        data.append(idEntry(id: 3, offset: 24, isDirectory: true)) // → name @24
        data.append(tableHeader(idEntries: 1)) // name @24
        data.append(idEntry(id: 1, offset: 48, isDirectory: true)) // → language @48
        data.append(tableHeader(idEntries: 1)) // language @48
        data.append(idEntry(id: 1_033, offset: 72, isDirectory: false)) // → data @72
        data.append(dataEntryBytes(dataRVA: 0x1000, size: 0x100)) // @72

        let table = try parseTable(data, name: "three_level")
        let entries = table.allEntries
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.dataRVA, 0x1000)
        XCTAssertEqual(entries.first?.size, 0x100)
    }

    func testFourthLevelTableIsTruncated() throws {
        // A directory entry at the language level (depth 2) points to an illegal
        // fourth table level. The depth cap must drop it, so the data entry below
        // it never appears.
        var data = Data()
        data.append(tableHeader(idEntries: 1)) // root @0
        data.append(idEntry(id: 3, offset: 24, isDirectory: true)) // → name @24
        data.append(tableHeader(idEntries: 1)) // name @24
        data.append(idEntry(id: 1, offset: 48, isDirectory: true)) // → language @48
        data.append(tableHeader(idEntries: 1)) // language @48
        data.append(idEntry(id: 1_033, offset: 72, isDirectory: true)) // → illegal 4th table @72
        data.append(tableHeader(idEntries: 1)) // 4th table @72
        data.append(idEntry(id: 1, offset: 96, isDirectory: false)) // → data @96
        data.append(dataEntryBytes(dataRVA: 0x2000, size: 0x40)) // @96

        let table = try parseTable(data, name: "four_level")
        XCTAssertTrue(table.allEntries.isEmpty)
    }

    func testSharedSubtableParsesOnEveryBranch() throws {
        // Two sibling directory entries point at the SAME subtable offset — a legal
        // DAG, not a cycle. The path-scoped visited set must let both branches parse
        // (the data entry appears once per referencing branch), not drop the second.
        var data = Data()
        data.append(tableHeader(idEntries: 2)) // root @0, two entries → shared name @32
        data.append(idEntry(id: 3, offset: 32, isDirectory: true))
        data.append(idEntry(id: 14, offset: 32, isDirectory: true))
        data.append(tableHeader(idEntries: 1)) // shared name @32
        data.append(idEntry(id: 1, offset: 56, isDirectory: false)) // → data @56
        data.append(dataEntryBytes(dataRVA: 0x3000, size: 0x10)) // @56

        let table = try parseTable(data, name: "shared_subtable")
        let entries = table.allEntries
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.allSatisfy { $0.dataRVA == 0x3000 })
    }
}
