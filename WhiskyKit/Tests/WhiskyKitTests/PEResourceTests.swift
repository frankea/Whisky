//
//  PEResourceTests.swift
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

// MARK: - ResourceType Tests

final class ResourceTypeTests: XCTestCase {
    func testResourceTypeIcon() {
        let iconType = ResourceType(rawValue: 3)
        XCTAssertEqual(iconType, .icon)
    }

    func testResourceTypeUnknownRawValue() {
        // The standard synthesized init(rawValue:) returns nil for invalid values
        let unknownType = ResourceType(rawValue: UInt32(999))
        XCTAssertNil(unknownType)
    }

    func testResourceTypeCustomInitWithNil() {
        // The custom init?(rawValue: UInt32?) handles nil by returning .unknown
        let nilType = ResourceType(rawValue: nil as UInt32?)
        XCTAssertEqual(nilType, .unknown)
    }

    func testResourceTypeCustomInitWithValidValue() {
        let iconType = ResourceType(rawValue: UInt32?(3))
        XCTAssertEqual(iconType, .icon)
    }

    func testResourceTypeCaseIterable() {
        let allCases = ResourceType.allCases
        XCTAssertTrue(allCases.contains(.icon))
        XCTAssertTrue(allCases.contains(.unknown))
    }

    func testResourceTypeHashable() {
        var set = Set<ResourceType>()
        set.insert(.icon)
        set.insert(.unknown)
        XCTAssertEqual(set.count, 2)
    }

    func testResourceTypeEquatable() {
        XCTAssertEqual(ResourceType.icon, ResourceType.icon)
        XCTAssertNotEqual(ResourceType.icon, ResourceType.unknown)
    }
}

// MARK: - Architecture from OptionalHeader Tests

final class ArchitectureFromOptionalHeaderTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appending(path: "arch_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testPE32ArchitectureIs32Bit() throws {
        let peData = PEBuilder.createMinimalPE32()
        let fileURL = tempDir.appending(path: "arch32.exe")
        try peData.write(to: fileURL)

        let peFile = try PEFile(url: fileURL)

        XCTAssertEqual(peFile.architecture, .x32)
        XCTAssertEqual(peFile.architecture.toString(), "32-bit")
    }

    func testPE32PlusArchitectureIs64Bit() throws {
        let peData = PEBuilder.createMinimalPE32Plus()
        let fileURL = tempDir.appending(path: "arch64.exe")
        try peData.write(to: fileURL)

        let peFile = try PEFile(url: fileURL)

        XCTAssertEqual(peFile.architecture, .x64)
        XCTAssertEqual(peFile.architecture.toString(), "64-bit")
    }
}

// MARK: - ResourceDataEntry Tests

final class ResourceDataEntryTests: XCTestCase {
    func testResolveRVAWithMatchingSection() throws {
        let entry = try createMockResourceDataEntry(dataRVA: 0x2500, size: 0x100, codePage: 0)

        let sections = try [
            createMockSection(name: ".text", virtualAddress: 0x1000, virtualSize: 0x1000, pointerToRawData: 0x400),
            createMockSection(name: ".rsrc", virtualAddress: 0x2000, virtualSize: 0x1000, pointerToRawData: 0x1400)
        ]

        let resolved = entry.resolveRVA(sections: sections)
        XCTAssertEqual(resolved, 0x1400 + 0x500)
    }

    func testResolveRVAWithNoMatchingSection() throws {
        let entry = try createMockResourceDataEntry(dataRVA: 0x9000, size: 0x100, codePage: 0)

        let sections = try [
            createMockSection(name: ".text", virtualAddress: 0x1000, virtualSize: 0x1000, pointerToRawData: 0x400)
        ]

        let resolved = entry.resolveRVA(sections: sections)
        XCTAssertNil(resolved)
    }

    private func createMockResourceDataEntry(
        dataRVA: UInt32,
        size: UInt32,
        codePage: UInt32
    ) throws -> ResourceDataEntry {
        var data = Data()
        data.append(contentsOf: withUnsafeBytes(of: dataRVA.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: size.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: codePage.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) })

        let tempURL = FileManager.default.temporaryDirectory.appending(path: "entry_\(UUID().uuidString).bin")
        try data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let handle = try FileHandle(forReadingFrom: tempURL)
        defer { try? handle.close() }

        guard let entry = ResourceDataEntry(handle: handle, offset: 0) else {
            throw PETestError.failedToCreateMockEntry
        }
        return entry
    }

    private func createMockSection(
        name: String,
        virtualAddress: UInt32,
        virtualSize: UInt32,
        pointerToRawData: UInt32
    ) throws -> PEFile.Section {
        var data = Data()

        var nameBytes = Array(name.utf8)
        while nameBytes.count < 8 {
            nameBytes.append(0)
        }
        data.append(contentsOf: nameBytes.prefix(8))

        data.append(contentsOf: withUnsafeBytes(of: virtualSize.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: virtualAddress.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0x1000).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: pointerToRawData.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) })

        let tempURL = FileManager.default.temporaryDirectory.appending(path: "section_\(UUID().uuidString).bin")
        try data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let handle = try FileHandle(forReadingFrom: tempURL)
        defer { try? handle.close() }

        guard let section = PEFile.Section(handle: handle, offset: 0) else {
            throw PETestError.failedToCreateMockSection
        }
        return section
    }
}

// MARK: - ResourceDirectoryEntry.ID Tests

final class ResourceDirectoryEntryIDTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appending(path: "rsrc_entry_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testDirectoryEntryWithIconType() throws {
        // Create entry data: type (UInt32) + offset (UInt32)
        var data = Data()
        // Type 3 = RT_ICON
        data.append(contentsOf: withUnsafeBytes(of: UInt32(3).littleEndian) { Array($0) })
        // Offset with high bit set (directory entry)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0x8000_0100).littleEndian) { Array($0) })

        let fileURL = tempDir.appending(path: "entry.bin")
        try data.write(to: fileURL)

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let entry = ResourceDirectoryEntry.ID(handle: handle, offset: 0)

        XCTAssertEqual(entry.type, .icon)
        XCTAssertTrue(entry.isDirectory)
        XCTAssertEqual(entry.offset, 0x0100)
    }

    func testDirectoryEntryWithDataOffset() throws {
        var data = Data()
        // Type 3 = RT_ICON (without high bit means data entry, not directory)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(3).littleEndian) { Array($0) })
        // Offset without high bit (data entry)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0x0000_0200).littleEndian) { Array($0) })

        let fileURL = tempDir.appending(path: "data_entry.bin")
        try data.write(to: fileURL)

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let entry = ResourceDirectoryEntry.ID(handle: handle, offset: 0)

        XCTAssertEqual(entry.type, .icon)
        XCTAssertFalse(entry.isDirectory)
        XCTAssertEqual(entry.offset, 0x0200)
    }

    func testDirectoryEntryWithUnknownType() throws {
        var data = Data()
        // Unknown type
        data.append(contentsOf: withUnsafeBytes(of: UInt32(999).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0x0000_0300).littleEndian) { Array($0) })

        let fileURL = tempDir.appending(path: "unknown_entry.bin")
        try data.write(to: fileURL)

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let entry = ResourceDirectoryEntry.ID(handle: handle, offset: 0)

        XCTAssertEqual(entry.type, .unknown)
    }
}

// MARK: - ResourceDirectoryTable Tests

final class ResourceDirectoryTableTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appending(path: "rsrc_table_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testEmptyResourceDirectoryTable() throws {
        // Create minimal resource directory table with no entries
        var data = Data()
        // Characteristics (UInt32)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) })
        // TimeDateStamp (UInt32)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0x5F5F_5F5F).littleEndian) { Array($0) })
        // MajorVersion (UInt16)
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
        // MinorVersion (UInt16)
        data.append(contentsOf: withUnsafeBytes(of: UInt16(2).littleEndian) { Array($0) })
        // NumberOfNameEntries (UInt16)
        data.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })
        // NumberOfIdEntries (UInt16)
        data.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })

        let fileURL = tempDir.appending(path: "empty_table.bin")
        try data.write(to: fileURL)

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let table = ResourceDirectoryTable(handle: handle, pointerToRawData: 0, types: nil)

        XCTAssertEqual(table.characteristics, 0)
        XCTAssertEqual(table.version.major, 1)
        XCTAssertEqual(table.version.minor, 2)
        XCTAssertEqual(table.numberOfNameEntries, 0)
        XCTAssertEqual(table.numberOfIdEntries, 0)
        XCTAssertTrue(table.subtables.isEmpty)
        XCTAssertTrue(table.entries.isEmpty)
        XCTAssertTrue(table.allEntries.isEmpty)
    }

    func testResourceDirectoryTableHashable() throws {
        var data = Data()
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })

        let fileURL = tempDir.appending(path: "hash_table.bin")
        try data.write(to: fileURL)

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let table1 = ResourceDirectoryTable(handle: handle, pointerToRawData: 0, types: nil)
        let table2 = ResourceDirectoryTable(handle: handle, pointerToRawData: 0, types: nil)

        XCTAssertEqual(table1, table2)
        XCTAssertEqual(table1.hashValue, table2.hashValue)
    }

    func testResourceDirectoryTableWithTypeFilter() throws {
        // Create table with one ID entry pointing to a data entry
        var data = Data()
        // Table header
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) }) // characteristics
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) }) // timestamp
        data.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) }) // major version
        data.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) }) // minor version
        data.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) }) // name entries
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // id entries: 1

        // Entry pointing to data at offset 24 (after header + this entry)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(3).littleEndian) { Array($0) }) // type: icon
        data.append(contentsOf: withUnsafeBytes(of: UInt32(24).littleEndian) { Array($0) }) // offset to data entry

        // Data entry at offset 24
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0x1000).littleEndian) { Array($0) }) // dataRVA
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0x100).littleEndian) { Array($0) }) // size
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) }) // codePage
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) }) // reserved

        let fileURL = tempDir.appending(path: "filter_table.bin")
        try data.write(to: fileURL)

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        // Filter for icon type
        let tableWithIcon = ResourceDirectoryTable(handle: handle, pointerToRawData: 0, types: [.icon])
        XCTAssertEqual(tableWithIcon.entries.count, 1)

        // Filter for unknown type (should exclude our icon entry)
        let tableWithUnknown = ResourceDirectoryTable(handle: handle, pointerToRawData: 0, types: [.unknown])
        XCTAssertTrue(tableWithUnknown.entries.isEmpty)
    }
}

// MARK: - Rosetta2 Tests

final class Rosetta2Tests: XCTestCase {
    func testRosettaInstalledPropertyExists() {
        // Just verify the property can be accessed without crashing
        let isInstalled = Rosetta2.isRosettaInstalled
        // On Apple Silicon Macs, this should return a boolean
        XCTAssertNotNil(isInstalled as Bool?)
    }
}
