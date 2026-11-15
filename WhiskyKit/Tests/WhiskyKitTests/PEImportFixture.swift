//
//  PEImportFixture.swift
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

/// A synthetic PE image with an import table and a delay-load import table,
/// in one `.idata` section: the names first, then the normal descriptors,
/// then the delay descriptors, each table ended by a null descriptor.
struct PEImportFixture {
    var pe32Plus = true
    /// DLL names in the normal import table, in order.
    var normalImports: [String] = []
    /// DLL names in the delay-load import table, in order.
    var delayImports: [String] = []
    /// Writes the delay descriptors the Visual C++ 6 way: attributes 0, and
    /// the name as a virtual address rather than a relative one.
    var delayVirtualAddresses = false
    /// The header's data directory count.
    var numberOfRvaAndSizes: UInt32 = 16
    /// Adds a first normal descriptor whose name lies in the section's
    /// zero-filled tail, outside the file.
    var danglingNormalName = false
    /// Continues the file past the section with `ghost.dll` where the
    /// dangling name would land if the tail were read from the file, so only
    /// the section's raw size keeps it out.
    var bytesBehindDanglingName = false
    /// Writes all 16 data directories whatever ``numberOfRvaAndSizes`` says,
    /// so only the count keeps the ones past it out.
    var directoriesPastCount = false

    static let sectionRVA: UInt32 = 0x1000
    static let sectionOffset = 0x400
    static let normalDescriptorSize = 20
    static let delayDescriptorSize = 32

    var imageBase: UInt64 {
        pe32Plus ? 0x1_4000_0000 : 0x400000
    }

    /// The offset of the normal import table in the file.
    var normalTableOffset: Int {
        Self.sectionOffset + namesBlob.data.count
    }

    /// The image's bytes.
    func data() -> Data {
        let names = namesBlob
        var section = names.data
        let normalRVA = Self.sectionRVA + UInt32(section.count)
        let rawSizeEstimate = section.count + (normalImports.count + 2) * Self.normalDescriptorSize
            + (delayImports.count + 1) * Self.delayDescriptorSize
        let danglingDelta = rawSizeEstimate + 0x800
        if danglingNormalName {
            // Past the raw data, inside the virtual size.
            section.append(normalDescriptor(nameRVA: Self.sectionRVA + UInt32(danglingDelta)))
        }
        for name in normalImports {
            section.append(normalDescriptor(nameRVA: Self.sectionRVA + UInt32(names.offsets[name] ?? 0)))
        }
        section.append(Data(count: Self.normalDescriptorSize))
        let normalSize = Self.sectionRVA + UInt32(section.count) - normalRVA

        let delayRVA = Self.sectionRVA + UInt32(section.count)
        for name in delayImports {
            section.append(delayDescriptor(nameRVA: Self.sectionRVA + UInt32(names.offsets[name] ?? 0)))
        }
        section.append(Data(count: Self.delayDescriptorSize))
        let delaySize = Self.sectionRVA + UInt32(section.count) - delayRVA

        var directories = [(UInt32, UInt32)](repeating: (0, 0), count: 16)
        directories[1] = normalImports.isEmpty && !danglingNormalName ? (0, 0) : (normalRVA, normalSize)
        directories[13] = delayImports.isEmpty ? (0, 0) : (delayRVA, delaySize)

        let rawSize = (section.count + 0x1FF) & ~0x1FF
        section.append(Data(count: rawSize - section.count))

        var image = Data(count: 0x80)
        image[0] = 0x4D
        image[1] = 0x5A
        image.replaceLE(UInt32(0x80), at: 0x3C)
        image.append(contentsOf: [0x50, 0x45, 0x00, 0x00])
        image.append(coffHeader())
        image.append(optionalHeader(directories: directories))
        image.append(sectionHeader(rawSize: rawSize))
        image.append(Data(count: Self.sectionOffset - image.count))
        image.append(section)
        if bytesBehindDanglingName {
            image.append(Data(count: Self.sectionOffset + danglingDelta - image.count))
            image.append(contentsOf: Array("ghost.dll".utf8) + [0])
            image.append(Data(count: 0x200))
        }
        return image
    }

    /// Writes the image to `url`, creating its folder.
    func write(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data().write(to: url)
    }

