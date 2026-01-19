//
//  PETests.swift
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

// MARK: - PEFile Tests

final class PEFileTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appending(path: "pe_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testValidPE32File() throws {
        let peData = PEBuilder.createMinimalPE32()
        let fileURL = tempDir.appending(path: "test32.exe")
        try peData.write(to: fileURL)

        let peFile = try PEFile(url: fileURL)

        XCTAssertNotNil(peFile.coffFileHeader)
        XCTAssertNotNil(peFile.optionalHeader)
        XCTAssertFalse(peFile.sections.isEmpty)
    }

    func testValidPE32PlusFile() throws {
        let peData = PEBuilder.createMinimalPE32Plus()
        let fileURL = tempDir.appending(path: "test64.exe")
        try peData.write(to: fileURL)

        let peFile = try PEFile(url: fileURL)

        XCTAssertNotNil(peFile.coffFileHeader)
        XCTAssertNotNil(peFile.optionalHeader)
        XCTAssertEqual(peFile.optionalHeader?.magic, .pe32Plus)
    }

    func testInvalidPEFileThrows() {
        let invalidData = Data([0x00, 0x01, 0x02, 0x03])
        let fileURL = tempDir.appending(path: "invalid.exe")
        try? invalidData.write(to: fileURL)

        XCTAssertThrowsError(try PEFile(url: fileURL)) { error in
            XCTAssertTrue(error is PEError)
        }
    }

    func testNonExistentFileThrows() {
        let nonExistent = tempDir.appending(path: "nonexistent.exe")

        XCTAssertThrowsError(try PEFile(url: nonExistent))
    }

    func testPEFileWithCorruptDOSHeader() {
        // Valid MZ signature but invalid PE offset
        var data = Data([0x4D, 0x5A])
        data.append(contentsOf: [UInt8](repeating: 0, count: 58))
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0xFFFF_FFFF).littleEndian) { Array($0) })

        let fileURL = tempDir.appending(path: "corrupt.exe")
        try? data.write(to: fileURL)

        XCTAssertThrowsError(try PEFile(url: fileURL))
    }

    func testPEFileSections() throws {
        let peData = PEBuilder.createMinimalPE32()
        let fileURL = tempDir.appending(path: "sections.exe")
        try peData.write(to: fileURL)

        let peFile = try PEFile(url: fileURL)

        XCTAssertEqual(peFile.sections.count, 1)
        XCTAssertEqual(peFile.sections.first?.name, ".text")
    }

    func testPEFileArchitecture() throws {
        let pe32Data = PEBuilder.createMinimalPE32()
        let pe32URL = tempDir.appending(path: "arch32.exe")
        try pe32Data.write(to: pe32URL)

        let pe32File = try PEFile(url: pe32URL)
        XCTAssertEqual(pe32File.architecture, .x32)

        let pe64Data = PEBuilder.createMinimalPE32Plus()
        let pe64URL = tempDir.appending(path: "arch64.exe")
        try pe64Data.write(to: pe64URL)

        let pe64File = try PEFile(url: pe64URL)
        XCTAssertEqual(pe64File.architecture, .x64)
    }

    func testPEFileEquatable() throws {
        let peData = PEBuilder.createMinimalPE32()
        let fileURL = tempDir.appending(path: "eq.exe")
        try peData.write(to: fileURL)

        let pe1 = try PEFile(url: fileURL)
        let pe2 = try PEFile(url: fileURL)

        XCTAssertEqual(pe1, pe2)
    }

    func testPEFileHashable() throws {
        let peData = PEBuilder.createMinimalPE32()
        let fileURL = tempDir.appending(path: "hash.exe")
        try peData.write(to: fileURL)

        let pe1 = try PEFile(url: fileURL)
        let pe2 = try PEFile(url: fileURL)

        XCTAssertEqual(pe1.hashValue, pe2.hashValue)
    }
}

// MARK: - COFFFileHeader Tests

