//
//  StalenessChecker.swift
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

/// Reasons why a game database entry may be considered stale.
///
/// Multiple reasons can apply simultaneously (e.g., both date-expired
/// and macOS version mismatch).
public enum StalenessReason: String, Sendable, Equatable {
    /// The entry was last tested more than 90 days ago.
    case dateExpired
    /// The user's macOS version is newer than the tested version by more than 1 minor release.
    case macOSVersionMismatch
    /// The user's Wine major version differs from the tested version.
    case wineVersionMismatch
}

/// The result of checking a game database entry for staleness.
///
/// Contains whether the entry is stale, the specific reasons, and a
/// user-friendly warning message suitable for display in a banner.
public struct StalenessResult: Sendable, Equatable {
    /// Whether the entry is considered stale.
    public let isStale: Bool
    /// The specific reasons for staleness (empty if not stale).
    public let reasons: [StalenessReason]
    /// A user-friendly warning message combining all reasons, or `nil` if not stale.
    public let warningMessage: String?

    public init(isStale: Bool, reasons: [StalenessReason], warningMessage: String?) {
        self.isStale = isStale
        self.reasons = reasons
        self.warningMessage = warningMessage
    }
}

/// Detects stale game database entries by comparing tested conditions against current environment.
///
/// Staleness is determined by three factors:
/// - **Date**: Entry tested more than 90 days ago
/// - **macOS version**: User's macOS is newer by more than 1 minor release
/// - **Wine version**: Wine major version differs from tested version
///
/// Stale entries show a warning but are not blocked from being applied.
///
/// ## Usage
///
/// ```swift
/// let result = StalenessChecker.check(
///     testedWith: variant.testedWith!,
///     currentMacOSVersion: "15.3.0",
///     currentWineVersion: "10.0"
/// )
/// if result.isStale {
///     showWarningBanner(result.warningMessage!)
/// }
/// ```
public enum StalenessChecker {
    /// The number of days after which an entry is considered date-stale.
    private static let stalenessThresholdDays: Double = 90

    /// Checks whether a game configuration entry is stale.
    ///
    /// - Parameters:
    ///   - testedWith: The ``TestedWith`` metadata from the entry/variant.
    ///   - currentMacOSVersion: The current macOS version string (e.g., "15.3.0").
    ///     Defaults to the system's current version from ProcessInfo.
    ///   - currentWineVersion: The current Wine version string (e.g., "10.0").
    ///     If `nil`, Wine version staleness is not checked.
    /// - Returns: A ``StalenessResult`` indicating whether the entry is stale and why.
    public static func check(
        testedWith: TestedWith,
        currentMacOSVersion: String? = nil,
        currentWineVersion: String? = nil
    ) -> StalenessResult {
        var reasons: [StalenessReason] = []
        var messageParts: [String] = []

        // 1. Date staleness: >90 days since last tested
        let daysSinceTested = Date().timeIntervalSince(testedWith.lastTestedAt) / 86_400
        if daysSinceTested > stalenessThresholdDays {
            reasons.append(.dateExpired)
            let days = Int(daysSinceTested)
            messageParts.append("last tested \(days) days ago")
        }

        // 2. macOS version mismatch: user's macOS newer by >1 minor release
        let macOSVersion = currentMacOSVersion ?? currentSystemMacOSVersion()
        if isMacOSVersionStale(tested: testedWith.macOSVersion, current: macOSVersion) {
            reasons.append(.macOSVersionMismatch)
            messageParts.append("on macOS \(testedWith.macOSVersion)")
        }

        // 3. Wine version mismatch: major version differs
        if let currentWine = currentWineVersion,
           isWineVersionStale(tested: testedWith.wineVersion, current: currentWine) {
            reasons.append(.wineVersionMismatch)
            messageParts.append("with Wine \(testedWith.wineVersion)")
        }

        let isStale = !reasons.isEmpty
        let warningMessage: String? = if isStale {
            "This config was \(messageParts.joined(separator: ", "))."
        } else {
            nil
        }

        return StalenessResult(
            isStale: isStale,
            reasons: reasons,
            warningMessage: warningMessage
        )
    }

    // MARK: - Version Comparison Helpers

    /// A parsed semantic version with major, minor, and patch components.
    private struct ParsedVersion {
        let major: Int
        let minor: Int
    }

    /// Parses a version string like "15.3.0" into major and minor components.
    ///
    /// Returns `nil` if the string cannot be parsed.
    private static func parseVersion(_ version: String) -> ParsedVersion? {
        let components = version.split(separator: ".").compactMap { Int($0) }
        guard components.count >= 2 else { return nil }
        return ParsedVersion(major: components[0], minor: components[1])
    }

    /// Checks if the macOS version indicates staleness.
    ///
    /// Stale when user's macOS is newer by >1 minor release (same major) or
    /// when the major version differs.
    private static func isMacOSVersionStale(tested: String, current: String) -> Bool {
        guard let testedVer = parseVersion(tested),
              let currentVer = parseVersion(current)
        else {
            return false
        }

        // Different major version -> stale
        if currentVer.major != testedVer.major {
            return currentVer.major > testedVer.major
        }

        // Same major, check minor version delta >1
        let minorDelta = currentVer.minor - testedVer.minor
        return minorDelta > 1
    }

    /// Checks if the Wine version indicates staleness.
    ///
    /// Stale when Wine major version differs.
    private static func isWineVersionStale(tested: String, current: String) -> Bool {
        guard let testedMajor = parseMajorVersion(tested),
              let currentMajor = parseMajorVersion(current)
        else {
            return false
        }
        return testedMajor != currentMajor
    }

    /// Extracts the major version number from a Wine version string.
    ///
    /// Handles formats like "10.0", "9.21", "10".
    private static func parseMajorVersion(_ version: String) -> Int? {
        let components = version.split(separator: ".")
        guard let first = components.first else { return nil }
        return Int(first)
    }

    /// Returns the current macOS version as a string (e.g., "15.3.0").
    private static func currentSystemMacOSVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}
