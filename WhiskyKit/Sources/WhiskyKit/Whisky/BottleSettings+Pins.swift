//
//  BottleSettings+Pins.swift
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

public extension BottleSettings {
    /// Which of a Start Menu scan's findings should be pinned.
    ///
    /// The scan runs every time a bottle screen opens and after every launch,
    /// so this has to be idempotent. It leaves out anything already pinned,
    /// anything the user unpinned and anything on the blocklist, which the
    /// program list hides. Paths compare case-insensitively, the way Windows
    /// and the default macOS volume format treat them.
    ///
    /// - Parameter candidates: Program URLs the scan wants to pin.
    /// - Returns: The candidates that should actually be pinned, in order and
    ///   without duplicates.
    func startMenuPinsToAdd(candidates: [URL]) -> [URL] {
        let refused = Set((unpinnedPrograms + blocklist).map(Self.pinKey))
        var seen = Set(pins.compactMap { $0.url.map(Self.pinKey) })
        return candidates.filter { candidate in
            let key = Self.pinKey(candidate)
            guard !refused.contains(key) else { return false }
            return seen.insert(key).inserted
        }
    }

    /// Removes the pin for `url` and remembers that the user unpinned it, so
    /// the Start Menu scan does not pin it again.
    mutating func unpin(_ url: URL) {
        pins.removeAll { $0.url == url }
        let key = Self.pinKey(url)
        if !unpinnedPrograms.contains(where: { Self.pinKey($0) == key }) {
            unpinnedPrograms.append(url)
        }
    }

    /// Whether the user unpinned `url` and hasn't pinned it again since.
    func isUnpinned(_ url: URL) -> Bool {
        let key = Self.pinKey(url)
        return unpinnedPrograms.contains { Self.pinKey($0) == key }
    }

    /// Forgets that the user unpinned `url`, because they pinned it again.
    ///
    /// Check ``isUnpinned(_:)`` first when the settings live in an observed
    /// property: any mutating call fires its setter, which saves the file.
    mutating func clearUnpin(_ url: URL) {
        let key = Self.pinKey(url)
        unpinnedPrograms.removeAll { Self.pinKey($0) == key }
    }

    /// The unpin records that still name an existing file, without duplicates.
    ///
    /// A record for an uninstalled program has nothing left to protect, and a
    /// fresh install of it should be pinned like any other new program.
    ///
    /// - Parameter fileExists: Whether a path exists. Injected for tests.
    func prunedUnpinnedPrograms(
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> [URL] {
        var seen: Set<String> = []
        return unpinnedPrograms.filter { url in
            guard fileExists(url.path(percentEncoded: false)) else { return false }
            return seen.insert(Self.pinKey(url)).inserted
        }
    }

    /// Points every pin, blocklist entry and unpin record inside the bottle at
    /// `old` to the same file inside `new`, for a bottle move or duplicate.
    mutating func rewriteProgramURLs(from old: URL, to new: URL) {
        for index in pins.indices {
            if let pinURL = pins[index].url {
                pins[index].url = pinURL.updateParentBottle(old: old, new: new)
            }
        }
        blocklist = blocklist.map { $0.updateParentBottle(old: old, new: new) }
        unpinnedPrograms = unpinnedPrograms.map { $0.updateParentBottle(old: old, new: new) }
    }

    /// Restores the pins, blocklist and unpin records of `snapshot`, undoing
    /// ``rewriteProgramURLs(from:to:)`` after a move that failed.
    mutating func restoreProgramURLs(from snapshot: BottleSettings) {
        pins = snapshot.pins
        blocklist = snapshot.blocklist
        unpinnedPrograms = snapshot.unpinnedPrograms
    }

    /// The key two program URLs are compared by: the standardized path,
    /// lowercased.
    private static func pinKey(_ url: URL) -> String {
        url.standardizedFileURL.path(percentEncoded: false).lowercased()
    }
}
