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

/// A shared, reference-type budget for the total number of directory entries the
/// resource walk may process across the whole tree.
///
/// Each directory entry is 8 bytes, so a crafted file can claim a huge
/// per-table entry count and then have every sibling point at the same
/// oversized subtable, amplifying a small file into millions of processed
/// entries (a denial-of-service). A single budget shared across the entire
/// recursion caps that total. One log line is emitted the first time the budget
/// is exhausted so the truncation is visible without per-entry spam.
private final class TraversalBudget {
    private(set) var remaining: Int
    private let fileName: String
    private var didLogExhaustion = false

    init(_ total: Int, fileName: String) {
        self.remaining = total
        self.fileName = fileName
    }

    /// Consume one unit of budget. Returns `false` once the budget is exhausted.
    func consume() -> Bool {
        guard remaining > 0 else {
            if !didLogExhaustion {
                didLogExhaustion = true
                logger.error(
                    """
                    Resource directory traversal budget exhausted in \
                    \(self.fileName, privacy: .public); truncating remaining entries
                    """
                )
            }
            return false
        }
        remaining -= 1
        return true
    }
}

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

    /// The maximum number of directory entries the entire resource walk may
    /// process. Real resource trees have at most a few thousand entries; this
    /// generous cap stops sibling fan-out amplification from a crafted file
    /// without truncating any legitimate input.
    private static let maxTotalEntries = 100_000

    /// Each resource directory entry is 8 bytes on disk.
    private static let entrySize: UInt64 = 8

    /// Read the Resource Directory Table
    ///
    /// - Parameters:
    ///   - fileHandle: The file handle to read the data from.
    ///   - pointerToRawData: The offset to the Resource Directory Table in the file handle.
    ///   - types: Only read entrys of the given types. Only applies to the root table. Defaults to `nil`.
    ///   - fileName: Display name of the file being parsed, for log attribution.
    init(handle: FileHandle, pointerToRawData: UInt64, types: [ResourceType]?, fileName: String = "<unknown>") {
        self.init(handle: handle, pointerToRawData: pointerToRawData, offset: 0, types: types, fileName: fileName)
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
        types: [ResourceType]? = nil,
        fileName: String = "<unknown>"
    ) {
        var visited: Set<UInt64> = [initialOffset]
        let budget = TraversalBudget(Self.maxTotalEntries, fileName: fileName)
        self.init(
            handle: handle,
            pointerToRawData: pointerToRawData,
            offset: initialOffset,
            types: types,
            fileName: fileName,
            depth: 0,
            visited: &visited,
            budget: budget
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
        fileName: String,
        depth: Int,
        visited: inout Set<UInt64>,
        budget: TraversalBudget
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
            fileName: fileName,
            depth: depth,
            visited: &visited,
            budget: budget
        )
    }

    /// Clamp a claimed per-table entry count to what actually fits in the file.
    ///
    /// A crafted header can claim up to `UInt16.max` entries while the file holds
    /// none of them; iterating the claimed count would read far past EOF (each
    /// read returns zero-filled garbage) and waste time. Capping at the number of
    /// 8-byte entries between `firstEntryOffset` and the end of the file bounds
    /// the loop to real data.
    private static func clampedEntryCount(
        claimed: UInt16,
        firstEntryOffset: UInt64,
        handle: FileHandle,
        fileName: String
    ) -> Int {
        let claimedCount = Int(claimed)
        guard let fileLength = try? handle.seekToEnd() else {
            // A length we can't determine can't bound anything; fail closed
            // rather than iterating an unverifiable claimed count.
            logger.error(
                "Cannot determine length of \(fileName, privacy: .public); skipping resource directory entries"
            )
            return 0
        }
        let fittableEntries = fileLength > firstEntryOffset
            ? Int((fileLength - firstEntryOffset) / Self.entrySize)
            : 0
        if claimedCount > fittableEntries {
            logger.notice(
                """
                Resource table in \(fileName, privacy: .public) claims \(claimedCount) entries; \
                only \(fittableEntries) fit in the file — truncating
                """
            )
        }
        return min(claimedCount, fittableEntries)
    }

    // swiftlint:disable:next function_parameter_count
    private static func readIDEntries(
        handle: FileHandle,
        pointerToRawData: UInt64,
        firstEntryOffset: UInt64,
        count: UInt16,
        types: [ResourceType]?,
        fileName: String,
        depth: Int,
        visited: inout Set<UInt64>,
        budget: TraversalBudget
    ) -> ([ResourceDirectoryTable], [ResourceDataEntry]) {
        var subtables: [ResourceDirectoryTable] = []
        var entries: [ResourceDataEntry] = []
        var offset = firstEntryOffset

        let entryCount = Self.clampedEntryCount(
            claimed: count,
            firstEntryOffset: firstEntryOffset,
            handle: handle,
            fileName: fileName
        )

        for _ in 0 ..< entryCount {
            // Global traversal budget: stop the whole walk once the total number of
            // processed entries is exhausted, defeating sibling fan-out amplification.
            guard budget.consume() else { break }

            let directoryEntry = ResourceDirectoryEntry.ID(handle: handle, offset: offset)
            offset += Self.entrySize

            if let types {
                // If we filter for specific types the directory entry type must be included
                guard types.contains(directoryEntry.type) else {
                    continue
                }
            }

            if directoryEntry.isDirectory {
                if let subtable = Self.readSubtable(
                    handle: handle,
                    pointerToRawData: pointerToRawData,
                    subtableOffset: UInt64(directoryEntry.offset),
                    fileName: fileName,
                    depth: depth,
                    visited: &visited,
                    budget: budget
                ) {
                    subtables.append(subtable)
                }
            } else if let entry = ResourceDataEntry(
                handle: handle,
                offset: pointerToRawData + UInt64(directoryEntry.offset)
            ) {
                entries.append(entry)
            }
        }

        return (subtables, entries)
    }

    // swiftlint:disable function_parameter_count
    /// Recurse into a directory entry's subtable, enforcing the cycle and depth
    /// guards. Returns `nil` (and logs once) when the entry is skipped.
    private static func readSubtable(
        handle: FileHandle,
        pointerToRawData: UInt64,
        subtableOffset: UInt64,
        fileName: String,
        depth: Int,
        visited: inout Set<UInt64>,
        budget: TraversalBudget
    ) -> ResourceDirectoryTable? {
        // swiftlint:enable function_parameter_count
        // A genuine cycle (this offset is an ancestor on the current path) is a
        // malformed-file signal: log it loudly so it is identifiable.
        if visited.contains(subtableOffset) {
            logger.fault(
                """
                Cyclic resource directory in \(fileName, privacy: .public): \
                offset \(subtableOffset, privacy: .public) revisits its own path
                """
            )
            return nil
        }

        // Hitting the depth cap is a benign limit, not a malformed file.
        guard depth < maxTableDepth else {
            logger.notice(
                """
                Resource directory depth limit reached in \(fileName, privacy: .public) \
                at offset \(subtableOffset, privacy: .public)
                """
            )
            return nil
        }

        visited.insert(subtableOffset)
        let subtable = ResourceDirectoryTable(
            handle: handle,
            pointerToRawData: pointerToRawData,
            offset: subtableOffset,
            types: nil,
            fileName: fileName,
            depth: depth + 1,
            visited: &visited,
            budget: budget
        )
        visited.remove(subtableOffset)
        return subtable
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
