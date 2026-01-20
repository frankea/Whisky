//
//  BinaryParsingTests.swift
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

// MARK: - BitmapCompression Tests

final class BitmapCompressionTests: XCTestCase {
    func testBitmapCompressionRawValues() {
        XCTAssertEqual(BitmapCompression.rgb.rawValue, 0x0000)
        XCTAssertEqual(BitmapCompression.rle8.rawValue, 0x0001)
        XCTAssertEqual(BitmapCompression.rle4.rawValue, 0x0002)
        XCTAssertEqual(BitmapCompression.bitfields.rawValue, 0x0003)
        XCTAssertEqual(BitmapCompression.jpeg.rawValue, 0x0004)
        XCTAssertEqual(BitmapCompression.png.rawValue, 0x0005)
        XCTAssertEqual(BitmapCompression.alphaBitfields.rawValue, 0x0006)
        XCTAssertEqual(BitmapCompression.cmyk.rawValue, 0x000B)
        XCTAssertEqual(BitmapCompression.cmykRle8.rawValue, 0x000C)
        XCTAssertEqual(BitmapCompression.cmykRle4.rawValue, 0x000D)
    }

    func testBitmapCompressionInitFromRawValue() {
        XCTAssertEqual(BitmapCompression(rawValue: 0x0000), .rgb)
        XCTAssertEqual(BitmapCompression(rawValue: 0x0001), .rle8)
        XCTAssertEqual(BitmapCompression(rawValue: 0x0003), .bitfields)
        XCTAssertEqual(BitmapCompression(rawValue: 0x0005), .png)
    }

    func testBitmapCompressionInvalidRawValue() {
        XCTAssertNil(BitmapCompression(rawValue: 0xFFFF))
        XCTAssertNil(BitmapCompression(rawValue: 0x0007))
        XCTAssertNil(BitmapCompression(rawValue: 0x0008))
        XCTAssertNil(BitmapCompression(rawValue: 0x0009))
        XCTAssertNil(BitmapCompression(rawValue: 0x000A))
    }

    func testBitmapCompressionHashable() {
        var set = Set<BitmapCompression>()
        set.insert(.rgb)
        set.insert(.rle8)
        set.insert(.jpeg)
        set.insert(.png)

        XCTAssertEqual(set.count, 4)
        XCTAssertTrue(set.contains(.rgb))
        XCTAssertTrue(set.contains(.rle8))
        XCTAssertTrue(set.contains(.jpeg))
        XCTAssertTrue(set.contains(.png))
    }
}

// MARK: - BitmapOriginDirection Tests

final class BitmapOriginDirectionTests: XCTestCase {
    func testBitmapOriginDirectionCases() {
        let bottomLeft = BitmapOriginDirection.bottomLeft
        let upperLeft = BitmapOriginDirection.upperLeft

        XCTAssertNotEqual(
            String(describing: bottomLeft),
            String(describing: upperLeft)
        )
    }

    func testBitmapOriginDirectionHashable() {
        var set = Set<BitmapOriginDirection>()
        set.insert(.bottomLeft)
        set.insert(.upperLeft)

        XCTAssertEqual(set.count, 2)
        XCTAssertTrue(set.contains(.bottomLeft))
        XCTAssertTrue(set.contains(.upperLeft))
    }

    func testBitmapOriginDirectionEquality() {
        XCTAssertEqual(BitmapOriginDirection.bottomLeft, BitmapOriginDirection.bottomLeft)
        XCTAssertEqual(BitmapOriginDirection.upperLeft, BitmapOriginDirection.upperLeft)
        XCTAssertNotEqual(BitmapOriginDirection.bottomLeft, BitmapOriginDirection.upperLeft)
    }
}

// MARK: - ColorFormat Tests

final class ColorFormatTests: XCTestCase {
    func testColorFormatRawValues() {
        XCTAssertEqual(ColorFormat.unknown.rawValue, 0)
        XCTAssertEqual(ColorFormat.indexed1.rawValue, 1)
        XCTAssertEqual(ColorFormat.indexed2.rawValue, 2)
        XCTAssertEqual(ColorFormat.indexed4.rawValue, 4)
        XCTAssertEqual(ColorFormat.indexed8.rawValue, 8)
        XCTAssertEqual(ColorFormat.sampled16.rawValue, 16)
        XCTAssertEqual(ColorFormat.sampled24.rawValue, 24)
        XCTAssertEqual(ColorFormat.sampled32.rawValue, 32)
    }

