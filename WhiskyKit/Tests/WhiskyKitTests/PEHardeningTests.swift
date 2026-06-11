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

// swiftlint:disable file_length
// Adversarial and valid-input PE fixtures are built inline, so the suite is long.

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

    // MARK: - Entry-count denial-of-service

    func testTruncatedHugeEntryCountParsesInBoundedTime() throws {
        // A table claims the maximum number of ID entries but the file holds none
        // of them. The per-table clamp must cap the loop to what fits in the file,
        // so this parses promptly and yields no spurious entries.
        var data = Data()
        data.append(tableHeader(idEntries: UInt16.max)) // claims 65535 entries; file has zero

        let start = Date()
        let table = try parseTable(data, name: "truncated_huge_count")
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertTrue(table.allEntries.isEmpty)
        XCTAssertLessThan(elapsed, 2.0, "Truncated huge-count table must parse in bounded time")
    }

    func testFanOutAmplificationCompletesQuickly() throws {
        // A root table whose many entries ALL point at the same oversized subtable.
        // Each sibling re-parses that subtable (a legal DAG), so without a global
        // budget this fans out into a huge number of processed entries. The shared
        // traversal budget must stop the walk and return promptly.
        let siblingCount: UInt16 = 8_000
        let subtableOffset = UInt32(16 + Int(siblingCount) * 8) // right after the root's entries

        var data = Data()
        data.append(tableHeader(idEntries: siblingCount))
        for _ in 0 ..< siblingCount {
            data.append(idEntry(id: 3, offset: subtableOffset, isDirectory: true))
        }
        // The shared subtable: itself claims the maximum entry count.
        data.append(tableHeader(idEntries: UInt16.max))
        // Pad so the subtable's claimed entries have file bytes to read, forcing the
        // budget (not just the clamp) to be the thing that stops the fan-out.
        data.append(Data(count: Int(UInt16.max) * 8))

        let start = Date()
        let table = try parseTable(data, name: "fan_out")
        let elapsed = Date().timeIntervalSince(start)

        // The walk completes (does not hang) and the budget bounds total work:
        // an un-budgeted fan-out would process ~524M entries (8,000 × 65,535).
        XCTAssertLessThanOrEqual(
            table.allEntries.count,
            100_000,
            "Global budget must bound the total processed entries"
        )
        XCTAssertLessThan(elapsed, 5.0, "Fan-out amplification must complete under the global budget")
    }
}

// MARK: - bestIcon() end-to-end

