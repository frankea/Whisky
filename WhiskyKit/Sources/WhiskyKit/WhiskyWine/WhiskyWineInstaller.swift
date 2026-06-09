//
//  WhiskyWineInstaller.swift
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

import CryptoKit
import Foundation
import os
import SemanticVersion

private let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "WhiskyWineInstaller")

/// Manages the installation and updates of the WhiskyWine runtime.
///
/// `WhiskyWineInstaller` handles downloading, installing, and managing the
/// Wine runtime that Whisky uses to run Windows applications. It provides
/// version checking, update detection, and installation/uninstallation.
///
/// ## Overview
///
/// WhiskyWine is a custom Wine build bundled with Whisky. This class manages
/// its lifecycle within the application's Library directory.
///
/// ## Checking Installation Status
///
/// ```swift
/// if WhiskyWineInstaller.isWhiskyWineInstalled() {
///     if let version = WhiskyWineInstaller.whiskyWineVersion() {
///         print("WhiskyWine version: \(version)")
///     }
/// } else {
///     // Prompt user to install
/// }
/// ```
///
/// ## Installing WhiskyWine
///
/// ```swift
/// // After downloading the tarball
/// WhiskyWineInstaller.install(from: downloadedTarballURL)
/// ```
///
/// ## Topics
///
/// ### File Locations
/// - ``applicationFolder``
/// - ``libraryFolder``
/// - ``binFolder``
///
/// ### Installation Status
/// - ``isWhiskyWineInstalled()``
/// - ``whiskyWineVersion()``
///
/// ### Installation Management
/// - ``install(from:)``
/// - ``uninstall()``
/// - ``shouldUpdateWhiskyWine()``
public class WhiskyWineInstaller {
    /// The root application support folder for Whisky.
    ///
    /// Located at `~/Library/Application Support/{bundle-identifier}/`.
    public static let applicationFolder = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
    )[0].appending(path: Bundle.whiskyBundleIdentifier)

    /// The folder containing all library files including Wine and DXVK.
    ///
    /// Located at `~/Library/Application Support/{bundle-identifier}/Libraries/`.
    public static let libraryFolder = applicationFolder.appending(path: "Libraries")

    /// The URL to the Wine binary directory.
    ///
    /// This folder contains `wine64`, `wineserver`, and other Wine executables.
    public static let binFolder: URL = libraryFolder.appending(path: "Wine").appending(path: "bin")

    /// Checks whether WhiskyWine is currently installed.
    ///
    /// - Returns: `true` if WhiskyWine is installed and has a valid version file.
    public static func isWhiskyWineInstalled() -> Bool {
        whiskyWineVersion() != nil
    }

    /// Installs WhiskyWine from a downloaded tarball.
    ///
    /// This method extracts the WhiskyWine tarball to the application support
    /// directory. If WhiskyWine is already installed, it is replaced.
    ///
    /// - Parameter from: The URL to the downloaded tarball file.
    /// - Note: The tarball is NOT deleted after extraction. Call ``cleanupTarball(at:)``
    ///   after verifying installation success with ``isWhiskyWineInstalled()``.
    ///
    /// - Important: Ensure the tarball is from a trusted source.
    public static func install(from: URL) {
        do {
            // Verify tarball exists before modifying application folder.
            // This prevents data loss if the OS has cleaned up the temp file.
            guard FileManager.default.fileExists(atPath: from.path) else {
                logger.error("Tarball not found at \(from.path) - cannot install")
                return
            }

            if !FileManager.default.fileExists(atPath: applicationFolder.path) {
                try FileManager.default.createDirectory(at: applicationFolder, withIntermediateDirectories: true)
            } else {
                // Recreate it
                try FileManager.default.removeItem(at: applicationFolder)
                try FileManager.default.createDirectory(at: applicationFolder, withIntermediateDirectories: true)
            }

            try Tar.untar(tarBall: from, toURL: applicationFolder)
        } catch {
            logger.error("Failed to install WhiskyWine: \(error.localizedDescription)")
        }
    }

    /// Computes the SHA-256 of a file by streaming it in chunks.
    ///
    /// The archive can be several hundred megabytes, so the file is hashed
    /// incrementally rather than read fully into memory.
    ///
    /// - Parameter url: The file to hash.
    /// - Returns: The lowercase hex SHA-256 digest, or `nil` if the file cannot
    ///   be opened or read.
    public static func sha256(ofFileAt url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            logger.error("Cannot open \(url.path) to compute SHA-256")
            return nil
        }
        defer { try? handle.close() }

        var hasher = SHA256()
        let chunkSize = 1 << 20 // 1 MiB
        do {
            while true {
                // `read(upToCount:)` returns nil at EOF and may return an empty
                // (non-nil) Data on some streams; treat both as "no more bytes".
                guard let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty else {
                    break
                }
                hasher.update(data: chunk)
            }
        } catch {
            logger.error("Failed reading \(url.path) for SHA-256: \(error.localizedDescription)")
            return nil
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The outcome of checking a downloaded archive against an expected digest.
    public enum IntegrityResult: Equatable, Sendable {
        /// The file's digest matched the expected value.
        case match
        /// The file hashed successfully but did not match. Carries the actual
        /// lowercase-hex digest so callers can report it in diagnostics.
        case mismatch(actual: String)
        /// The file could not be read to compute a digest.
        case unreadable
    }

    /// Checks a file's SHA-256 against an expected hex digest.
    ///
    /// This is an integrity check — it confirms the downloaded archive is the
    /// exact bytes the runtime metadata advertised, catching truncated or
    /// corrupted downloads before install. It is not a substitute for the
    /// transport-level trust provided by HTTPS.
    ///
    /// - Parameters:
    ///   - url: The file to check.
    ///   - expected: The expected SHA-256 as a hex string (compared
    ///     case-insensitively).
    /// - Returns: ``IntegrityResult/match``, ``IntegrityResult/mismatch(actual:)``,
    ///   or ``IntegrityResult/unreadable``.
    public static func integrityResult(
        forFileAt url: URL,
        expectedSHA256 expected: String
    ) -> IntegrityResult {
        guard let actual = sha256(ofFileAt: url) else { return .unreadable }
        return actual.caseInsensitiveCompare(expected) == .orderedSame ? .match : .mismatch(actual: actual)
    }

    /// Removes the installation tarball after successful installation.
    ///
    /// Call this method only after ``isWhiskyWineInstalled()`` returns `true`
    /// to ensure the tarball is preserved for retry attempts if installation fails.
    ///
    /// - Parameter url: The URL to the tarball file to remove.
    public static func cleanupTarball(at url: URL) {
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            logger.warning("Failed to cleanup tarball: \(error.localizedDescription)")
        }
    }

    /// Removes the installed WhiskyWine runtime.
    ///
    /// This deletes the Libraries folder containing Wine and DXVK.
    /// Existing bottles are not affected, but they will not be able
    /// to run programs until WhiskyWine is reinstalled.
    public static func uninstall() {
        do {
            try FileManager.default.removeItem(at: libraryFolder)
        } catch {
            logger.error("Failed to uninstall WhiskyWine: \(error.localizedDescription)")
        }
    }

    /// Removes everything Whisky has stored under Application Support: the
    /// WhiskyWine runtime and every bottle whose plist registration lives in
    /// the default bottles list. Caller is responsible for confirming with
    /// the user — this is destructive and unrecoverable.
    ///
    /// Bottles stored at custom paths outside the default bottles directory
    /// are not removed; their tracking entries are dropped from the
    /// `BottleData` plist but the on-disk bottle directories are preserved
    /// to avoid surprising users who relocated bottles intentionally.
    public static func uninstallAll() {
        // Drop the runtime first so partial failures still leave a coherent state.
        uninstall()

        // Default bottles directory (matches `Bottle.defaultBottlesDirectory`).
        let defaultBottles = applicationFolder.appending(path: "Bottles")
        if FileManager.default.fileExists(atPath: defaultBottles.path(percentEncoded: false)) {
            do {
                try FileManager.default.removeItem(at: defaultBottles)
            } catch {
                logger.error("Failed to remove default bottles folder: \(error.localizedDescription)")
            }
        }

        // BottleData.plist registers bottle paths; remove it so a reinstall
        // starts with no orphaned entries pointing at deleted directories.
        let bottleData = applicationFolder.appending(path: "BottleData.plist")
        if FileManager.default.fileExists(atPath: bottleData.path(percentEncoded: false)) {
            try? FileManager.default.removeItem(at: bottleData)
        }
    }

    /// Checks if a newer version of WhiskyWine is available.
    ///
    /// This method compares the locally installed version against the
    /// remote version plist to determine if an update is available.
    ///
    /// - Returns: A tuple containing:
    ///   - A boolean indicating whether an update is available.
    ///   - The remote version if an update is available, or `0.0.0` otherwise.
    public static func shouldUpdateWhiskyWine() async -> (Bool, SemanticVersion) {
        let versionPlistURL = DistributionConfig.versionPlistURL
        let localVersion = whiskyWineVersion()

        var remoteVersion: SemanticVersion?

        if let remoteUrl = URL(string: versionPlistURL) {
            remoteVersion = await withCheckedContinuation { continuation in
                URLSession(configuration: .ephemeral).dataTask(with: URLRequest(url: remoteUrl)) { data, _, error in
                    do {
                        if error == nil, let data {
                            let decoder = PropertyListDecoder()
                            let remoteInfo = try decoder.decode(WhiskyWineVersion.self, from: data)
                            let remoteVersion = remoteInfo.version

                            continuation.resume(returning: remoteVersion)
                            return
                        }
                        if let error {
                            logger.warning("Failed to fetch remote version: \(error.localizedDescription)")
                        }
                    } catch {
                        logger.warning("Failed to decode remote version: \(error.localizedDescription)")
                    }

                    continuation.resume(returning: nil)
                }.resume()
            }
        }

        if let localVersion, let remoteVersion {
            if localVersion < remoteVersion {
                return (true, remoteVersion)
            }
        }

        return (false, SemanticVersion(0, 0, 0))
    }

    /// Returns the version of the installed WhiskyWine runtime.
    ///
    /// - Returns: The semantic version of the installed WhiskyWine,
    ///   or `nil` if WhiskyWine is not installed or the version
    ///   file cannot be read.
    public static func whiskyWineVersion() -> SemanticVersion? {
        whiskyWineInfo()?.version
    }

    /// The bundled DXVK (macOS) version recorded in the installed runtime's
    /// version plist, or `nil` if WhiskyWine is not installed or the plist does
    /// not record a DXVK version.
    public static func whiskyWineDXVKVersion() -> String? {
        whiskyWineInfo()?.dxvkVersion
    }

    /// Reads the full version record from the installed WhiskyWine runtime.
    ///
    /// - Returns: The decoded ``WhiskyWineVersion``, or `nil` if WhiskyWine is
    ///   not installed or the version file cannot be read.
    public static func whiskyWineInfo() -> WhiskyWineVersion? {
        let versionPlist = libraryFolder
            .appending(path: "WhiskyWineVersion")
            .appendingPathExtension("plist")
        return whiskyWineInfo(at: versionPlist)
    }

    /// Reads a WhiskyWine version record from a plist at an arbitrary URL.
    ///
    /// ``whiskyWineInfo()`` resolves the installed location; this overload reads
    /// any plist URL (also convenient for tests).
    ///
    /// - Parameter url: The location of a `WhiskyWineVersion.plist` file.
    /// - Returns: The decoded record, or `nil` if it is missing or malformed.
    public static func whiskyWineInfo(at url: URL) -> WhiskyWineVersion? {
        do {
            let decoder = PropertyListDecoder()
            let data = try Data(contentsOf: url)
            return try decoder.decode(WhiskyWineVersion.self, from: data)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // Expected when WhiskyWine simply isn't installed yet.
            logger.debug("WhiskyWine version plist absent: \(error.localizedDescription)")
            return nil
        } catch {
            // Present but unreadable/undecodable — likely a corrupt install.
            logger.error("WhiskyWine version plist unreadable, likely corrupt: \(error.localizedDescription)")
            return nil
        }
    }
}
