//
//  ResourceDataEntry.swift
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

/// Each Resource Data entry describes an actual unit of raw data in the Resource Data area
///
/// https://learn.microsoft.com/en-us/windows/win32/debug/pe-format#resource-data-entry
public struct ResourceDataEntry: Hashable, Equatable {
    public let dataRVA: UInt32
    public let size: UInt32
    public let codePage: UInt32

    init?(handle: FileHandle, offset: UInt64) {
        var offset = offset
        self.dataRVA = handle.extract(UInt32.self, offset: offset) ?? 0
        offset += 4
        self.size = handle.extract(UInt32.self, offset: offset) ?? 0
        offset += 4
        self.codePage = handle.extract(UInt32.self, offset: offset) ?? 0
        offset += 4
        let reserved = handle.extract(UInt32.self, offset: offset) ?? 0
        offset += 4
        guard reserved == 0 else { return nil }
    }

    public func resolveRVA(sections: [PEFile.Section]) -> UInt32? {
        // All operands come from the file, so do the math in 64-bit: crafted
        // headers must produce nil, never an overflow trap.
        sections
            .first { section in
                let sectionEnd = UInt64(section.virtualAddress) + UInt64(section.virtualSize)
                return section.virtualAddress <= dataRVA && UInt64(dataRVA) < sectionEnd
            }
            .flatMap { section in
                let resolved = UInt64(section.pointerToRawData) + UInt64(dataRVA - section.virtualAddress)
                return UInt32(exactly: resolved)
            }
    }
}