/// Exercises `PEFile.bestIcon()` through a full (synthetic) PE so the
/// nil-return-on-failure and the valid-icon render path both have coverage.
final class BestIconEndToEndTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appending(path: "best_icon_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // The icon edge of the synthetic bitmap. Stored height is doubled (image +
    // AND mask) by convention, and `renderBitmap` emits height/2 rows.
    private let iconEdge: Int32 = 4
    private let rsrcRawPointer: UInt32 = 0x400
    private let rsrcVirtualAddress: UInt32 = 0x2000

    private func littleEndianBytes(_ value: some FixedWidthInteger) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian) { Array($0) }
    }

    private func tableHeader(idEntries: UInt16) -> Data {
        var data = Data()
        data.append(contentsOf: littleEndianBytes(UInt32(0))) // characteristics
        data.append(contentsOf: littleEndianBytes(UInt32(0))) // timestamp
        data.append(contentsOf: littleEndianBytes(UInt16(0))) // major version
        data.append(contentsOf: littleEndianBytes(UInt16(0))) // minor version
        data.append(contentsOf: littleEndianBytes(UInt16(0))) // name entries
        data.append(contentsOf: littleEndianBytes(idEntries)) // id entries
        return data
    }

    private func idEntry(id: UInt32, offset: UInt32, isDirectory: Bool) -> Data {
        var data = Data()
        data.append(contentsOf: littleEndianBytes(id))
        let encoded = isDirectory ? (offset | 0x8000_0000) : offset
        data.append(contentsOf: littleEndianBytes(encoded))
        return data
    }

    private func dataEntryBytes(dataRVA: UInt32, size: UInt32) -> Data {
        var data = Data()
        data.append(contentsOf: littleEndianBytes(dataRVA))
        data.append(contentsOf: littleEndianBytes(size))
        data.append(contentsOf: littleEndianBytes(UInt32(0))) // codePage
        data.append(contentsOf: littleEndianBytes(UInt32(0))) // reserved
        return data
    }

    /// A valid 40-byte BITMAPINFOHEADER plus 32bpp BGRA pixel data for the
    /// rendered (image) half of the icon.
    private func iconBitmap(width: Int32, storedHeight: Int32) -> Data {
        var data = Data()
        data.append(contentsOf: littleEndianBytes(UInt32(40))) // biSize
        data.append(contentsOf: littleEndianBytes(width)) // biWidth
        data.append(contentsOf: littleEndianBytes(storedHeight)) // biHeight (doubled)
        data.append(contentsOf: littleEndianBytes(UInt16(1))) // planes
        data.append(contentsOf: littleEndianBytes(UInt16(32))) // bitCount → sampled32
        data.append(contentsOf: littleEndianBytes(UInt32(0))) // compression
        data.append(contentsOf: littleEndianBytes(UInt32(0))) // sizeImage
        data.append(contentsOf: littleEndianBytes(Int32(0))) // xPelsPerMeter
        data.append(contentsOf: littleEndianBytes(Int32(0))) // yPelsPerMeter
        data.append(contentsOf: littleEndianBytes(UInt32(0))) // clrUsed
        data.append(contentsOf: littleEndianBytes(UInt32(0))) // clrImportant

        let renderedRows = Int(abs(storedHeight) / 2)
        for _ in 0 ..< (renderedRows * Int(width)) {
            data.append(contentsOf: [0x10, 0x20, 0x30, 0xFF]) // BGRA opaque pixel
        }
        return data
    }

    /// The internal `.rsrc` section body: a conventional three-level icon tree
    /// (type → name → language) whose data entry points at `bitmap`.
    private func rsrcBody(bitmap: Data) -> Data {
        var body = Data()
        // root (type) @0 → name @24
        body.append(tableHeader(idEntries: 1))
        body.append(idEntry(id: 3, offset: 24, isDirectory: true)) // RT_ICON
        // name @24 → language @48
        body.append(tableHeader(idEntries: 1))
        body.append(idEntry(id: 1, offset: 48, isDirectory: true))
        // language @48 → data entry @72
        body.append(tableHeader(idEntries: 1))
        body.append(idEntry(id: 1_033, offset: 72, isDirectory: false))
        // data entry @72 (16 bytes) → bitmap @88
        let bitmapRelOffset = UInt32(88)
        let dataRVA = rsrcVirtualAddress + bitmapRelOffset
        body.append(dataEntryBytes(dataRVA: dataRVA, size: UInt32(bitmap.count)))
        // bitmap @88
        body.append(bitmap)
        return body
    }

    /// Assemble a complete PE32 whose `.rsrc` section carries `rsrcBody`.
    private func makePE(rsrcBody: Data) -> Data {
        var data = PEBuilder.createDOSHeader(peOffset: 0x80)
        while data.count < 0x80 {
            data.append(0x00)
        }
        data.append(contentsOf: [0x50, 0x45, 0x00, 0x00]) // "PE\0\0"
        data.append(PEBuilder.createCOFFHeader(numberOfSections: 1, sizeOfOptionalHeader: 0xE0))
        data.append(PEBuilder.createPE32OptionalHeader())
        data.append(PEBuilder.createSectionHeader(
            name: ".rsrc",
            virtualSize: UInt32(max(rsrcBody.count, 1)),
            virtualAddress: rsrcVirtualAddress,
            pointerToRawData: rsrcRawPointer
        ))
        while data.count < Int(rsrcRawPointer) {
            data.append(0x00)
        }
        data.append(rsrcBody)
        return data
    }

    private func writePE(_ data: Data, name: String) throws -> URL {
        let url = tempDir.appending(path: "\(name)_\(UUID().uuidString).exe")
        try data.write(to: url)
        return url
    }

    func testValidIconRendersNonEmptyImage() throws {
        let bitmap = iconBitmap(width: iconEdge, storedHeight: iconEdge * 2)
        let peData = makePE(rsrcBody: rsrcBody(bitmap: bitmap))
        let url = try writePE(peData, name: "valid_icon")

        let peFile = try PEFile(url: url)
        let icon = try XCTUnwrap(peFile.bestIcon(), "A valid icon resource must yield an image")
        XCTAssertTrue(icon.isValid)
        XCTAssertEqual(Int(icon.size.width), Int(iconEdge))
        XCTAssertEqual(Int(icon.size.height), Int(iconEdge))
    }

    func testUnparseableIconYieldsNilForFallback() throws {
        // A data entry whose RVA resolves outside the section, so the bitmap can't
        // be read and no renderable icon results: bestIcon() must be nil so the
        // caller falls back to a system icon.
        var body = Data()
        body.append(tableHeader(idEntries: 1)) // root @0 → name @24
        body.append(idEntry(id: 3, offset: 24, isDirectory: true))
        body.append(tableHeader(idEntries: 1)) // name @24 → language @48
        body.append(idEntry(id: 1, offset: 48, isDirectory: true))
        body.append(tableHeader(idEntries: 1)) // language @48 → data @72
        body.append(idEntry(id: 1_033, offset: 72, isDirectory: false))
        // dataRVA far outside any section → resolveRVA returns nil
        body.append(dataEntryBytes(dataRVA: 0xFFFF_0000, size: 0x40))

        let peData = makePE(rsrcBody: body)
        let url = try writePE(peData, name: "unparseable_icon")

        let peFile = try PEFile(url: url)
        XCTAssertNil(peFile.bestIcon(), "An unparseable icon resource must yield nil so the fallback triggers")
    }

    func testNearInt32MaxBitmapDimensionsReturnsNilQuickly() throws {
        // The bitmap header claims near-Int32.max width/height. renderBitmap must
        // reject the dimensions and return nil without an unbounded allocation.
        var bitmap = Data()
        bitmap.append(contentsOf: littleEndianBytes(UInt32(40))) // biSize
        bitmap.append(contentsOf: littleEndianBytes(Int32.max)) // biWidth
        bitmap.append(contentsOf: littleEndianBytes(Int32.max)) // biHeight
        bitmap.append(contentsOf: littleEndianBytes(UInt16(1))) // planes
        bitmap.append(contentsOf: littleEndianBytes(UInt16(32))) // bitCount
        bitmap.append(contentsOf: littleEndianBytes(UInt32(0))) // compression
        bitmap.append(contentsOf: littleEndianBytes(UInt32(0))) // sizeImage
        bitmap.append(contentsOf: littleEndianBytes(Int32(0))) // xPels
        bitmap.append(contentsOf: littleEndianBytes(Int32(0))) // yPels
        bitmap.append(contentsOf: littleEndianBytes(UInt32(0))) // clrUsed
        bitmap.append(contentsOf: littleEndianBytes(UInt32(0))) // clrImportant

        let peData = makePE(rsrcBody: rsrcBody(bitmap: bitmap))
        let url = try writePE(peData, name: "huge_dims")

        let peFile = try PEFile(url: url)
        let start = Date()
        let icon = peFile.bestIcon()
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertNil(icon, "Near-Int32.max bitmap dimensions must be rejected")
        XCTAssertLessThan(elapsed, 2.0, "Rejecting huge dimensions must be prompt, with no unbounded allocation")
    }
}
