//
//  WinePrefixValidation.swift
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

private let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "WinePrefixValidation")

/// Provides validation utilities for Wine prefix health.
///
/// This enum contains static methods to validate that a Wine prefix has properly
/// initialized user profile directories, which are required for winetricks and
/// other dependency installations to function correctly.
///
/// ## Overview
///
/// Many Windows dependencies (dotnet, DirectX, vcruntime) require `%AppData%` and
/// other user profile environment variables to resolve correctly. When a Wine prefix
/// is incompletely initialized, these variables may be empty, causing installations to fail.
///
/// ## Usage
///
/// ```swift
/// let result = await WinePrefixValidation.validatePrefix(for: bottle)
/// switch result {
/// case .valid:
///     // Proceed with winetricks
/// case .missingAppData(let diagnostics):
///     // Show error with diagnostics
/// }
/// ```
public enum WinePrefixValidation {
    /// The result of validating a Wine prefix.
    public enum ValidationResult: Sendable {
        /// The prefix is valid and has all required user directories.
        case valid

        /// The user profile directory is missing.
        case missingUserProfile(diagnostics: WinePrefixDiagnostics)

        /// The AppData directory or its subdirectories are missing.
        case missingAppData(diagnostics: WinePrefixDiagnostics)

        /// The prefix is corrupted or missing essential directories.
        case corruptedPrefix(diagnostics: WinePrefixDiagnostics)

        /// Returns the diagnostics if validation failed, nil if valid.
        public var diagnostics: WinePrefixDiagnostics? {
            switch self {
            case .valid:
                nil
            case let .missingUserProfile(diag), let .missingAppData(diag), let .corruptedPrefix(diag):
                diag
            }
        }

        /// Returns true if the prefix is valid.
        public var isValid: Bool {
            if case .valid = self { return true }
            return false
        }
    }

    /// Validates that a Wine prefix has properly initialized user directories.
    ///
    /// This method checks for the presence of essential directories that Wine creates
    /// during prefix initialization. If any are missing, dependency installations may fail.
    ///
    /// - Parameter bottle: The bottle to validate.
    /// - Returns: A validation result indicating whether the prefix is valid or what is missing.
    @MainActor
    public static func validatePrefix(for bottle: Bottle) -> ValidationResult {
        var diagnostics = WinePrefixDiagnostics()
        diagnostics.prefixPath = bottle.url.path
        diagnostics.record("Starting prefix validation")

        let fileManager = FileManager.default

        // Check prefix exists
        diagnostics.prefixExists = fileManager.fileExists(atPath: bottle.url.path)
        if !diagnostics.prefixExists {
            diagnostics.record("Prefix directory does not exist")
            return .corruptedPrefix(diagnostics: diagnostics)
        }

        // Check drive_c exists
        let driveC = bottle.url.appending(path: "drive_c")
        diagnostics.driveCExists = fileManager.fileExists(atPath: driveC.path)
        if !diagnostics.driveCExists {
            diagnostics.record("drive_c directory does not exist")
            return .corruptedPrefix(diagnostics: diagnostics)
        }

        // Check users directory exists
        let usersDir = driveC.appending(path: "users")
        diagnostics.usersDirectoryExists = fileManager.fileExists(atPath: usersDir.path)
        if !diagnostics.usersDirectoryExists {
            diagnostics.record("users directory does not exist")
            return .corruptedPrefix(diagnostics: diagnostics)
        }

        // Detect Wine username
        guard let username = detectWineUsername(in: usersDir) else {
            diagnostics.record("Could not detect Wine username in users directory")
            return .missingUserProfile(diagnostics: diagnostics)
        }
        diagnostics.detectedUsername = username
        diagnostics.record("Detected Wine username: \(username)")

        // Check user profile directories
        let userProfile = usersDir.appending(path: username)
        diagnostics.userProfileExists = fileManager.fileExists(atPath: userProfile.path)
        if !diagnostics.userProfileExists {
            diagnostics.record("User profile directory does not exist: \(userProfile.path)")
            return .missingUserProfile(diagnostics: diagnostics)
        }

        let appData = userProfile.appending(path: "AppData")
        diagnostics.appDataExists = fileManager.fileExists(atPath: appData.path)

        let roaming = appData.appending(path: "Roaming")
        diagnostics.roamingExists = fileManager.fileExists(atPath: roaming.path)

        let local = appData.appending(path: "Local")
        diagnostics.localAppDataExists = fileManager.fileExists(atPath: local.path)

        // Check if AppData structure is complete
        if !diagnostics.appDataExists || !diagnostics.roamingExists || !diagnostics.localAppDataExists {
            diagnostics.record("AppData directory structure incomplete")
            diagnostics.record("  AppData: \(diagnostics.appDataExists)")
            diagnostics.record("  Roaming: \(diagnostics.roamingExists)")
            diagnostics.record("  Local: \(diagnostics.localAppDataExists)")
            return .missingAppData(diagnostics: diagnostics)
        }

        diagnostics.record("Prefix validation passed")
        logger.debug("Prefix validation passed for bottle at \(bottle.url.path)")
        return .valid
    }

    /// Detects the Wine username by scanning the users directory.
    ///
    /// Wine creates user profile directories in `drive_c/users/`. This method scans
    /// that directory to find the actual username, skipping system directories.
    ///
    /// - Parameter usersDir: The URL to the users directory within the Wine prefix.
    /// - Returns: The detected username, or nil if none found.
    public static func detectWineUsername(in usersDir: URL) -> String? {
        let fileManager = FileManager.default

        guard let entries = try? fileManager.contentsOfDirectory(
            at: usersDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        else {
            logger.debug("Could not list users directory: \(usersDir.path)")
            return nil
        }

        // Filter to only directories and skip system directories
        let systemDirs: Set<String> = ["Public"]
        let userDirs = entries.filter { entry in
            let name = entry.lastPathComponent
            guard !systemDirs.contains(name) else { return false }

            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: entry.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }

        // Sort deterministically by directory name so selection is not filesystem-order dependent
        let sortedUserDirs = userDirs.sorted {
            $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
        }

        // Prefer non-"crossover" username if available (for compatibility with different Wine builds)
        if let preferred = sortedUserDirs.first(where: { $0.lastPathComponent != "crossover" }) {
            return preferred.lastPathComponent
        }

        // Fall back to crossover or first available (deterministically chosen)
        return sortedUserDirs.first?.lastPathComponent
    }
}
