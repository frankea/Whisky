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
        /// A mounted, consent-gated volume refused the write with a permission
        /// error, which is what a withheld Files and Folders grant looks like.
        /// Distinct from ``notWritable`` because it is the only case System
        /// Settings can fix.
        case accessDenied(path: String)
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
        let path = url.path(percentEncoded: false)

        switch probeWrite(in: ancestor, fileManager: fileManager) {
        case .succeeded:
            break
        case .denied:
            // Only a consent-gated volume can be blocked by a withheld grant. A
            // locked folder on the internal disk is the same errno with a
            // different fix, and sending that to the privacy pane wastes a trip.
            return isConsentGatedVolume(ancestor) ? .accessDenied(path: path) : .notWritable(path: path)
        case .failed:
            return .notWritable(path: path)
        }

        // Skip the space check (fail open) if capacity can't be read, rather
        // than blocking creation over an unreadable volume.
        if let available = availableCapacity(at: ancestor), available < minimumFreeBytes {
            return .insufficientSpace(availableBytes: available, requiredBytes: minimumFreeBytes)
        }

        return .valid
    }

    /// Walks up from `url` to the first existing path, so writability and
    /// capacity can be probed even when the chosen path does not exist yet.
    ///
    /// The first existing path may be a regular file (a malformed location); the
    /// caller's write probe then fails and yields `.notWritable` rather than
    /// silently validating the file's parent.
    static func nearestExistingDirectory(for url: URL, fileManager: FileManager) -> URL {
        var candidate = url.resolvingSymlinksInPath()
        while !exists(candidate, fileManager: fileManager) {
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

    /// `fileExists(atPath:)` with a trailing slash returns `false` for a regular
    /// file, and `deletingLastPathComponent()` introduces trailing slashes — so
    /// strip them before testing existence to detect file components correctly.
    private static func exists(_ url: URL, fileManager: FileManager) -> Bool {
        var path = url.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return fileManager.fileExists(atPath: path)
    }

    /// Why a write probe did not succeed, kept apart so a refusal can be told
    /// from a location that is unusable for some other reason.
    enum WriteProbe: Equatable {
        case succeeded
        /// Refused with a permission error.
        case denied
        /// Failed for any other reason, a read-only volume among them.
        case failed
    }

    /// Probes writability by creating and removing a unique temp file, and on a
    /// consent-gated volume this is also what makes macOS ask: the prompt fires
    /// on a real access, and there is no status API to consult instead.
    ///
    /// `FileManager.isWritableFile(atPath:)` and the `isWritable` resource key
    /// are documented as unreliable on modern macOS, so an attempt-and-clean
    /// probe is used instead. It writes through `Data` rather than
    /// `createFile(atPath:contents:)` because only the throwing form reports
    /// *why* it failed.
    static func probeWrite(in directory: URL, fileManager: FileManager) -> WriteProbe {
        let probe = directory.appendingPathComponent(".whisky-write-probe-\(UUID().uuidString)")
        do {
            try Data().write(to: probe, options: .atomic)
            try? fileManager.removeItem(at: probe)
            return .succeeded
        } catch {
            let nsError = error as NSError
            let underlying = nsError.underlyingErrors.map { ($0 as NSError).code }
            let denied = nsError.code == NSFileWriteNoPermissionError
                || underlying.contains(Int(EPERM)) || underlying.contains(Int(EACCES))
            return denied ? .denied : .failed
        }
    }

    /// Whether macOS gates this location behind Files and Folders consent.
    ///
    /// Whisky is not sandboxed, so choosing the folder in an open panel grants
    /// nothing by itself.
    public static func isConsentGatedVolume(_ url: URL) -> Bool {
        guard let volume = try? url.resourceValues(forKeys: [.volumeURLKey]).volume,
              let values = try? volume.resourceValues(forKeys: [.volumeIsInternalKey, .volumeIsLocalKey])
        else { return false }
        // `volumeIsInternal` is nil, not false, on volumes macOS cannot place on a
        // bus: disk images and some enclosures report that way. Comparing it to
        // false therefore classified exactly the gated volumes as internal, so
        // nothing was ever reported as a consent problem. Only a definite true
        // rules a volume out.
        if values.volumeIsLocal == false { return true }
        return values.volumeIsInternal != true
    }

    /// Reads available capacity, preferring the "important usage" figure (which
    /// counts purgeable space, so it errs optimistic and won't false-positive).
    /// However, that sometimes doesn't work on removable drives, so we fall
    /// back to normal figure.
    private static func availableCapacity(at directory: URL) -> Int64? {
        let isExternalOrCustom: Bool = {
            guard let values = try? directory.resourceValues(forKeys: [.volumeIsInternalKey]) else { return false }
            // nil, not false, on the removable volumes this exists for.
            return values.volumeIsInternal != true
        }()

        if isExternalOrCustom {
            if let values = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
               let basic = values.volumeAvailableCapacity {
                return Int64(basic)
            }
            return nil
        }

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
