//
//  BitmapRenderTests.swift
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

// MARK: - BitmapInfoHeader Tests

/// Parameters for creating test bitmap info header data
struct BitmapHeaderParams {
    var size: UInt32 = 40
    var width: Int32 = 32
    var height: Int32 = 32
    var planes: UInt16 = 1
    var bitCount: UInt16 = 32
    var compression: UInt32 = 0
    var sizeImage: UInt32 = 0
}

final class BitmapInfoHeaderTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appending(path: "bitmap_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testBitmapInfoHeaderParsing() throws {
        let headerData = createBitmapInfoHeaderData(BitmapHeaderParams(
            width: 32,
            height: 64,
            sizeImage: 8_192
        ))

        let fileURL = tempDir.appending(path: "header.bin")
        try headerData.write(to: fileURL)

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let header = BitmapInfoHeader(handle: handle, offset: 0)

        XCTAssertEqual(header.size, 40)
        XCTAssertEqual(header.width, 32)
        XCTAssertEqual(header.height, 64)
        XCTAssertEqual(header.planes, 1)
        XCTAssertEqual(header.bitCount, 32)
        XCTAssertEqual(header.compression, .rgb)
        XCTAssertEqual(header.colorFormat, .sampled32)
        XCTAssertEqual(header.originDirection, .bottomLeft)
    }

    func testBitmapInfoHeaderNegativeHeight() throws {
        let headerData = createBitmapInfoHeaderData(BitmapHeaderParams(
            height: -64,
            bitCount: 24,
            sizeImage: 6_144
        ))

        let fileURL = tempDir.appending(path: "negheight.bin")
        try headerData.write(to: fileURL)

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let header = BitmapInfoHeader(handle: handle, offset: 0)

        XCTAssertEqual(header.height, -64)
        XCTAssertEqual(header.originDirection, .upperLeft)
    }

    func testBitmapInfoHeaderDifferentBitCounts() throws {
        let testCases: [(bitCount: UInt16, expectedFormat: ColorFormat)] = [
            (1, .indexed1),
            (4, .indexed4),
            (8, .indexed8),
            (16, .sampled16),
            (24, .sampled24),
            (32, .sampled32)
        ]

        for testCase in testCases {
            let headerData = createBitmapInfoHeaderData(BitmapHeaderParams(
                width: 16,
                height: 16,
                bitCount: testCase.bitCount
            ))

            let fileURL = tempDir.appending(path: "bc\(testCase.bitCount).bin")
            try headerData.write(to: fileURL)

            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }

            let header = BitmapInfoHeader(handle: handle, offset: 0)

            XCTAssertEqual(
                header.colorFormat,
                testCase.expectedFormat,
                "Expected \(testCase.expectedFormat) for bitCount \(testCase.bitCount)"
            )
        }
    }

    func testBitmapInfoHeaderHashable() throws {
        let headerData = createBitmapInfoHeaderData(BitmapHeaderParams(
            sizeImage: 4_096
        ))

        let fileURL = tempDir.appending(path: "hash.bin")
        try headerData.write(to: fileURL)

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let header1 = BitmapInfoHeader(handle: handle, offset: 0)
        let header2 = BitmapInfoHeader(handle: handle, offset: 0)

        XCTAssertEqual(header1, header2)
        XCTAssertEqual(header1.hashValue, header2.hashValue)
    }

    func testRenderBitmapSampled32() throws {
        // Create a 2x4 bitmap (height is doubled in icon format) with sampled32 format
        var data = createBitmapInfoHeaderWithColorTable(
            width: 2,
            height: 4,
            bitCount: 32,
            clrUsed: 0
        )

        // Add pixel data: 2x2 pixels (red, green, blue, white)
        // BGR + Alpha format
        data.append(contentsOf: [0x00, 0x00, 0xFF, 0xFF]) // Red pixel (BGR)
        data.append(contentsOf: [0x00, 0xFF, 0x00, 0xFF]) // Green pixel
        data.append(contentsOf: [0xFF, 0x00, 0x00, 0xFF]) // Blue pixel
        data.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF]) // White pixel

        let fileURL = tempDir.appending(path: "render32.bin")
        try data.write(to: fileURL)

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let header = BitmapInfoHeader(handle: handle, offset: 0)
        XCTAssertEqual(header.colorFormat, .sampled32)

        let image = header.renderBitmap(handle: handle, offset: 40)
        XCTAssertNotNil(image)
    }

    func testRenderBitmapSampled24() throws {
        // Create a 2x4 bitmap with sampled24 format
        var data = createBitmapInfoHeaderWithColorTable(
            width: 2,
            height: 4,
            bitCount: 24,
            clrUsed: 0
        )

        // Add pixel data: 2x2 pixels (red, green, blue, white)
        // BGR format (no alpha)
        data.append(contentsOf: [0x00, 0x00, 0xFF]) // Red pixel
        data.append(contentsOf: [0x00, 0xFF, 0x00]) // Green pixel
        data.append(contentsOf: [0xFF, 0x00, 0x00]) // Blue pixel
        data.append(contentsOf: [0xFF, 0xFF, 0xFF]) // White pixel

        let fileURL = tempDir.appending(path: "render24.bin")
        try data.write(to: fileURL)

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let header = BitmapInfoHeader(handle: handle, offset: 0)
        XCTAssertEqual(header.colorFormat, .sampled24)

        let image = header.renderBitmap(handle: handle, offset: 40)
        XCTAssertNotNil(image)
    }

    func testRenderBitmapIndexed8() throws {
        // Create a 2x4 bitmap with indexed8 format and color table
        var data = createBitmapInfoHeaderWithColorTable(
            width: 2,
            height: 4,
            bitCount: 8,
            clrUsed: 4
        )

        // Add color table (4 colors: red, green, blue, white)
        data.append(contentsOf: [0x00, 0x00, 0xFF, 0x00]) // Index 0: Red (BGR + reserved)
        data.append(contentsOf: [0x00, 0xFF, 0x00, 0x00]) // Index 1: Green
        data.append(contentsOf: [0xFF, 0x00, 0x00, 0x00]) // Index 2: Blue
        data.append(contentsOf: [0xFF, 0xFF, 0xFF, 0x00]) // Index 3: White

        // Add pixel indices: 2x2 pixels
        data.append(contentsOf: [0x00, 0x01]) // Row 1: red, green
        data.append(contentsOf: [0x02, 0x03]) // Row 2: blue, white

        let fileURL = tempDir.appending(path: "render8.bin")
        try data.write(to: fileURL)

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let header = BitmapInfoHeader(handle: handle, offset: 0)
        XCTAssertEqual(header.colorFormat, .indexed8)
        XCTAssertEqual(header.clrUsed, 4)

        let image = header.renderBitmap(handle: handle, offset: 40)
        XCTAssertNotNil(image)
    }

    func testRenderBitmapEmptyReturnsNil() throws {
        // Create a 0x0 bitmap
        let data = createBitmapInfoHeaderWithColorTable(
            width: 0,
            height: 0,
            bitCount: 32,
            clrUsed: 0
        )

        let fileURL = tempDir.appending(path: "empty.bin")
        try data.write(to: fileURL)

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let header = BitmapInfoHeader(handle: handle, offset: 0)
        let image = header.renderBitmap(handle: handle, offset: 40)
        XCTAssertNil(image)
    }

    func testRenderBitmapSampled16() throws {
        // Create a 2x4 bitmap with sampled16 format
        var data = createBitmapInfoHeaderWithColorTable(
            width: 2,
            height: 4,
            bitCount: 16,
            clrUsed: 0
        )

        // Add pixel data: 2 bytes per pixel in 5-5-5 format
        // Bits: 0BBBBBGG GGGRRRRR
        data.append(contentsOf: [0x1F, 0x00]) // Red (R=31, G=0, B=0)
        data.append(contentsOf: [0xE0, 0x03]) // Green (R=0, G=31, B=0)
        data.append(contentsOf: [0x00, 0x7C]) // Blue (R=0, G=0, B=31)
        data.append(contentsOf: [0xFF, 0x7F]) // White (R=31, G=31, B=31)

        let fileURL = tempDir.appending(path: "render16.bin")
        try data.write(to: fileURL)

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let header = BitmapInfoHeader(handle: handle, offset: 0)
        XCTAssertEqual(header.colorFormat, .sampled16)

        let image = header.renderBitmap(handle: handle, offset: 40)
        XCTAssertNotNil(image)
    }

    func testRenderBitmapIndexed8OutOfBoundsIndex() throws {
        // Create a bitmap where pixel index exceeds color table size
        var data = createBitmapInfoHeaderWithColorTable(
            width: 1,
            height: 2,
            bitCount: 8,
            clrUsed: 2
        )

        // Add small color table (only 2 colors)
        data.append(contentsOf: [0xFF, 0x00, 0x00, 0x00]) // Index 0: Blue
        data.append(contentsOf: [0x00, 0xFF, 0x00, 0x00]) // Index 1: Green

        // Add pixel with out-of-bounds index
        data.append(0xFF) // Index 255 - out of bounds

        let fileURL = tempDir.appending(path: "oob.bin")
        try data.write(to: fileURL)

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let header = BitmapInfoHeader(handle: handle, offset: 0)

        // Should not crash, should render with transparent pixel
        let image = header.renderBitmap(handle: handle, offset: 40)
        XCTAssertNotNil(image)
    }

    private func createBitmapInfoHeaderWithColorTable(
        width: Int32,
        height: Int32,
        bitCount: UInt16,
        clrUsed: UInt32
    ) -> Data {
        var data = Data()

        data.append(contentsOf: withUnsafeBytes(of: UInt32(40).littleEndian) { Array($0) }) // size
        data.append(contentsOf: withUnsafeBytes(of: width.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: height.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // planes
        data.append(contentsOf: withUnsafeBytes(of: bitCount.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) }) // compression
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) }) // sizeImage
        data.append(contentsOf: withUnsafeBytes(of: Int32(0).littleEndian) { Array($0) }) // xPelsPerMeter
        data.append(contentsOf: withUnsafeBytes(of: Int32(0).littleEndian) { Array($0) }) // yPelsPerMeter
        data.append(contentsOf: withUnsafeBytes(of: clrUsed.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) }) // clrImportant

        return data
    }

    private func createBitmapInfoHeaderData(_ params: BitmapHeaderParams) -> Data {
        var data = Data()

        data.append(contentsOf: withUnsafeBytes(of: params.size.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: params.width.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: params.height.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: params.planes.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: params.bitCount.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: params.compression.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: params.sizeImage.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: Int32(0).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: Int32(0).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) })

        return data
    }
}
