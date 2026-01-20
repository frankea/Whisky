//
//  PETestHelpers.swift
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

// MARK: - PE File Binary Builder

enum PEBuilder {
    static func createMinimalPE32() -> Data {
        var data = Data()

        let dosHeader = createDOSHeader(peOffset: 0x80)
        data.append(dosHeader)

        while data.count < 0x80 {
            data.append(0x00)
        }

        data.append(contentsOf: [0x50, 0x45, 0x00, 0x00])

        let coffHeader = createCOFFHeader(numberOfSections: 1, sizeOfOptionalHeader: 0xE0)
        data.append(coffHeader)

        let optionalHeader = createPE32OptionalHeader()
        data.append(optionalHeader)

        let sectionHeader = createSectionHeader(name: ".text", virtualSize: 0x1000, virtualAddress: 0x1000)
        data.append(sectionHeader)

        return data
    }

    static func createMinimalPE32Plus() -> Data {
        var data = Data()

        let dosHeader = createDOSHeader(peOffset: 0x80)
        data.append(dosHeader)

        while data.count < 0x80 {
            data.append(0x00)
        }

        data.append(contentsOf: [0x50, 0x45, 0x00, 0x00])

        let coffHeader = createCOFFHeader(numberOfSections: 1, sizeOfOptionalHeader: 0xF0)
        data.append(coffHeader)

        let optionalHeader = createPE32PlusOptionalHeader()
        data.append(optionalHeader)

        let sectionHeader = createSectionHeader(name: ".text", virtualSize: 0x1000, virtualAddress: 0x1000)
        data.append(sectionHeader)

        return data
    }

    static func createDOSHeader(peOffset: UInt32) -> Data {
        var data = Data()
        data.append(contentsOf: [0x4D, 0x5A])

        data.append(contentsOf: [UInt8](repeating: 0, count: 58))

        data.append(contentsOf: withUnsafeBytes(of: peOffset.littleEndian) { Array($0) })
        return data
    }

    static func createCOFFHeader(numberOfSections: UInt16, sizeOfOptionalHeader: UInt16) -> Data {
        var data = Data()
        data.append(contentsOf: withUnsafeBytes(of: UInt16(0x8664).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: numberOfSections.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0x1234_5678).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: sizeOfOptionalHeader.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(0x0022).littleEndian) { Array($0) })
        return data
    }

    static func createPE32OptionalHeader() -> Data {
        var data = Data()
        data.append(contentsOf: withUnsafeBytes(of: UInt16(0x10B).littleEndian) { Array($0) })
        data.append(0x0E)
        data.append(0x1D)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0x1000).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0x2000).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0x1000).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0x1000).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0x3000).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0x0040_0000).littleEndian) { Array($0) })

        data.append(contentsOf: [UInt8](repeating: 0, count: 0xE0 - data.count))

        return Data(data.prefix(0xE0))
    }

    static func createPE32PlusOptionalHeader() -> Data {
        var data = Data()
        data.append(contentsOf: withUnsafeBytes(of: UInt16(0x20B).littleEndian) { Array($0) })
        data.append(0x0E)
        data.append(0x1D)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0x1000).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0x2000).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0x1000).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0x1000).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt64(0x0000_0001_4000_0000).littleEndian) { Array($0) })

        data.append(contentsOf: [UInt8](repeating: 0, count: 0xF0 - data.count))

        return Data(data.prefix(0xF0))
    }

    static func createSectionHeader(name: String, virtualSize: UInt32, virtualAddress: UInt32) -> Data {
        var data = Data()
        var nameBytes = Array(name.utf8)
        while nameBytes.count < 8 {
            nameBytes.append(0)
        }
        data.append(contentsOf: nameBytes.prefix(8))
        data.append(contentsOf: withUnsafeBytes(of: virtualSize.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: virtualAddress.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0x1000).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0x200).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0x6000_0020).littleEndian) { Array($0) })
        return data
    }
}

// MARK: - Test Error

enum PETestError: Error {
    case failedToCreateMockEntry
    case failedToCreateMockSection
}
