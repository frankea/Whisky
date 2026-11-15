//
//  ImportTable.swift
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

import Foundation

/// Intentionally not marked public to avoid Swift 6 redundant access modifiers.
/// Nested types remain public to preserve the API surface.
extension PEFile {
    /// The DLL names an image imports, from its import table and its
    /// delay-load import table, each read on its own.
    ///
    /// Only the names are read, never the imported functions, so a 200 MB
    /// Electron executable costs a few KB of reads. The parse is bounded: at
    /// most ``maxDescriptors`` descriptors across both tables, names of at
    /// most ``maxNameLength`` bytes, and it stops at the null descriptor or at
    /// the first offset outside the file.
    ///
    /// The two are kept apart because they mean different things. Chromium
    /// delay-loads `d3d11.dll` and `dxgi.dll`, and Electron 45 delay-loads
    /// `ffmpeg.dll` too, while a program that draws with Direct3D itself
    /// usually imports it normally.
    ///
    /// https://learn.microsoft.com/en-us/windows/win32/debug/pe-format#the-idata-section
    /// https://learn.microsoft.com/en-us/windows/win32/debug/pe-format#delay-load-import-tables-image-only
    public struct ImportTable: Hashable, Equatable, Sendable {
        /// The most descriptors read, across both tables.
        public static let maxDescriptors = 1_024
        /// The longest DLL name read, in bytes, terminator included.
        public static let maxNameLength = 256

        /// The DLLs the loader binds at startup, lowercased.
        public let normalImports: Set<String>
        /// The DLLs bound on first call, lowercased.
        public let delayImports: Set<String>

        /// Every DLL the image names, in either table.
        public var allImports: Set<String> {
            normalImports.union(delayImports)
        }

        public init(normalImports: Set<String>, delayImports: Set<String>) {
            self.normalImports = normalImports
            self.delayImports = delayImports
        }

        /// Reads both tables of a parsed image.
        ///
        /// - Parameters:
        ///   - handle: The image, open for reading.
        ///   - fileSize: The image's size, past which nothing is read.
        ///   - optionalHeader: The image's optional header, with its data directories.
        ///   - sections: The image's section table, to map addresses to file offsets.
        init(handle: FileHandle, fileSize: UInt64, optionalHeader: OptionalHeader, sections: [Section]) {
            var reader = DescriptorReader(
                handle: handle, fileSize: fileSize, sections: sections,
                imageBase: optionalHeader.imageBase, budget: Self.maxDescriptors
            )
            self.normalImports = optionalHeader.dataDirectory(.importTable)
                .map { reader.names(in: $0, layout: .normal) } ?? []
            self.delayImports = optionalHeader.dataDirectory(.delayImportDescriptor)
                .map { reader.names(in: $0, layout: .delay) } ?? []
        }
    }

    /// Reads the image's import tables. Opens the file once.
    ///
    /// - Returns: The DLLs the image names, or `nil` when the file cannot be
    ///   read or has no optional header.
    public func importTable() -> ImportTable? {
        guard let optionalHeader, let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer {
            try? handle.close()
        }
        guard let fileSize = try? handle.seekToEnd() else { return nil }
        return ImportTable(handle: handle, fileSize: fileSize, optionalHeader: optionalHeader, sections: sections)
    }

    /// The file offset of a relative virtual address, through the section
    /// table: `nil` when no section holds it, or it falls in a section's
    /// zero-filled tail, or past the end of the file.
    static func fileOffset(forRVA rva: UInt32, sections: [Section], fileSize: UInt64) -> UInt64? {
        let address = UInt64(rva)
        for section in sections {
            let start = UInt64(section.virtualAddress)
            let span = UInt64(max(section.virtualSize, section.sizeOfRawData))
            guard address >= start, address - start < span else { continue }
            let delta = address - start
            guard delta < UInt64(section.sizeOfRawData) else { return nil }
            let offset = UInt64(section.pointerToRawData) + delta
            return offset < fileSize ? offset : nil
        }
        return nil
    }
}

// MARK: - Descriptor walk

/// Walks import descriptors under a budget shared by both tables.
private struct DescriptorReader {
    /// Where a descriptor keeps the fields this reader needs.
    enum Layout {
        /// `IMAGE_IMPORT_DESCRIPTOR`: 20 bytes, the name's address at 12.
        case normal
        /// `IMAGE_DELAYLOAD_DESCRIPTOR`: 32 bytes, attributes at 0, the name's address at 4.
        case delay

        var size: UInt64 {
            switch self {
            case .normal: 20
            case .delay: 32
            }
        }

        var nameField: Int {
            switch self {
            case .normal: 12
            case .delay: 4
            }
        }
    }

    let handle: FileHandle
    let fileSize: UInt64
    let sections: [PEFile.Section]
    let imageBase: UInt64
    /// Descriptors left to read, across both tables.
    var budget: Int

    mutating func names(in directory: PEFile.DataDirectory, layout: Layout) -> Set<String> {
        guard var offset = PEFile.fileOffset(
            forRVA: directory.virtualAddress, sections: sections, fileSize: fileSize
        )
        else { return [] }

        var names: Set<String> = []
        while budget > 0 {
            guard let descriptor = read(count: Int(layout.size), at: offset), UInt64(descriptor.count) == layout.size,
                  descriptor.contains(where: { $0 != 0 })
            else { break }
            budget -= 1
            offset += layout.size
            if let rva = nameRVA(in: descriptor, layout: layout), let name = name(at: rva) {
                names.insert(name)
            }
        }
        return names
    }

    /// The descriptor's name as a relative virtual address. An old delay
    /// descriptor (attributes bit 0 clear, as Visual C++ 6 wrote them) holds a
    /// virtual address instead, which the image base turns back into one.
    private func nameRVA(in descriptor: Data, layout: Layout) -> UInt32? {
        let field = UInt64(descriptor.littleEndianUInt32(at: layout.nameField))
        guard layout == .delay, descriptor.littleEndianUInt32(at: 0) & 1 == 0 else {
            return UInt32(field)
        }
        guard field >= imageBase else { return nil }
        return UInt32(exactly: field - imageBase)
    }

    /// The NUL-terminated ASCII name at an address, lowercased; `nil` when it
    /// is unterminated within ``PEFile/ImportTable/maxNameLength`` bytes or
    /// outside the file.
    private func name(at rva: UInt32) -> String? {
        guard let offset = PEFile.fileOffset(forRVA: rva, sections: sections, fileSize: fileSize),
              let bytes = read(count: PEFile.ImportTable.maxNameLength, at: offset),
              let end = bytes.firstIndex(of: 0), end > bytes.startIndex
        else { return nil }
        let name = bytes[bytes.startIndex ..< end]
        guard name.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) else { return nil }
        return String(bytes: name, encoding: .ascii)?.lowercased()
    }

    private func read(count: Int, at offset: UInt64) -> Data? {
        guard offset < fileSize else { return nil }
        let available = Int(min(UInt64(count), fileSize - offset))
        do {
            try handle.seek(toOffset: offset)
            return try handle.read(upToCount: available)
        } catch {
            return nil
        }
    }
}

private extension Data {
    func littleEndianUInt32(at index: Int) -> UInt32 {
        let start = startIndex + index
        return self[start ..< start + 4].enumerated().reduce(UInt32(0)) { value, byte in
            value | UInt32(byte.element) << (8 * UInt32(byte.offset))
        }
    }
}
