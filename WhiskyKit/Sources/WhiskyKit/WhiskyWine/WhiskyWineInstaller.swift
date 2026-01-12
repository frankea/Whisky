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
    ///   The tarball is deleted after successful extraction.
    ///
    /// - Important: Ensure the tarball is from a trusted source.
    public static func install(from: URL) {
        do {
            if !FileManager.default.fileExists(atPath: applicationFolder.path) {
                try FileManager.default.createDirectory(at: applicationFolder, withIntermediateDirectories: true)
            } else {
                // Recreate it
                try FileManager.default.removeItem(at: applicationFolder)
                try FileManager.default.createDirectory(at: applicationFolder, withIntermediateDirectories: true)
            }

            try Tar.untar(tarBall: from, toURL: applicationFolder)
            try FileManager.default.removeItem(at: from)
        } catch {
            logger.error("Failed to install WhiskyWine: \(error.localizedDescription)")
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
        do {
            let versionPlist = libraryFolder
                .appending(path: "WhiskyWineVersion")
                .appendingPathExtension("plist")

            let decoder = PropertyListDecoder()
            let data = try Data(contentsOf: versionPlist)
            let info = try decoder.decode(WhiskyWineVersion.self, from: data)
            return info.version
        } catch {
            logger.debug("WhiskyWine version not found: \(error.localizedDescription)")
            return nil
        }
    }
}
