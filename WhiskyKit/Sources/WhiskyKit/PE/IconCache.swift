//
//  IconCache.swift
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

import AppKit
import Foundation

/// Thread-safe cache for program icons extracted from PE files.
///
/// This actor-based cache reduces redundant PE file parsing by storing extracted icons
/// in memory. Icons are expensive to extract as they require parsing the PE resource
/// section and converting bitmap data.
///
/// ## Usage
/// ```swift
/// let icon = await IconCache.shared.iconAsync(for: programURL)
/// ```
public actor IconCache {
    /// The shared icon cache instance.
    public static let shared = IconCache()

    private let memoryCache = NSCache<NSURL, NSImage>()

    private init() {
        memoryCache.countLimit = 100
        memoryCache.totalCostLimit = 50 * 1_024 * 1_024 // 50MB limit
    }

    /// Retrieves a cached icon or extracts and caches it.
    ///
    /// If the icon for the given URL is already cached, it is returned immediately.
    /// Otherwise, the PE file is parsed and the best icon is extracted and cached.
    ///
    /// - Parameters:
    ///   - url: The URL of the PE executable file.
    ///   - peFile: An optional pre-parsed PE file. If not provided, the file will be parsed.
    /// - Returns: The extracted icon, or `nil` if extraction fails.
    public func icon(for url: URL, peFile: PEFile? = nil) -> NSImage? {
        if let cached = memoryCache.object(forKey: url as NSURL) {
            return cached
        }

        let pefile = peFile ?? (try? PEFile(url: url))
        guard let icon = pefile?.bestIcon() else { return nil }

        memoryCache.setObject(icon, forKey: url as NSURL)
        return icon
    }

    /// Asynchronously loads an icon, using cache when available.
    ///
    /// This is the preferred method for loading icons from SwiftUI views,
    /// as it can be called from a `Task` context.
    ///
    /// - Parameters:
    ///   - url: The URL of the PE executable file.
    ///   - peFile: An optional pre-parsed PE file. If not provided, the file will be parsed.
    /// - Returns: The extracted icon, or `nil` if extraction fails.
    public func iconAsync(for url: URL, peFile: PEFile? = nil) -> NSImage? {
        icon(for: url, peFile: peFile)
    }

    /// Removes a specific icon from the cache.
    ///
    /// Call this when a program is deleted or its executable is modified.
    ///
    /// - Parameter url: The URL of the PE file to remove from cache.
    public func invalidate(url: URL) {
        memoryCache.removeObject(forKey: url as NSURL)
    }

    /// Clears all cached icons.
    ///
    /// This can be called in response to memory pressure or when bottles are deleted.
    public func clearCache() {
        memoryCache.removeAllObjects()
    }
}
