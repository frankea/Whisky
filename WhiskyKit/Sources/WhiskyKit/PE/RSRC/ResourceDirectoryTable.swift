//
//  ResourceDirectoryTable.swift
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
import os.log
import SemanticVersion

private let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "ResourceDirectoryTable")

/// This data structure should be considered the heading of a table,
/// because the table actually consists of directory entries
///
/// https://learn.microsoft.com/en-us/windows/win32/debug/pe-format#resource-directory-table
public struct ResourceDirectoryTable: Hashable, Equatable {
    public let characteristics: UInt32
    public let timeDateStamp: Date
    public let version: SemanticVersion
    public let numberOfNameEntries: UInt16
    public let numberOfIdEntries: UInt16

    public let subtables: [ResourceDirectoryTable]
    public let entries: [ResourceDataEntry]

    /// Windows resource trees use three levels by convention (type → name →
    /// language), 0-indexed here as table depths 0–2. The PE/COFF format
    /// technically allows arbitrary depth, but nothing real produces more, so
    /// recursion is capped at this depth to guard against hostile or circular
    /// directories. A directory entry found at this depth is not recursed into.
    private static let maxTableDepth = 2

    /// Read the Resource Directory Table
    ///
    /// - Parameters:
    ///   - fileHandle: The file handle to read the data from.
    ///   - pointerToRawData: The offset to the Resource Directory Table in the file handle.
    ///   - types: Only read entrys of the given types. Only applies to the root table. Defaults to `nil`.
    init(handle: FileHandle, pointerToRawData: UInt64, types: [ResourceType]?) {
        self.init(handle: handle, pointerToRawData: pointerToRawData, offset: 0, types: types)
    }

    /// Read the Resource Directory Table
    ///
    /// - Parameters:
    ///   - fileHandle: The file handle to read the data from.
    ///   - pointerToRawData: The offset to the Resource Directory Table in the file handle.
    ///   - offset: Additional offset to the `pointerToRawData`.
    ///             Use only for sub-tables. The root-table has the offset 0.
    ///   - types: Only read entrys of the given types. Only applies to the root table. Defaults to `nil`.
    init(
        handle: FileHandle,
        pointerToRawData: UInt64,
        offset initialOffset: UInt64,
        types: [ResourceType]? = nil
    ) {
        var visited: Set<UInt64> = [initialOffset]
        self.init(
            handle: handle,
            pointerToRawData: pointerToRawData,
            offset: initialOffset,
            types: types,
            depth: 0,
            visited: &visited
        )
    }

    /// Worker that carries the recursion guards: a hard depth cap (the
    /// stack-overflow bound) and a path-scoped set of ancestor table offsets, so
    /// a crafted file whose directory entry points back up its own branch can't
    /// recurse forever. The visited set is path-scoped (an offset is removed once
    /// its subtree is done), so legitimately shared subtables — a DAG, which the
    /// format permits — still parse on every branch.
    private init(
        handle: FileHandle,
        pointerToRawData: UInt64,
        offset initialOffset: UInt64,
        types: [ResourceType]?,
        depth: Int,
        visited: inout Set<UInt64>
    ) {
        var offset = pointerToRawData + initialOffset
        self.characteristics = handle.extract(UInt32.self, offset: offset) ?? 0
        offset += 4
        let timeDateStamp = handle.extract(UInt32.self, offset: offset) ?? 0
        self.timeDateStamp = Date(timeIntervalSince1970: TimeInterval(timeDateStamp))
        offset += 4
        let majorVersion = handle.extract(UInt16.self, offset: offset) ?? 0
        offset += 2
        let minorVersion = handle.extract(UInt16.self, offset: offset) ?? 0
        offset += 2
        self.version = SemanticVersion(Int(majorVersion), Int(minorVersion), 0)
        let numberOfNameEntries = handle.extract(UInt16.self, offset: offset) ?? 0
        self.numberOfNameEntries = numberOfNameEntries
        offset += 2
        let numberOfIdEntries = handle.extract(UInt16.self, offset: offset) ?? 0
        self.numberOfIdEntries = numberOfIdEntries
        offset += 2

        // We don't care about named entries
        // the entries we're looking for are ID'd
        offset += 8 * UInt64(numberOfNameEntries)

        (self.subtables, self.entries) = Self.readIDEntries(
            handle: handle,
            pointerToRawData: pointerToRawData,
            firstEntryOffset: offset,
            count: numberOfIdEntries,
            types: types,
            depth: depth,
            visited: &visited
        )
    }

    // swiftlint:disable:next function_parameter_count
    private static func readIDEntries(
        handle: FileHandle,
        pointerToRawData: UInt64,
        firstEntryOffset: UInt64,
        count: UInt16,
        types: [ResourceType]?,
        depth: Int,
        visited: inout Set<UInt64>
    ) -> ([ResourceDirectoryTable], [ResourceDataEntry]) {
        var subtables: [ResourceDirectoryTable] = []
        var entries: [ResourceDataEntry] = []
        var offset = firstEntryOffset

        for _ in 0 ..< count {
            let directoryEntry = ResourceDirectoryEntry.ID(handle: handle, offset: offset)
            offset += 8

            if let types {
                // If we filter for specific types the directory entry type must be included
                guard types.contains(directoryEntry.type) else {
                    continue
                }
            }

            if directoryEntry.isDirectory {
                let subtableOffset = UInt64(directoryEntry.offset)
                guard depth < Self.maxTableDepth, !visited.contains(subtableOffset) else {
                    logger.notice(
                        "Truncating resource directory: depth or cycle limit hit at offset \(subtableOffset)"
                    )
                    continue
                }
                visited.insert(subtableOffset)
                let subtable = ResourceDirectoryTable(
                    handle: handle,
                    pointerToRawData: pointerToRawData,
                    offset: subtableOffset,
                    types: nil,
                    depth: depth + 1,
                    visited: &visited
                )
                visited.remove(subtableOffset)
                subtables.append(subtable)
            } else if let entry = ResourceDataEntry(
                handle: handle,
                offset: pointerToRawData + UInt64(directoryEntry.offset)
            ) {
                entries.append(entry)
            }
        }

        return (subtables, entries)
    }

    /// Access all entries from this table and all its subtables
    public var allEntries: [ResourceDataEntry] {
        var entries = self.entries
        for subtable in subtables {
            entries.append(contentsOf: subtable.allEntries)
        }
        return entries
    }
}