    // MARK: - Parts

    /// Every name once, NUL-terminated, with its offset in the section.
    private var namesBlob: (data: Data, offsets: [String: Int]) {
        var data = Data()
        var offsets: [String: Int] = [:]
        for name in normalImports + delayImports where offsets[name] == nil {
            offsets[name] = data.count
            data.append(contentsOf: Array(name.utf8) + [0])
        }
        while data.count % 4 != 0 {
            data.append(0)
        }
        return (data, offsets)
    }

    private func normalDescriptor(nameRVA: UInt32) -> Data {
        var data = Data(count: Self.normalDescriptorSize)
        data.replaceLE(UInt32(0x2000), at: 0) // OriginalFirstThunk
        data.replaceLE(nameRVA, at: 12)
        data.replaceLE(UInt32(0x2000), at: 16) // FirstThunk
        return data
    }

    private func delayDescriptor(nameRVA: UInt32) -> Data {
        var data = Data(count: Self.delayDescriptorSize)
        if delayVirtualAddresses {
            data.replaceLE(UInt32(truncatingIfNeeded: UInt64(nameRVA) + imageBase), at: 4)
        } else {
            data.replaceLE(UInt32(1), at: 0) // RVA-based
            data.replaceLE(nameRVA, at: 4)
        }
        data.replaceLE(UInt32(0x3000), at: 8) // ModuleHandleRVA
        data.replaceLE(UInt32(0x3008), at: 12) // ImportAddressTableRVA
        data.replaceLE(UInt32(0x3010), at: 16) // ImportNameTableRVA
        return data
    }

    private var optionalHeaderSize: Int {
        (pe32Plus ? 112 : 96) + 16 * 8
    }

    private func coffHeader() -> Data {
        var data = Data(count: 20)
        data.replaceLE(UInt16(pe32Plus ? 0x8664 : 0x14C), at: 0)
        data.replaceLE(UInt16(1), at: 2)
        data.replaceLE(UInt16(optionalHeaderSize), at: 16)
        data.replaceLE(UInt16(0x0022), at: 18)
        return data
    }

    private func optionalHeader(directories: [(UInt32, UInt32)]) -> Data {
        var data = Data(count: optionalHeaderSize)
        data.replaceLE(UInt16(pe32Plus ? 0x20B : 0x10B), at: 0)
        if pe32Plus {
            data.replaceLE(imageBase, at: 24)
        } else {
            data.replaceLE(UInt32(imageBase), at: 28)
        }
        data.replaceLE(UInt32(0x1000), at: 32) // SectionAlignment
        data.replaceLE(UInt32(0x200), at: 36) // FileAlignment
        data.replaceLE(UInt32(0x10000), at: 56) // SizeOfImage
        data.replaceLE(UInt32(Self.sectionOffset), at: 60) // SizeOfHeaders
        data.replaceLE(UInt16(2), at: 68) // Subsystem: GUI
        let countOffset = pe32Plus ? 108 : 92
        data.replaceLE(numberOfRvaAndSizes, at: countOffset)
        for (index, directory) in directories.enumerated()
            where directoriesPastCount || index < Int(numberOfRvaAndSizes) {
            data.replaceLE(directory.0, at: countOffset + 4 + index * 8)
            data.replaceLE(directory.1, at: countOffset + 8 + index * 8)
        }
        return data
    }

    private func sectionHeader(rawSize: Int) -> Data {
        var data = Data(count: 40)
        data.replaceSubrange(0 ..< 6, with: Array(".idata".utf8))
        data.replaceLE(UInt32(rawSize + 0x1000), at: 8) // VirtualSize
        data.replaceLE(Self.sectionRVA, at: 12)
        data.replaceLE(UInt32(rawSize), at: 16) // SizeOfRawData
        data.replaceLE(UInt32(Self.sectionOffset), at: 20) // PointerToRawData
        data.replaceLE(UInt32(0xC000_0040), at: 36) // Characteristics
        return data
    }
}

private extension Data {
    mutating func replaceLE(_ value: some FixedWidthInteger, at offset: Int) {
        let bytes = Swift.withUnsafeBytes(of: value.littleEndian) { Array($0) }
        replaceSubrange(offset ..< offset + bytes.count, with: bytes)
    }
}
