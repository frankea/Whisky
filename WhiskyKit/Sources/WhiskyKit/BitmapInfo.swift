//
//  BitmapInfo.swift
//  WhiskyKit
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

import AppKit
import Foundation

public struct BitmapInfoHeader: Hashable {
    public let size: UInt32
    public let width: Int32
    public let height: Int32
    public let planes: UInt16
    public let bitCount: UInt16
    public let compression: BitmapCompression
    public let sizeImage: UInt32
    public let xPelsPerMeter: Int32
    public let yPelsPerMeter: Int32
    public let clrUsed: UInt32
    public let clrImportant: UInt32

    public let originDirection: BitmapOriginDirection
    public let colorFormat: ColorFormat

    /// Largest icon edge we will render. Real Windows icons top out at 256px;
    /// 1024 is a generous ceiling. width/height are file-controlled and can be
    /// near Int32.max in a crafted file, which would otherwise drive an
    /// effectively unbounded allocation and pixel loop (a denial-of-service).
    private static let maxDimension: Int32 = 1_024

    /// Upper bound on the color-table length we will read. A palette never
    /// exceeds 256 entries; `clrUsed` is file-controlled and can claim billions.
    private static let maxColorTableEntries: UInt32 = 256

    init(handle: FileHandle, offset: UInt64) {
        var offset = offset
        self.size = handle.extract(UInt32.self, offset: offset) ?? 0
        offset += 4
        self.width = handle.extract(Int32.self, offset: offset) ?? 0
        offset += 4
        self.height = handle.extract(Int32.self, offset: offset) ?? 0
        offset += 4
        self.planes = handle.extract(UInt16.self, offset: offset) ?? 0
        offset += 2
        self.bitCount = handle.extract(UInt16.self, offset: offset) ?? 0
        offset += 2
        self.compression = BitmapCompression(rawValue: handle.extract(UInt32.self, offset: offset) ?? 0) ?? .rgb
        offset += 4
        self.sizeImage = handle.extract(UInt32.self, offset: offset) ?? 0
        offset += 4
        self.xPelsPerMeter = handle.extract(Int32.self, offset: offset) ?? 0
        offset += 4
        self.yPelsPerMeter = handle.extract(Int32.self, offset: offset) ?? 0
        offset += 4
        self.clrUsed = handle.extract(UInt32.self, offset: offset) ?? 0
        offset += 4
        self.clrImportant = handle.extract(UInt32.self, offset: offset) ?? 0
        offset += 4

        self.originDirection = self.height < 0 ? .upperLeft : .bottomLeft
        self.colorFormat = ColorFormat(rawValue: bitCount) ?? .unknown
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func renderBitmap(handle: FileHandle, offset: UInt64) -> NSImage? {
        // Reject crafted dimensions before allocating or looping. width/height
        // come straight from the file and can be non-positive or near Int32.max.
        let actualHeight = abs(height)
        guard width > 0, actualHeight > 0,
              width <= Self.maxDimension, actualHeight <= Self.maxDimension
        else {
            return nil
        }
        // A bitmap palette never legitimately exceeds 256 entries. Clamping a
        // larger clrUsed would leave the read cursor inside the palette when the
        // pixel loop starts, silently rendering garbage — reject it as malformed.
        guard clrUsed <= Self.maxColorTableEntries else {
            return nil
        }

        var offset = offset
        let colorTable = buildColorTable(offset: &offset, handle: handle)

        var pixels: [ColorQuad] = []

        // Handle bitfields later if necessary

        for _ in 0 ..< Int(actualHeight / 2) {
            var pixelRow: [ColorQuad] = []

            for _ in 0 ..< width {
                switch colorFormat {
                case .indexed1:
                    // Swift has no data type equivelent to a single bit
                    // This will take some bitwise magic
                    break
                case .indexed2:
                    // Swift's smallest data type is 1 byte
                    // Ditto .indexed1
                    break
                case .indexed4:
                    // Swift's smallest data type is 1 byte
                    // Ditto .indexed1
                    break
                case .indexed8:
                    let index = Int(handle.extract(UInt8.self, offset: offset) ?? 0)
                    if index >= colorTable.count {
                        pixelRow.append(ColorQuad(red: 0, green: 0, blue: 0, alpha: 0))
                    } else {
                        pixelRow.append(colorTable[Int(index)])
                    }
                    offset += 1
                case .sampled16:
                    let sample = handle.extract(UInt16.self, offset: offset) ?? 0
                    let red = sample & 0x001F
                    let green = (sample & 0x03E0) >> 5
                    let blue = (sample & 0x7C00) >> 10
                    pixelRow.append(ColorQuad(
                        red: UInt8(red),
                        green: UInt8(green),
                        blue: UInt8(blue),
                        alpha: 255
                    ))
                    offset += 2
                case .sampled24:
                    let blue = handle.extract(UInt8.self, offset: offset) ?? 0
                    offset += 1
                    let green = handle.extract(UInt8.self, offset: offset) ?? 0
                    offset += 1
                    let red = handle.extract(UInt8.self, offset: offset) ?? 0
                    offset += 1
                    pixelRow.append(ColorQuad(
                        red: red,
                        green: green,
                        blue: blue,
                        alpha: 255
                    ))
                case .sampled32:
                    let blue = handle.extract(UInt8.self, offset: offset) ?? 0
                    offset += 1
                    let green = handle.extract(UInt8.self, offset: offset) ?? 0
                    offset += 1
                    let red = handle.extract(UInt8.self, offset: offset) ?? 0
                    offset += 1
                    let alpha = handle.extract(UInt8.self, offset: offset) ?? 0
                    offset += 1
                    pixelRow.append(ColorQuad(
                        red: red,
                        green: green,
                        blue: blue,
                        alpha: alpha
                    ))
                case .unknown:
                    break
                }
            }

            if originDirection == .upperLeft {
                pixels.append(contentsOf: pixelRow)
            } else {
                pixels.insert(contentsOf: pixelRow, at: 0)
            }
        }

        return constructImage(pixels: pixels)
    }

    func buildColorTable(offset: inout UInt64, handle: FileHandle) -> [ColorQuad] {
        var colorTable: [ColorQuad] = []

        // renderBitmap rejects clrUsed above the cap before calling this; the
        // clamp is a backstop so a future caller can't loop unbounded either.
        let entryCount = min(clrUsed, Self.maxColorTableEntries)
        for _ in 0 ..< entryCount {
            let blue = handle.extract(UInt8.self, offset: offset) ?? 0
            offset += 1
            let green = handle.extract(UInt8.self, offset: offset) ?? 0
            offset += 1
            let red = handle.extract(UInt8.self, offset: offset) ?? 0
            offset += 2

            colorTable.append(ColorQuad(
                red: red,
                green: green,
                blue: blue,
                alpha: Int(red) + Int(green) + Int(blue) == 0 ? 0 : 255
            ))
        }

        return colorTable
    }

    func constructImage(pixels: [ColorQuad]) -> NSImage? {
        var pixels = pixels

        if !pixels.isEmpty {
            let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
            let quadStride = MemoryLayout<ColorQuad>.stride

            if let providerRef = CGDataProvider(data: Data(
                bytes: &pixels,
                count: pixels.count * quadStride
            ) as CFData) {
                if let cgImg = CGImage(
                    width: Int(width),
                    height: Int(abs(height) / 2),
                    bitsPerComponent: 8,
                    bitsPerPixel: 32,
                    bytesPerRow: Int(width) * quadStride,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: bitmapInfo,
                    provider: providerRef,
                    decode: nil,
                    shouldInterpolate: true,
                    intent: .defaultIntent
                ) {
                    return NSImage(cgImage: cgImg, size: .zero)
                }
            }
        }

        return nil
    }
}

public struct ColorQuad {
    var red: UInt8
    var green: UInt8
    var blue: UInt8
    var alpha: UInt8
}

public enum BitmapCompression: UInt32 {
    case rgb = 0x0000
    case rle8 = 0x0001
    case rle4 = 0x0002
    case bitfields = 0x0003
    case jpeg = 0x0004
    case png = 0x0005
    case alphaBitfields = 0x0006
    case cmyk = 0x000B
    case cmykRle8 = 0x000C
    case cmykRle4 = 0x000D
}

public enum BitmapOriginDirection {
    case bottomLeft
    case upperLeft
}

public enum ColorFormat: UInt16 {
    case unknown = 0
    case indexed1 = 1
    case indexed2 = 2
    case indexed4 = 4
    case indexed8 = 8
    case sampled16 = 16
    case sampled24 = 24
    case sampled32 = 32
}
