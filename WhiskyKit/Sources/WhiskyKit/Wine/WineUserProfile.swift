//
//  WineUserProfile.swift
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

private let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "WineUserProfile")

/// Keeps a bottle's user profile reachable under both names Wine builds use for it.
///
/// Every Wine build names the profile directory after the Unix user, so a bottle
/// created on the stock engine has `drive_c/users/<name>`. CrossOver-lineage
/// builds carry a shell32 hack that expands `%USERPROFILE%` to `C:\users\crossover`
/// regardless of the user, so the same bottle opened on one of those runtimes
/// gets a fresh, empty `users/crossover`, and every app in it starts from
/// nothing: Steam asks for a login, saves are gone, nothing errors. The name is
/// a compile-time constant in that build, so no environment variable steers it.
///
/// The fix is on disk: before a launch, whichever of the two names is missing
/// becomes a symlink to the one that holds the data. A directory is only ever
/// replaced when it is an untouched skeleton (directories and temp files, no
/// user data), and it is moved aside rather than deleted. Two populated
/// profiles are left alone, because merging them is a decision for a person.
public enum WineUserProfile {
    /// The profile name CrossOver-lineage builds hardcode.
    public static let crossOverName = "crossover"

    /// Where a displaced skeleton goes, relative to the bottle root. Outside
    /// `drive_c/users` so Wine and ``WinePrefixValidation/detectWineUsername(in:)``
    /// never see it as a profile.
    static let displacedDirectoryName = ".profile-reconcile"

    /// What a reconcile pass did.
    public enum Outcome: Equatable, Sendable {
        /// No users directory, or no profile under either name yet.
        case nothingToReconcile
        /// Both names already resolve, or one of them is already a symlink.
        case alreadyConsistent
        /// `name` was missing and is now a symlink to `target`.
        case linked(name: String, target: String)
        /// `name` was an empty skeleton; it was moved to `movedTo` and replaced by a symlink to `target`.
        case replacedSkeleton(name: String, target: String, movedTo: URL)
        /// Both names hold user data; nothing was touched.
        case bothPopulated
        /// A filesystem operation failed; the profile is as it was.
        case failed(String)
    }

    private enum Entry {
        case absent
        case symlink
        case directory
        case other
    }

    /// Makes the profile reachable under both the Unix user's name and `crossover`.
    ///
    /// Safe to call before every launch: the common case is a handful of stat calls.
    ///
    /// - Parameters:
    ///   - bottleURL: The bottle (Wine prefix) root.
    ///   - unixUserName: The name Wine derives from the Unix user; injectable for tests.
    /// - Returns: What was done, for logging and tests.
    @discardableResult
    public static func reconcile(bottleURL: URL, unixUserName: String = NSUserName()) -> Outcome {
        guard unixUserName != crossOverName else { return .alreadyConsistent }
        let usersDir = bottleURL.appending(path: "drive_c/users")
        guard classify(usersDir) == .directory else { return .nothingToReconcile }

        let unixDir = usersDir.appending(path: unixUserName)
        let crossOverDir = usersDir.appending(path: crossOverName)
        let unix = classify(unixDir)
        let crossOver = classify(crossOverDir)

        switch (unix, crossOver) {
        case (.absent, .absent):
            return .nothingToReconcile
        case (.symlink, _), (_, .symlink):
            return .alreadyConsistent
        case (.directory, .absent):
            return link(crossOverDir, to: unixUserName)
        case (.absent, .directory):
            return link(unixDir, to: crossOverName)
        case (.directory, .directory):
            return reconcilePair(
                unix: unixDir, crossOver: crossOverDir, unixUserName: unixUserName, bottleURL: bottleURL
            )
        default:
            return .alreadyConsistent
        }
    }

    // MARK: - Steps

    private static func reconcilePair(
        unix unixDir: URL, crossOver crossOverDir: URL, unixUserName: String, bottleURL: URL
    ) -> Outcome {
        let unixPopulated = hasUserData(unixDir)
        let crossOverPopulated = hasUserData(crossOverDir)

        switch (unixPopulated, crossOverPopulated) {
        case (true, true):
            return .bothPopulated
        case (false, true):
            // The stock-name directory is the empty one: a crossover-lineage
            // bottle opened once on the stock engine.
            return replaceSkeleton(unixDir, with: crossOverName, bottleURL: bottleURL)
        default:
            // Either the crossover directory is the empty one, or both are and
            // the Unix name is the better one to keep.
            return replaceSkeleton(crossOverDir, with: unixUserName, bottleURL: bottleURL)
        }
    }

    private static func link(_ url: URL, to target: String) -> Outcome {
        do {
            try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: target)
            logger.info("Linked profile \(url.lastPathComponent, privacy: .public) to \(target, privacy: .public)")
            return .linked(name: url.lastPathComponent, target: target)
        } catch {
            logger.error("Could not link profile \(url.path, privacy: .public): \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }

    private static func replaceSkeleton(_ url: URL, with target: String, bottleURL: URL) -> Outcome {
        let fileManager = FileManager.default
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let parking = bottleURL.appending(path: displacedDirectoryName)
        let movedTo = parking.appending(path: "\(url.lastPathComponent)-\(stamp)")
        do {
            try fileManager.createDirectory(at: parking, withIntermediateDirectories: true)
            try fileManager.moveItem(at: url, to: movedTo)
        } catch {
            logger.error("Could not move skeleton \(url.path, privacy: .public): \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
        guard case let .linked(name, target) = link(url, to: target) else {
            // Put the skeleton back so the prefix is exactly as it was.
            try? fileManager.moveItem(at: movedTo, to: url)
            return .failed("Could not replace \(url.lastPathComponent) with a link")
        }
        return .replacedSkeleton(name: name, target: target, movedTo: movedTo)
    }

    // MARK: - Inspection

    private static func classify(_ url: URL) -> Entry {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let type = attributes[.type] as? FileAttributeType
        else { return .absent }
        switch type {
        case .typeSymbolicLink: return .symlink
        case .typeDirectory: return .directory
        default: return .other
        }
    }

    /// True if the profile holds anything an app wrote: a regular file outside
    /// a `Temp` directory. A freshly booted profile is directories only, and
    /// what lands in `Temp` is scratch by definition.
    static func hasUserData(_ profile: URL) -> Bool {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: profile,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        else { return false }

        for case let item as URL in enumerator {
            let components = item.pathComponents.dropFirst(profile.pathComponents.count)
            if components.contains("Temp") {
                enumerator.skipDescendants()
                continue
            }
            if (try? item.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                return true
            }
        }
        return false
    }
}
