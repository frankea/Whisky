//
//  Redactor.swift
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

/// Composable redaction pipeline for privacy-safe diagnostic exports.
///
/// Scrubs home directory paths and filters sensitive environment variable
/// keys before content is included in diagnostic reports or clipboard copies.
/// Follows the ``GPUDetection`` caseless-enum pattern.
///
/// ## Redaction Rules
///
/// - Home paths (`/Users/<username>`) are replaced with `/Users/<redacted>`
/// - Environment variable keys matching ``sensitiveKeyPatterns`` are removed
///   unless explicitly included
public enum Redactor {
    /// Substrings that identify sensitive environment variable keys.
    ///
    /// Keys whose uppercased form contains any of these substrings
    /// are removed during environment redaction.
    public static let sensitiveKeyPatterns = ["TOKEN", "KEY", "SECRET", "PASSWORD", "AUTH"]

    /// Replaces the current user's home directory path with a redacted placeholder.
    ///
    /// Detects the actual home directory at runtime and replaces all occurrences
    /// of `/Users/<username>` with `/Users/<redacted>`.
    ///
    /// - Parameter text: The text to redact.
    /// - Returns: The text with home paths replaced.
    public static func redactHomePaths(_ text: String) -> String {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        // Remove trailing slash if present for consistent matching
        let normalizedHome = homePath.hasSuffix("/") ? String(homePath.dropLast()) : homePath
        guard !normalizedHome.isEmpty else { return text }
        return text.replacingOccurrences(of: normalizedHome, with: "/Users/<redacted>")
    }

    /// Redacts an environment variable dictionary for safe export.
    ///
    /// By default (when `includeSensitive` is `false`):
    /// - Home paths in values are replaced with `/Users/<redacted>`
    /// - Keys matching ``sensitiveKeyPatterns`` (case-insensitive contains) are removed
    ///
    /// When `includeSensitive` is `true`:
    /// - Home paths in values are still redacted
    /// - Sensitive keys are kept (not removed)
    ///
    /// - Parameters:
    ///   - env: The environment dictionary to redact.
    ///   - includeSensitive: When `true`, keeps sensitive keys. Defaults to `false`.
    /// - Returns: The redacted environment dictionary.
    public static func redactEnvironment(
        _ env: [String: String],
        includeSensitive: Bool = false
    ) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in env {
            if !includeSensitive, isSensitiveKey(key) {
                continue
            }
            result[key] = redactHomePaths(value)
        }
        return result
    }

    /// Redacts home directory paths throughout log text.
    ///
    /// - Parameter text: The log text to redact.
    /// - Returns: The text with all home paths replaced.
    public static func redactLogText(_ text: String) -> String {
        redactHomePaths(text)
    }

    // MARK: - Private

    /// Checks whether an environment variable key matches any sensitive pattern.
    private static func isSensitiveKey(_ key: String) -> Bool {
        let upper = key.uppercased()
        return sensitiveKeyPatterns.contains { upper.contains($0) }
    }
}
