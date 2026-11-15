//
//  OptionalHeader.swift
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
    /// Optional Header
    ///
    /// https://learn.microsoft.com/en-us/windows/win32/debug/pe-format#optional-header-image-only
    public struct OptionalHeader: Hashable, Equatable, Sendable {
        // Standard Fields

        public let magic: Magic
        public let majorLinkerVersion: UInt8
        public let minorLinkerVersion: UInt8
        public let sizeOfCode: UInt32
        public let sizeOfInitializedData: UInt32
        public let sizeOfUninitializedData: UInt32
        public let addressOfEntryPoint: UInt32
        public let baseOfCode: UInt32
        public let baseOfData: UInt32?

        // Windows-Specific Fields

        public let imageBase: UInt64
        public let sectionAlignment: UInt32
        public let fileAlignment: UInt32
        public let majorOperatingSystemVersion: UInt16
        public let minorOperatingSystemVersion: UInt16
        public let majorImageVersion: UInt16
        public let minorImageVersion: UInt16
        public let majorSubsystemVersion: UInt16
        public let minorSubsystemVersion: UInt16
        public let win32VersionValue: UInt32
        public let sizeOfImage: UInt32
        public let sizeOfHeaders: UInt32
        public let checkSum: UInt32
        public let subsystem: UInt16
        public let dllCharacteristics: UInt16
        /// The reserve and commit sizes are 8 bytes wide in a PE32+ image and
        /// 4 in a PE32 one, so they are held at the wider size for both.
        public let sizeOfStackReserve: UInt64
        public let sizeOfStackCommit: UInt64
        public let sizeOfHeapReserve: UInt64
        public let sizeOfHeapCommit: UInt64
        public let loaderFlags: UInt32
        public let numberOfRvaAndSizes: UInt32

        // swiftlint:disable:next function_body_length
        init?(handle: FileHandle, offset: UInt64) {
            var offset = offset
            let rawMagic = handle.extract(UInt16.self, offset: offset) ?? 0
            let magic = Magic(rawValue: rawMagic) ?? .unknown
            self.magic = magic
            offset += 2
            self.majorLinkerVersion = handle.extract(UInt8.self, offset: offset) ?? 0
            offset += 1
            self.minorLinkerVersion = handle.extract(UInt8.self, offset: offset) ?? 0
            offset += 1
            self.sizeOfCode = handle.extract(UInt32.self, offset: offset) ?? 0
            offset += 4
            self.sizeOfInitializedData = handle.extract(UInt32.self, offset: offset) ?? 0
            offset += 4
            self.sizeOfUninitializedData = handle.extract(UInt32.self, offset: offset) ?? 0
            offset += 4
            self.addressOfEntryPoint = handle.extract(UInt32.self, offset: offset) ?? 0
            offset += 4
            self.baseOfCode = handle.extract(UInt32.self, offset: offset) ?? 0
            offset += 4

            switch magic {
            case .pe32Plus:
                // PE32+ does not contain this field, following BaseOfCode is a larger ImageBase instead.
                self.baseOfData = nil

                // PE32+ images have a 8 byte ImageBase field
                self.imageBase = handle.extract(UInt64.self, offset: offset) ?? 0
                offset += 8
            default:
                // PE32 contains this additional field, following BaseOfCode.
                self.baseOfData = handle.extract(UInt32.self, offset: offset) ?? 0
                offset += 4

                // PE32 images have a 4 byte ImageBase field
                let imageBase = handle.extract(UInt32.self, offset: offset) ?? 0
                self.imageBase = UInt64(imageBase)
                offset += 4
            }

            self.sectionAlignment = handle.extract(UInt32.self, offset: offset) ?? 0
            offset += 4
            self.fileAlignment = handle.extract(UInt32.self, offset: offset) ?? 0
            offset += 4
            self.majorOperatingSystemVersion = handle.extract(UInt16.self, offset: offset) ?? 0
            offset += 2
            self.minorOperatingSystemVersion = handle.extract(UInt16.self, offset: offset) ?? 0
            offset += 2
            self.majorImageVersion = handle.extract(UInt16.self, offset: offset) ?? 0
            offset += 2
            self.minorImageVersion = handle.extract(UInt16.self, offset: offset) ?? 0
            offset += 2
            self.majorSubsystemVersion = handle.extract(UInt16.self, offset: offset) ?? 0
            offset += 2
            self.minorSubsystemVersion = handle.extract(UInt16.self, offset: offset) ?? 0
            offset += 2
            self.win32VersionValue = handle.extract(UInt32.self, offset: offset) ?? 0
            offset += 4
            self.sizeOfImage = handle.extract(UInt32.self, offset: offset) ?? 0
            offset += 4
            self.sizeOfHeaders = handle.extract(UInt32.self, offset: offset) ?? 0
            offset += 4
            self.checkSum = handle.extract(UInt32.self, offset: offset) ?? 0
            offset += 4
            self.subsystem = handle.extract(UInt16.self, offset: offset) ?? 0
            offset += 2
            self.dllCharacteristics = handle.extract(UInt16.self, offset: offset) ?? 0
            offset += 2
            // PE32+ widens these four to 8 bytes. Read as 4, they put LoaderFlags,
            // NumberOfRvaAndSizes and the data directories 16 bytes early.
            let wideSizes = magic == .pe32Plus
            let sizeWidth: UInt64 = wideSizes ? 8 : 4
            self.sizeOfStackReserve = Self.sizeField(handle: handle, offset: offset, wide: wideSizes)
            offset += sizeWidth
            self.sizeOfStackCommit = Self.sizeField(handle: handle, offset: offset, wide: wideSizes)
            offset += sizeWidth
            self.sizeOfHeapReserve = Self.sizeField(handle: handle, offset: offset, wide: wideSizes)
            offset += sizeWidth
            self.sizeOfHeapCommit = Self.sizeField(handle: handle, offset: offset, wide: wideSizes)
            offset += sizeWidth
            self.loaderFlags = handle.extract(UInt32.self, offset: offset) ?? 0
            offset += 4
            self.numberOfRvaAndSizes = handle.extract(UInt32.self, offset: offset) ?? 0
        }

        /// A stack or heap size field: 8 bytes in a PE32+ image, 4 otherwise.
        private static func sizeField(handle: FileHandle, offset: UInt64, wide: Bool) -> UInt64 {
            if wide {
                return handle.extract(UInt64.self, offset: offset) ?? 0
            }
            return UInt64(handle.extract(UInt32.self, offset: offset) ?? 0)
        }
    }
}
