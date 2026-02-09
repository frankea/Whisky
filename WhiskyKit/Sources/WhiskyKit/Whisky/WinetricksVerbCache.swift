//
//  WinetricksVerbCache.swift
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

/// Cached state of installed winetricks verbs for a bottle.
///
/// Stores the set of installed verb names alongside metadata about the
/// `winetricks.log` file that was current when the cache was last refreshed.
/// This enables cheap staleness detection without spawning a subprocess.
///
/// ## Storage
///
/// Persisted as `WinetricksCache.plist` in the bottle directory alongside
/// `Metadata.plist`, keeping the main settings file uncluttered.
///
/// ## Staleness Detection
///
/// ```swift
/// let logInfo = WinetricksVerbCache.winetricksLogInfo(for: bottleURL)
/// if cache.isStale(currentLogSize: logInfo.size, currentLogModDate: logInfo.modDate) {
///     // Re-run winetricks list-installed
/// }
/// ```
public struct WinetricksVerbCache: Codable, Sendable {
    /// The set of verb names that were installed when the cache was last checked.
    public var installedVerbs: Set<String>

    /// The date when the installed verbs were last verified.
    public var lastChecked: Date

    /// The byte size of the winetricks.log file at the time of the last check.
    public var logFileSize: Int64?

    /// The modification date of the winetricks.log file at the time of the last check.
    public var logFileModDate: Date?

    /// Creates a new verb cache.
    ///
    /// - Parameters:
    ///   - installedVerbs: The set of installed verb names. Defaults to empty.
    ///   - lastChecked: When the verbs were last verified. Defaults to `.distantPast`.
    public init(installedVerbs: Set<String> = [], lastChecked: Date = .distantPast) {
        self.installedVerbs = installedVerbs
        self.lastChecked = lastChecked
    }

    /// Whether the cache may be stale based on winetricks.log file changes.
    ///
    /// The cache is considered stale if:
    /// - No log metadata was recorded (first check or log didn't exist)
    /// - The log file size has changed
    /// - The log file modification date has changed
    ///
    /// - Parameters:
    ///   - currentLogSize: The current byte size of the winetricks.log file, or nil if missing.
    ///   - currentLogModDate: The current modification date, or nil if missing.
    /// - Returns: `true` if the cache should be refreshed.
    public func isStale(currentLogSize: Int64?, currentLogModDate: Date?) -> Bool {
        // Stale if we never recorded log metadata
        guard let cachedSize = logFileSize, let cachedDate = logFileModDate else {
            return true
        }

        // Stale if the log file disappeared
        guard let currentSize = currentLogSize, let currentDate = currentLogModDate else {
            return true
        }

        // Stale if size or modification date changed
        return cachedSize != currentSize || cachedDate != currentDate
    }

    // MARK: - Persistence

    private static let cacheFileName = "WinetricksCache.plist"

    /// Loads the verb cache from the bottle directory.
    ///
    /// - Parameter bottleURL: The URL of the bottle directory.
    /// - Returns: The cached verb data, or `nil` if no cache exists or it cannot be decoded.
    public static func load(from bottleURL: URL) -> WinetricksVerbCache? {
        let cacheURL = bottleURL.appending(path: cacheFileName)
        guard let data = try? Data(contentsOf: cacheURL) else {
            return nil
        }
        return try? PropertyListDecoder().decode(WinetricksVerbCache.self, from: data)
    }

    /// Saves the verb cache to the bottle directory.
    ///
    /// - Parameters:
    ///   - cache: The cache to persist.
    ///   - bottleURL: The URL of the bottle directory.
    /// - Throws: An error if encoding or writing fails.
    public static func save(_ cache: WinetricksVerbCache, to bottleURL: URL) throws {
        let cacheURL = bottleURL.appending(path: cacheFileName)
        let data = try PropertyListEncoder().encode(cache)
        try data.write(to: cacheURL)
    }

    /// Reads the file attributes of the winetricks.log in the bottle.
    ///
    /// Checks both the prefix root (`<bottleURL>/winetricks.log`) and the
    /// drive_c location (`<bottleURL>/drive_c/winetricks.log`), preferring
    /// whichever exists (prefix root first, which is the standard location).
    ///
    /// - Parameter bottleURL: The URL of the bottle directory.
    /// - Returns: A tuple of the file size in bytes and the modification date,
    ///   with `nil` values if the file does not exist.
    public static func winetricksLogInfo(
        for bottleURL: URL
    ) -> (size: Int64?, modDate: Date?) {
        // Standard winetricks.log location is at the prefix root
        let prefixLogURL = bottleURL.appending(path: "winetricks.log")
        // Some configurations write to drive_c
        let driveCLogURL = bottleURL
            .appending(path: "drive_c")
            .appending(path: "winetricks.log")

        let logURL: URL
        if FileManager.default.fileExists(atPath: prefixLogURL.path(percentEncoded: false)) {
            logURL = prefixLogURL
        } else if FileManager.default.fileExists(atPath: driveCLogURL.path(percentEncoded: false)) {
            logURL = driveCLogURL
        } else {
            return (nil, nil)
        }

        guard let attrs = try? FileManager.default.attributesOfItem(
            atPath: logURL.path(percentEncoded: false)
        )
        else {
            return (nil, nil)
        }

        let size = attrs[.size] as? Int64
        let modDate = attrs[.modificationDate] as? Date
        return (size, modDate)
    }
}