final class COFFFileHeaderTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appending(path: "coff_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testCOFFHeaderParsing() throws {
        let peData = PEBuilder.createMinimalPE32()
        let fileURL = tempDir.appending(path: "coff.exe")
        try peData.write(to: fileURL)

        let peFile = try PEFile(url: fileURL)

        XCTAssertEqual(peFile.coffFileHeader.numberOfSections, 1)
    }

    func testCOFFHeaderTimestamp() throws {
        let peData = PEBuilder.createMinimalPE32()
        let fileURL = tempDir.appending(path: "timestamp.exe")
        try peData.write(to: fileURL)

        let peFile = try PEFile(url: fileURL)

        XCTAssertNotNil(peFile.coffFileHeader.timeDateStamp)
    }

    func testCOFFHeaderSizeOfOptionalHeader() throws {
        let peData = PEBuilder.createMinimalPE32()
        let fileURL = tempDir.appending(path: "optsize.exe")
        try peData.write(to: fileURL)

        let peFile = try PEFile(url: fileURL)

        XCTAssertEqual(peFile.coffFileHeader.sizeOfOptionalHeader, 0xE0)
    }

    func testCOFFHeaderHashable() throws {
        let peData = PEBuilder.createMinimalPE32()
        let fileURL = tempDir.appending(path: "coffhash.exe")
        try peData.write(to: fileURL)

        let pe1 = try PEFile(url: fileURL)
        let pe2 = try PEFile(url: fileURL)

        XCTAssertEqual(pe1.coffFileHeader, pe2.coffFileHeader)
        XCTAssertEqual(pe1.coffFileHeader.hashValue, pe2.coffFileHeader.hashValue)
    }
}

// MARK: - OptionalHeader Tests

final class OptionalHeaderTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appending(path: "opt_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testPE32MagicNumber() throws {
        let peData = PEBuilder.createMinimalPE32()
        let fileURL = tempDir.appending(path: "magic32.exe")
        try peData.write(to: fileURL)

        let peFile = try PEFile(url: fileURL)

        XCTAssertEqual(peFile.optionalHeader?.magic, .pe32)
        XCTAssertNotNil(peFile.optionalHeader?.baseOfData)
    }

    func testPE32PlusMagicNumber() throws {
        let peData = PEBuilder.createMinimalPE32Plus()
        let fileURL = tempDir.appending(path: "magic64.exe")
        try peData.write(to: fileURL)

        let peFile = try PEFile(url: fileURL)

        XCTAssertEqual(peFile.optionalHeader?.magic, .pe32Plus)
        XCTAssertNil(peFile.optionalHeader?.baseOfData)
    }

    func testLinkerVersion() throws {
        let peData = PEBuilder.createMinimalPE32()
        let fileURL = tempDir.appending(path: "linker.exe")
        try peData.write(to: fileURL)

        let peFile = try PEFile(url: fileURL)

        XCTAssertEqual(peFile.optionalHeader?.majorLinkerVersion, 0x0E)
        XCTAssertEqual(peFile.optionalHeader?.minorLinkerVersion, 0x1D)
    }

    func testOptionalHeaderHashable() throws {
        let peData = PEBuilder.createMinimalPE32()
        let fileURL = tempDir.appending(path: "hashopt.exe")
        try peData.write(to: fileURL)

        let pe1 = try PEFile(url: fileURL)
        let pe2 = try PEFile(url: fileURL)

        XCTAssertEqual(pe1.optionalHeader, pe2.optionalHeader)
    }
}

// MARK: - Section Tests

final class SectionTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appending(path: "section_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testSectionName() throws {
        let peData = PEBuilder.createMinimalPE32()
        let fileURL = tempDir.appending(path: "sectname.exe")
        try peData.write(to: fileURL)

        let peFile = try PEFile(url: fileURL)

        XCTAssertEqual(peFile.sections.first?.name, ".text")
    }

    func testSectionVirtualAddress() throws {
        let peData = PEBuilder.createMinimalPE32()
        let fileURL = tempDir.appending(path: "sectva.exe")
        try peData.write(to: fileURL)

        let peFile = try PEFile(url: fileURL)

        XCTAssertEqual(peFile.sections.first?.virtualAddress, 0x1000)
        XCTAssertEqual(peFile.sections.first?.virtualSize, 0x1000)
    }

    func testSectionHashable() throws {
        let peData = PEBuilder.createMinimalPE32()
        let fileURL = tempDir.appending(path: "secthash.exe")
        try peData.write(to: fileURL)

        let pe1 = try PEFile(url: fileURL)
        let pe2 = try PEFile(url: fileURL)

        XCTAssertEqual(pe1.sections, pe2.sections)
        if let section1 = pe1.sections.first, let section2 = pe2.sections.first {
            XCTAssertEqual(section1.hashValue, section2.hashValue)
        }
    }
}
