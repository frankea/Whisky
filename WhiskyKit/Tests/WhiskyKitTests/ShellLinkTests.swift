//
//  ShellLinkTests.swift
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

// MARK: - ShellLinkHeader Tests

final class ShellLinkHeaderTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appending(path: "shelllink_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testInvalidLinkFileStructure() throws {
        // Create a file with no hasLinkInfo flag set - getProgram would return nil
        var data = Data()
        // Header size (76 bytes is standard .lnk header size)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(76).littleEndian) { Array($0) })
        // Link CLSID (16 bytes of zeros)
        data.append(contentsOf: [UInt8](repeating: 0, count: 16))
        // Link flags - no flags set (0)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) })
        // Padding to reach header size
        data.append(contentsOf: [UInt8](repeating: 0, count: 76 - 24))

        let fileURL = tempDir.appending(path: "invalid.lnk")
        try data.write(to: fileURL)

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        // Verify the header was written correctly
        let headerSize = handle.extract(UInt32.self, offset: 0) ?? 0
        XCTAssertEqual(headerSize, 76)

        // Verify flags indicate no link info
        let rawFlags = handle.extract(UInt32.self, offset: 20) ?? 0
        let flags = LinkFlags(rawValue: rawFlags)
        XCTAssertFalse(flags.contains(.hasLinkInfo))
    }

    func testLinkFileWithHasLinkInfoFlag() throws {
        var data = Data()
        // Header size
        data.append(contentsOf: withUnsafeBytes(of: UInt32(76).littleEndian) { Array($0) })
        // Link CLSID (16 bytes)
        data.append(contentsOf: [UInt8](repeating: 0, count: 16))
        // Link flags - hasLinkInfo (bit 1)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0x02).littleEndian) { Array($0) })
        // Padding
        data.append(contentsOf: [UInt8](repeating: 0, count: 76 - 24))

        let fileURL = tempDir.appending(path: "withinfo.lnk")
        try data.write(to: fileURL)

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let rawFlags = handle.extract(UInt32.self, offset: 20) ?? 0
        let flags = LinkFlags(rawValue: rawFlags)
        XCTAssertTrue(flags.contains(.hasLinkInfo))
        XCTAssertFalse(flags.contains(.hasLinkTargetIDList))
    }

    func testLinkFileWithBothFlags() throws {
        var data = Data()
        // Header size
        data.append(contentsOf: withUnsafeBytes(of: UInt32(76).littleEndian) { Array($0) })
        // Link CLSID (16 bytes)
        data.append(contentsOf: [UInt8](repeating: 0, count: 16))
        // Link flags - hasLinkTargetIDList (bit 0) + hasLinkInfo (bit 1)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0x03).littleEndian) { Array($0) })
        // Padding
        data.append(contentsOf: [UInt8](repeating: 0, count: 76 - 24))

        let fileURL = tempDir.appending(path: "bothflags.lnk")
        try data.write(to: fileURL)

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let rawFlags = handle.extract(UInt32.self, offset: 20) ?? 0
        let flags = LinkFlags(rawValue: rawFlags)
        XCTAssertTrue(flags.contains(.hasLinkInfo))
        XCTAssertTrue(flags.contains(.hasLinkTargetIDList))
    }

    func testLinkFileFlagsOffset() throws {
        // Test that flags are at the correct offset (after 4-byte header size + 16-byte CLSID)
        var data = Data()
        data.append(contentsOf: withUnsafeBytes(of: UInt32(76).littleEndian) { Array($0) })
        data.append(contentsOf: [UInt8](repeating: 0, count: 16))
        // hasIconLocation flag (bit 6) = 0x40
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0x40).littleEndian) { Array($0) })
        data.append(contentsOf: [UInt8](repeating: 0, count: 76 - 24))

        let fileURL = tempDir.appending(path: "iconloc.lnk")
        try data.write(to: fileURL)

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        // Flags should be at offset 20 (4 + 16)
        let rawFlags = handle.extract(UInt32.self, offset: 20) ?? 0
        let flags = LinkFlags(rawValue: rawFlags)
        XCTAssertTrue(flags.contains(.hasIconLocation))
    }
}