    func testColorFormatInitFromRawValue() {
        XCTAssertEqual(ColorFormat(rawValue: 0), .unknown)
        XCTAssertEqual(ColorFormat(rawValue: 1), .indexed1)
        XCTAssertEqual(ColorFormat(rawValue: 8), .indexed8)
        XCTAssertEqual(ColorFormat(rawValue: 24), .sampled24)
        XCTAssertEqual(ColorFormat(rawValue: 32), .sampled32)
    }

    func testColorFormatInvalidRawValue() {
        XCTAssertNil(ColorFormat(rawValue: 3))
        XCTAssertNil(ColorFormat(rawValue: 5))
        XCTAssertNil(ColorFormat(rawValue: 6))
        XCTAssertNil(ColorFormat(rawValue: 7))
        XCTAssertNil(ColorFormat(rawValue: 9))
        XCTAssertNil(ColorFormat(rawValue: 15))
        XCTAssertNil(ColorFormat(rawValue: 64))
    }

    func testColorFormatHashable() {
        var set = Set<ColorFormat>()
        set.insert(.unknown)
        set.insert(.indexed8)
        set.insert(.sampled24)
        set.insert(.sampled32)

        XCTAssertEqual(set.count, 4)
        XCTAssertTrue(set.contains(.unknown))
        XCTAssertTrue(set.contains(.indexed8))
        XCTAssertTrue(set.contains(.sampled24))
        XCTAssertTrue(set.contains(.sampled32))
    }

    func testColorFormatCorrespondsToBitCount() {
        // Verify that ColorFormat raw values match standard bitmap bit counts
        XCTAssertEqual(ColorFormat.indexed1.rawValue, 1)
        XCTAssertEqual(ColorFormat.indexed4.rawValue, 4)
        XCTAssertEqual(ColorFormat.indexed8.rawValue, 8)
        XCTAssertEqual(ColorFormat.sampled16.rawValue, 16)
        XCTAssertEqual(ColorFormat.sampled24.rawValue, 24)
        XCTAssertEqual(ColorFormat.sampled32.rawValue, 32)
    }
}

// MARK: - ColorQuad Tests

final class ColorQuadTests: XCTestCase {
    func testColorQuadInitialization() {
        let quad = ColorQuad(red: 255, green: 128, blue: 64, alpha: 200)

        XCTAssertEqual(quad.red, 255)
        XCTAssertEqual(quad.green, 128)
        XCTAssertEqual(quad.blue, 64)
        XCTAssertEqual(quad.alpha, 200)
    }

    func testColorQuadBlack() {
        let black = ColorQuad(red: 0, green: 0, blue: 0, alpha: 255)

        XCTAssertEqual(black.red, 0)
        XCTAssertEqual(black.green, 0)
        XCTAssertEqual(black.blue, 0)
    }

    func testColorQuadWhite() {
        let white = ColorQuad(red: 255, green: 255, blue: 255, alpha: 255)

        XCTAssertEqual(white.red, 255)
        XCTAssertEqual(white.green, 255)
        XCTAssertEqual(white.blue, 255)
    }

    func testColorQuadTransparent() {
        let transparent = ColorQuad(red: 0, green: 0, blue: 0, alpha: 0)

        XCTAssertEqual(transparent.alpha, 0)
    }

    func testColorQuadMutability() {
        var quad = ColorQuad(red: 0, green: 0, blue: 0, alpha: 0)

        quad.red = 100
        quad.green = 150
        quad.blue = 200
        quad.alpha = 128

        XCTAssertEqual(quad.red, 100)
        XCTAssertEqual(quad.green, 150)
        XCTAssertEqual(quad.blue, 200)
        XCTAssertEqual(quad.alpha, 128)
    }

