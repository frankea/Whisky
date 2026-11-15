//
//  PEOptionalHeaderTests.swift
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
import Testing
@testable import WhiskyKit

/// A PE image whose optional header has every field after DllCharacteristics
/// set to a distinct value, laid out as the PE format specifies for PE32 and
/// PE32+, so a field read at the wrong width or offset shows up as a wrong value.
private enum OptionalHeaderFixture {
    /// MSVC's default reserve and commit sizes, with a stack reserve above
    /// 4 GiB on PE32+ so a truncating read is caught too.
    static let stackReserve64: UInt64 = 0x0000_0001_0010_0000
    static let stackReserve32: UInt64 = 0x0010_0000
    static let stackCommit: UInt64 = 0x1000
    static let heapReserve: UInt64 = 0x0020_0000
    static let heapCommit: UInt64 = 0x2000
    static let loaderFlags: UInt32 = 0
    static let directoryCount: UInt32 = 16

    static func image(pe32Plus: Bool) -> Data {
        var data = PEBuilder.createDOSHeader(peOffset: 0x80)
        data.append(contentsOf: [UInt8](repeating: 0, count: 0x80 - data.count))
        data.append(contentsOf: [0x50, 0x45, 0x00, 0x00])
        let header = optionalHeader(pe32Plus: pe32Plus)
        data.append(PEBuilder.createCOFFHeader(numberOfSections: 1, sizeOfOptionalHeader: UInt16(header.count)))
        data.append(header)
        data.append(PEBuilder.createSectionHeader(name: ".text", virtualSize: 0x1000, virtualAddress: 0x1000))
        return data
    }

    private static func optionalHeader(pe32Plus: Bool) -> Data {
        var data = Data()
        append(UInt16(pe32Plus ? 0x20B : 0x10B), to: &data)
        data.append(contentsOf: [0x0E, 0x1D])
        // SizeOfCode through BaseOfCode.
        for value: UInt32 in [0x1000, 0x2000, 0, 0x1000, 0x1000] {
            append(value, to: &data)
        }
        if pe32Plus {
            append(UInt64(0x0000_0001_4000_0000), to: &data)
        } else {
            append(UInt32(0x3000), to: &data) // BaseOfData
            append(UInt32(0x0040_0000), to: &data)
        }
        append(UInt32(0x1000), to: &data) // SectionAlignment
        append(UInt32(0x200), to: &data) // FileAlignment
        // Operating system, image and subsystem versions.
        for value: UInt16 in [6, 0, 0, 0, 6, 0] {
            append(value, to: &data)
        }
        // Win32VersionValue, SizeOfImage, SizeOfHeaders, CheckSum.
        for value: UInt32 in [0, 0x3000, 0x400, 0] {
            append(value, to: &data)
        }
        append(UInt16(3), to: &data) // Subsystem: console
        append(UInt16(0x8160), to: &data) // DllCharacteristics
        let sizes = [pe32Plus ? stackReserve64 : stackReserve32, stackCommit, heapReserve, heapCommit]
        for size in sizes {
            if pe32Plus {
                append(size, to: &data)
            } else {
                append(UInt32(size), to: &data)
            }
        }
        append(loaderFlags, to: &data)
        append(directoryCount, to: &data)
        // The data directories: an RVA and a size each, all empty.
        data.append(contentsOf: [UInt8](repeating: 0, count: Int(directoryCount) * 8))
        return data
    }

    private static func append(_ value: some FixedWidthInteger, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
}

@Suite("PE Optional Header Tests")
struct PEOptionalHeaderTests {
    private func header(pe32Plus: Bool) throws -> PEFile.OptionalHeader? {
        let url = FileManager.default.temporaryDirectory.appending(path: "optional-header-\(UUID().uuidString).exe")
        try OptionalHeaderFixture.image(pe32Plus: pe32Plus).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try PEFile(url: url).optionalHeader
    }

    @Test("The fixtures have the optional header sizes the PE format specifies")
    func fixtureSizes() {
        // DOS stub to 0x80, signature, COFF header, optional header, one section header.
        #expect(OptionalHeaderFixture.image(pe32Plus: true).count == 0x84 + 20 + 0xF0 + 40)
        #expect(OptionalHeaderFixture.image(pe32Plus: false).count == 0x84 + 20 + 0xE0 + 40)
    }

    @Test("A PE32+ image's stack and heap sizes are read as 8 bytes each")
    func pe32PlusSizesAreEightBytes() throws {
        let header = try #require(try header(pe32Plus: true))

        #expect(header.magic == .pe32Plus)
        #expect(header.dllCharacteristics == 0x8160)
        #expect(header.sizeOfStackReserve == OptionalHeaderFixture.stackReserve64)
        #expect(header.sizeOfStackCommit == OptionalHeaderFixture.stackCommit)
        #expect(header.sizeOfHeapReserve == OptionalHeaderFixture.heapReserve)
        #expect(header.sizeOfHeapCommit == OptionalHeaderFixture.heapCommit)
    }

    @Test("A PE32+ image's fields after the sizes come from their own offsets")
    func pe32PlusLaterFieldsAreInPlace() throws {
        let header = try #require(try header(pe32Plus: true))

        #expect(header.loaderFlags == OptionalHeaderFixture.loaderFlags)
        #expect(header.numberOfRvaAndSizes == OptionalHeaderFixture.directoryCount)
    }

    @Test("A PE32 image's stack and heap sizes stay 4 bytes each")
    func pe32SizesAreFourBytes() throws {
        let header = try #require(try header(pe32Plus: false))

        #expect(header.magic == .pe32)
        #expect(header.sizeOfStackReserve == OptionalHeaderFixture.stackReserve32)
        #expect(header.sizeOfStackCommit == OptionalHeaderFixture.stackCommit)
        #expect(header.sizeOfHeapReserve == OptionalHeaderFixture.heapReserve)
        #expect(header.sizeOfHeapCommit == OptionalHeaderFixture.heapCommit)
        #expect(header.loaderFlags == OptionalHeaderFixture.loaderFlags)
        #expect(header.numberOfRvaAndSizes == OptionalHeaderFixture.directoryCount)
    }
}
