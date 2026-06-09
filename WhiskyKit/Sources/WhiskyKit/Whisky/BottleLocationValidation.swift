//
//  BottleLocationValidation.swift
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

/// Pre-flight validation of a user-chosen bottle parent directory.
///
/// Run this *before* the bottle subdirectory is created and `wineboot`
/// initializes the prefix, so an unusable location surfaces a clear, actionable
/// error up front instead of a cryptic late Wine failure (issue #61).
///
/// Only the two checks that confidently and directly predict failure are
/// enforced: whether the location can be written to (a probe write), and
/// whether the volume has enough free space. Ownership is intentionally *not*
/// checked — the bottle prefix is a freshly created subdirectory owned by the
/// current user regardless of the parent's owner, so the probe write is the
/// accurate predictor of whether creation will succeed.
public enum BottleLocationValidation {
    /// The outcome of validating a prospective bottle location.
    public enum ValidationResult: Equatable, Sendable {
        /// The location is usable.
        case valid
        /// Neither the location nor its nearest existing parent can be written to.
        case notWritable(path: String)
        /// The volume does not have enough free space to create a bottle.
        case insufficientSpace(availableBytes: Int64, requiredBytes: Int64)
    }

    /// Minimum free space required to create a bottle. A bare prefix is well
    /// under 1 GiB; the floor leaves headroom and refuses near-full disks where
    /// prefix initialization would otherwise fail partway.
    public static let minimumFreeBytes: Int64 = 2 << 30 // 2 GiB

    /// Validates a prospective bottle parent directory.
    ///
    /// - Parameters:
    ///   - url: The parent directory the user chose (the bottle itself is a
    ///     not-yet-created subdirectory of this).
    ///   - minimumFreeBytes: The free-space floor to require. Injectable for tests.
    ///   - fileManager: The file manager to probe with. Injectable for tests.
    /// - Returns: ``ValidationResult/valid`` if the location is usable, otherwise
    ///   the specific reason it is not.
    public static func validate(
        at url: URL,
        minimumFreeBytes: Int64 = BottleLocationValidation.minimumFreeBytes,
        fileManager: FileManager = .default
    ) -> ValidationResult {
        let ancestor = nearestExistingDirectory(for: url, fileManager: fileManager)

        guard isWritable(ancestor, fileManager: fileManager) else {
            return .notWritable(path: url.path(percentEncoded: false))
        }

        // Skip the space check (fail open) if capacity can't be read, rather
        // than blocking creation over an unreadable volume.
        if let available = availableCapacity(at: ancestor), available < minimumFreeBytes {
            return .insufficientSpace(availableBytes: available, requiredBytes: minimumFreeBytes)
        }

        return .valid
    }

    /// Walks up from `url` to the first existing directory, so writability and
    /// capacity can be probed even when the chosen path does not exist yet.
    static func nearestExistingDirectory(for url: URL, fileManager: FileManager) -> URL {
        var candidate = url.resolvingSymlinksInPath()
        while !fileManager.fileExists(atPath: candidate.path(percentEncoded: false)) {
            let parent = candidate.deletingLastPathComponent()
            // `deletingLastPathComponent()` on "/" returns "/"; stop at the root
            // rather than looping forever.
            if parent.path(percentEncoded: false) == candidate.path(percentEncoded: false) {
                break
            }
            candidate = parent
        }
        return candidate
    }

    /// Probes writability by creating and removing a unique temp file.
    ///
    /// `FileManager.isWritableFile(atPath:)` and the `isWritable` resource key
    /// are documented as unreliable on modern macOS, so an attempt-and-clean
    /// probe is used instead.
    private static func isWritable(_ directory: URL, fileManager: FileManager) -> Bool {
        let probe = directory.appendingPathComponent(".whisky-write-probe-\(UUID().uuidString)")
        guard fileManager.createFile(atPath: probe.path(percentEncoded: false), contents: nil) else {
            return false
        }
        try? fileManager.removeItem(at: probe)
        return true
    }

    /// Reads available capacity, preferring the "important usage" figure (which
    /// counts purgeable space, so it errs optimistic and won't false-positive).
    private static func availableCapacity(at directory: URL) -> Int64? {
        let keys: Set<URLResourceKey> = [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]
        guard let values = try? directory.resourceValues(forKeys: keys) else { return nil }
        if let important = values.volumeAvailableCapacityForImportantUsage { return important }
        if let basic = values.volumeAvailableCapacity { return Int64(basic) }
        return nil
    }
}
