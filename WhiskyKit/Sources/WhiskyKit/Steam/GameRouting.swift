//
//  GameRouting.swift
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

/// Remembers which bottle each Steam App ID was last launched from, so a game
/// can be launched by App ID alone (from the CLI, or later from a URL) without
/// asking which bottle every time.
///
/// Deliberately a plain dictionary on disk rather than a database: the file is
/// hand-readable, a missing or corrupt entry only costs one prompt, and a wrong
/// entry is corrected by the next launch.
public struct GameRouting {
    /// The default store, alongside the bottle registry.
    public static var defaultURL: URL {
        BottleData.containerDir.appending(path: "GameRouting").appendingPathExtension("plist")
    }

    private let url: URL

    /// Creates a routing store.
    ///
    /// - Parameter url: The plist to read and write. Defaults to ``defaultURL``.
    public init(url: URL = GameRouting.defaultURL) {
        self.url = url
    }

    /// The bottle a game was last launched from.
    public func bottleURL(forAppId appId: Int) -> URL? {
        entries()[String(appId)].map { URL(fileURLWithPath: $0) }
    }

    /// All known routes, keyed by App ID.
    public func routes() -> [Int: URL] {
        var result: [Int: URL] = [:]
        for (key, path) in entries() {
            if let appId = Int(key) {
                result[appId] = URL(fileURLWithPath: path)
            }
        }
        return result
    }

    /// Records the bottle a game was launched from, replacing any previous
    /// route for that App ID (last launch wins).
    public func record(appId: Int, bottleURL: URL) {
        var current = entries()
        current[String(appId)] = bottleURL.path(percentEncoded: false)
        write(current)
    }

    /// Forgets every route pointing at a bottle, e.g. when the bottle is
    /// deleted.
    ///
    /// Paths are compared through `standardizedFileURL`, the same way
    /// resolution matches a route against the bottle list, so exactly the
    /// routes that would have named this bottle are the ones removed. When
    /// nothing matches the store is left untouched (and never created).
    public func removeRoutes(toBottle bottleURL: URL) {
        let target = bottleURL.standardizedFileURL
        let current = entries()
        let remaining = current.filter { URL(fileURLWithPath: $0.value).standardizedFileURL != target }
        guard remaining.count != current.count else { return }
        write(remaining)
    }

    private func entries() -> [String: String] {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = plist as? [String: String]
        else { return [:] }
        return dictionary
    }

    private func write(_ entries: [String: String]) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let data = try PropertyListSerialization.data(
                fromPropertyList: entries, format: .xml, options: 0
            )
            try data.write(to: url, options: .atomic)
        } catch {
            Logger.wineKit.error("Failed to write game routing: \(error.localizedDescription)")
        }
    }
}