    func testColorQuadMaxValues() {
        let quad = ColorQuad(red: UInt8.max, green: UInt8.max, blue: UInt8.max, alpha: UInt8.max)

        XCTAssertEqual(quad.red, 255)
        XCTAssertEqual(quad.green, 255)
        XCTAssertEqual(quad.blue, 255)
        XCTAssertEqual(quad.alpha, 255)
    }
}

// MARK: - LinkFlags Tests

final class LinkFlagsTests: XCTestCase {
    func testLinkFlagsHasLinkTargetIDList() {
        let flags = LinkFlags.hasLinkTargetIDList
        XCTAssertEqual(flags.rawValue, 1 << 0)
        XCTAssertTrue(flags.contains(.hasLinkTargetIDList))
    }

    func testLinkFlagsHasLinkInfo() {
        let flags = LinkFlags.hasLinkInfo
        XCTAssertEqual(flags.rawValue, 1 << 1)
        XCTAssertTrue(flags.contains(.hasLinkInfo))
    }

    func testLinkFlagsHasIconLocation() {
        let flags = LinkFlags.hasIconLocation
        XCTAssertEqual(flags.rawValue, 1 << 6)
        XCTAssertTrue(flags.contains(.hasIconLocation))
    }

    func testLinkFlagsCombined() {
        let flags: LinkFlags = [.hasLinkTargetIDList, .hasLinkInfo]

        XCTAssertTrue(flags.contains(.hasLinkTargetIDList))
        XCTAssertTrue(flags.contains(.hasLinkInfo))
        XCTAssertFalse(flags.contains(.hasIconLocation))
    }

    func testLinkFlagsFromRawValue() {
        let flags = LinkFlags(rawValue: 0b0100_0011)

        XCTAssertTrue(flags.contains(.hasLinkTargetIDList))
        XCTAssertTrue(flags.contains(.hasLinkInfo))
        XCTAssertTrue(flags.contains(.hasIconLocation))
    }

    func testLinkFlagsHashable() {
        var set = Set<LinkFlags>()
        set.insert(.hasLinkTargetIDList)
        set.insert(.hasLinkInfo)

        XCTAssertEqual(set.count, 2)
    }
}

// MARK: - LinkInfoFlags Tests

final class LinkInfoFlagsTests: XCTestCase {
    func testLinkInfoFlagsVolumeIDAndLocalBasePath() {
        let flags = LinkInfoFlags.volumeIDAndLocalBasePath
        XCTAssertEqual(flags.rawValue, 1 << 0)
        XCTAssertTrue(flags.contains(.volumeIDAndLocalBasePath))
    }

    func testLinkInfoFlagsCommonNetworkRelativeLink() {
        let flags = LinkInfoFlags.commonNetworkRelativeLinkAndPathSuffix
        XCTAssertEqual(flags.rawValue, 1 << 1)
        XCTAssertTrue(flags.contains(.commonNetworkRelativeLinkAndPathSuffix))
    }

    func testLinkInfoFlagsCombined() {
        let flags: LinkInfoFlags = [.volumeIDAndLocalBasePath, .commonNetworkRelativeLinkAndPathSuffix]

        XCTAssertTrue(flags.contains(.volumeIDAndLocalBasePath))
        XCTAssertTrue(flags.contains(.commonNetworkRelativeLinkAndPathSuffix))
        XCTAssertEqual(flags.rawValue, 0b11)
    }

    func testLinkInfoFlagsFromRawValue() {
        let flags = LinkInfoFlags(rawValue: 3)

        XCTAssertTrue(flags.contains(.volumeIDAndLocalBasePath))
        XCTAssertTrue(flags.contains(.commonNetworkRelativeLinkAndPathSuffix))
    }

    func testLinkInfoFlagsHashable() {
        var set = Set<LinkInfoFlags>()
        set.insert(.volumeIDAndLocalBasePath)
        set.insert(.commonNetworkRelativeLinkAndPathSuffix)

        XCTAssertEqual(set.count, 2)
    }

    func testLinkInfoFlagsEquality() {
        let flags1 = LinkInfoFlags(rawValue: 1)
        let flags2 = LinkInfoFlags.volumeIDAndLocalBasePath

        XCTAssertEqual(flags1, flags2)
    }
}
