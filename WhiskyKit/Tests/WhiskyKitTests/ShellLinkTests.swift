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

// MARK: - LinkInfo Tests

final class LinkInfoTests: XCTestCase {
    var tempDir: URL!
    var bottleURL: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appending(path: "linkinfo_\(UUID().uuidString)")
        bottleURL = tempDir.appending(path: "TestBottle")
        try? FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)
        // Create drive_c directory that LinkInfo expects
        let driveCURL = bottleURL.appending(path: "drive_c")
        try? FileManager.default.createDirectory(at: driveCURL, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    /// Creates LinkInfo section binary data for testing
    func createLinkInfoData(
        linkInfoSize: UInt32,
        headerSize: UInt32,
        flags: UInt32,
        localBasePathOffset: UInt32,
        localBasePathOffsetUnicode: UInt32? = nil,
        pathData: Data? = nil
    ) -> Data {
        var data = Data()

        // LinkInfoSize
        data.append(contentsOf: withUnsafeBytes(of: linkInfoSize.littleEndian) { Array($0) })
        // LinkInfoHeaderSize
        data.append(contentsOf: withUnsafeBytes(of: headerSize.littleEndian) { Array($0) })
        // LinkInfoFlags
        data.append(contentsOf: withUnsafeBytes(of: flags.littleEndian) { Array($0) })
        // VolumeIDOffset (not used in our tests)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) })
        // LocalBasePathOffset
        data.append(contentsOf: withUnsafeBytes(of: localBasePathOffset.littleEndian) { Array($0) })
        // CommonNetworkRelativeLinkOffset
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) })
        // CommonPathSuffixOffset
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) })

        // If header size >= 0x24, add Unicode offsets
        if headerSize >= 0x24 {
            let unicodeOffset = (localBasePathOffsetUnicode ?? 0).littleEndian
            data.append(contentsOf: withUnsafeBytes(of: unicodeOffset) { Array($0) })
            // commonPathSuffixUnicode
            data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) })
        }

        // Pad to header size
        while data.count < Int(headerSize) {
            data.append(0)
        }

        // Add path data if provided
        if let pathData {
            data.append(pathData)
        }

        return data
    }

    @MainActor
    func testLinkInfoWithNoVolumeIDFlag() throws {
        // Create LinkInfo data with no volumeIDAndLocalBasePath flag
        let linkInfoData = createLinkInfoData(
            linkInfoSize: 28,
            headerSize: 28,
            flags: 0, // No flags
            localBasePathOffset: 0
        )

        let fileURL = tempDir.appending(path: "novolume.bin")
        try linkInfoData.write(to: fileURL)

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let bottle = Bottle(bottleUrl: bottleURL)
        var offset: UInt64 = 0

        let linkInfo = LinkInfo(handle: handle, bottle: bottle, offset: &offset)

        XCTAssertFalse(linkInfo.linkInfoFlags.contains(.volumeIDAndLocalBasePath))
        XCTAssertNil(linkInfo.program)
        XCTAssertEqual(offset, 28) // Should advance by linkInfoSize
    }

    @MainActor
    func testLinkInfoWithVolumeIDFlagSmallHeader() throws {
        // Create a path string in Windows CP1254 encoding
        let windowsPath = "C:\\Program Files\\test.exe"
        var pathData = windowsPath.data(using: .windowsCP1254) ?? Data()
        pathData.append(0) // Null terminator

        // LocalBasePathOffset points to where path data starts (after header)
        let headerSize: UInt32 = 28
        let localBasePathOffset: UInt32 = headerSize
        let linkInfoSize: UInt32 = headerSize + UInt32(pathData.count)

        let linkInfoData = createLinkInfoData(
            linkInfoSize: linkInfoSize,
            headerSize: headerSize,
            flags: 0x01, // volumeIDAndLocalBasePath
            localBasePathOffset: localBasePathOffset,
            pathData: pathData
        )

        let fileURL = tempDir.appending(path: "smallheader.bin")
        try linkInfoData.write(to: fileURL)

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let bottle = Bottle(bottleUrl: bottleURL)
        var offset: UInt64 = 0

        let linkInfo = LinkInfo(handle: handle, bottle: bottle, offset: &offset)

        XCTAssertTrue(linkInfo.linkInfoFlags.contains(.volumeIDAndLocalBasePath))
        // Program may or may not exist depending on whether the path is valid
        XCTAssertEqual(offset, UInt64(linkInfoSize))
    }

    @MainActor
    func testLinkInfoWithVolumeIDFlagLargeHeader() throws {
        // Create a path string in UTF-16 encoding for Unicode path
        let windowsPath = "C:\\Program Files\\test.exe"
        var pathData = windowsPath.data(using: .utf16LittleEndian) ?? Data()
        pathData.append(contentsOf: [0, 0]) // Null terminator (2 bytes for UTF-16)

        // Large header (>= 0x24) uses Unicode path offset
        let headerSize: UInt32 = 0x24
        let localBasePathOffsetUnicode: UInt32 = headerSize
        let linkInfoSize: UInt32 = headerSize + UInt32(pathData.count)

        let linkInfoData = createLinkInfoData(
            linkInfoSize: linkInfoSize,
            headerSize: headerSize,
            flags: 0x01, // volumeIDAndLocalBasePath
            localBasePathOffset: 0,
            localBasePathOffsetUnicode: localBasePathOffsetUnicode,
            pathData: pathData
        )

        let fileURL = tempDir.appending(path: "largeheader.bin")
        try linkInfoData.write(to: fileURL)

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let bottle = Bottle(bottleUrl: bottleURL)
        var offset: UInt64 = 0

        let linkInfo = LinkInfo(handle: handle, bottle: bottle, offset: &offset)

        XCTAssertTrue(linkInfo.linkInfoFlags.contains(.volumeIDAndLocalBasePath))
        XCTAssertEqual(offset, UInt64(linkInfoSize))
    }

    @MainActor
    func testLinkInfoOffsetAdvancement() throws {
        // Test that offset is correctly advanced by linkInfoSize
        let linkInfoSize: UInt32 = 100
        let linkInfoData = createLinkInfoData(
            linkInfoSize: linkInfoSize,
            headerSize: 28,
            flags: 0,
            localBasePathOffset: 0
        )

        // Pad to reach linkInfoSize
        var paddedData = linkInfoData
        while paddedData.count < Int(linkInfoSize) {
            paddedData.append(0)
        }

        let fileURL = tempDir.appending(path: "offset.bin")
        try paddedData.write(to: fileURL)

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let bottle = Bottle(bottleUrl: bottleURL)
        var offset: UInt64 = 0

        _ = LinkInfo(handle: handle, bottle: bottle, offset: &offset)

        XCTAssertEqual(offset, UInt64(linkInfoSize))
    }

    @MainActor
    func testLinkInfoWithCommonNetworkFlag() throws {
        // Test with commonNetworkRelativeLinkAndPathSuffix flag (bit 1)
        let linkInfoData = createLinkInfoData(
            linkInfoSize: 28,
            headerSize: 28,
            flags: 0x02, // commonNetworkRelativeLinkAndPathSuffix only
            localBasePathOffset: 0
        )

        let fileURL = tempDir.appending(path: "network.bin")
        try linkInfoData.write(to: fileURL)

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let bottle = Bottle(bottleUrl: bottleURL)
        var offset: UInt64 = 0

        let linkInfo = LinkInfo(handle: handle, bottle: bottle, offset: &offset)

        XCTAssertFalse(linkInfo.linkInfoFlags.contains(.volumeIDAndLocalBasePath))
        XCTAssertTrue(linkInfo.linkInfoFlags.contains(.commonNetworkRelativeLinkAndPathSuffix))
        XCTAssertNil(linkInfo.program) // No local path, so no program
    }
}
