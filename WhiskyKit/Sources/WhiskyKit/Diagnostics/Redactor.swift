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
/// - Wine profile paths (`C:\users\<name>`, `drive_c/users/<name>`) lose the
///   account name, except the shared `crossover`, `Public` and `Shared` profiles
/// - Environment variable keys matching ``sensitiveKeyPatterns`` are removed
///   unless explicitly included
/// - Free text (launch arguments, log lines) has common secret shapes scrubbed
///   by ``redactSecrets(_:)``: `token=...` and `--password ...` forms,
///   `Bearer`/`Basic` credentials, URL user info, sensitive query parameters,
///   and JWTs. Best effort by nature; a secret with no recognizable shape
///   passes through, which is why the export UI says so.
public enum Redactor {
    /// Substrings that identify sensitive environment variable keys.
    ///
    /// Keys whose uppercased form contains any of these substrings
    /// are removed during environment redaction.
    public static let sensitiveKeyPatterns = ["TOKEN", "KEY", "SECRET", "PASSWORD", "AUTH"]

    /// Replaces user-profile paths with a redacted placeholder.
    ///
    /// Detects the actual home directory at runtime and replaces all occurrences
    /// of it with `/Users/<redacted>`. Wine logs also name the account inside
    /// the bottle, so `C:\users\<name>` (any drive letter, either slash) and
    /// `drive_c/users/<name>` lose the name too. The shared profiles
    /// (`crossover`, `Public`, `Shared`) carry no personal data and stay
    /// visible, so a support log still shows which profile was in use.
    ///
    /// - Parameter text: The text to redact.
    /// - Returns: The text with home paths replaced.
    public static func redactHomePaths(_ text: String) -> String {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        // Remove trailing slash if present for consistent matching
        let normalizedHome = homePath.hasSuffix("/") ? String(homePath.dropLast()) : homePath
        var result = text
        if !normalizedHome.isEmpty {
            result = result.replacingOccurrences(of: normalizedHome, with: "/Users/<redacted>")
        }
        for pattern in profilePathPatterns {
            result = result.replacingOccurrences(
                of: pattern, with: "$1<redacted>", options: [.regularExpression, .caseInsensitive]
            )
        }
        return result
    }

    /// Keeps the profiles that are the same on every machine readable. The name
    /// has to end there, so `Publicity` is still redacted.
    private static let sharedProfileLookahead = #"(?!(?:crossover|public|shared)(?:[\\/\s"'<>;,:)\]|]|$))"#

    /// One path component: anything up to a separator, whitespace, quote, angle
    /// bracket, or the punctuation that ends a path in a list or parentheses.
    /// Windows does not allow `; , : ] |` in an account name, and a `)` there
    /// almost always closes a parenthesised path.
    private static let profileName = #"[^\\/\s"'<>;,:)\]|]+"#

    /// Windows-side profile paths that Wine prints in its logs.
    private static let profilePathPatterns: [String] = [
        // C:\users\name, Z:/Users/name
        #"\b([a-z]:[\\/]+users[\\/]+)"# + sharedProfileLookahead + profileName,
        // .../drive_c/users/name
        #"(drive_c[\\/]+users[\\/]+)"# + sharedProfileLookahead + profileName
    ]

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

    /// Redacts home directory paths and common secret shapes throughout free
    /// text such as a log or a launch argument string.
    ///
    /// - Parameter text: The text to redact.
    /// - Returns: The text with home paths and recognizable secrets replaced.
    public static func redactLogText(_ text: String) -> String {
        redactSecrets(redactHomePaths(text))
    }

    /// Replaces the value of anything that looks like a credential with
    /// `<redacted>`, leaving the key or flag in place so the line still reads.
    ///
    /// Shapes covered, in order:
    /// 1. `name=value` and `name: value` where the name ends in a sensitive
    ///    word (token, secret, password, passwd, pwd, pass, auth, credential,
    ///    api key, access key, private key, key)
    /// 2. `--name value` and `-name value` flags with the same names
    /// 3. `Bearer <token>` and `Basic <base64>`
    /// 4. `scheme://user:pass@host` user info
    /// 5. `?name=value` query parameters with the same names, plus `sig`
    /// 6. JWTs (three base64url segments starting with `eyJ`)
    ///
    /// Prose is deliberately not matched: "auth failed" has no separator, so
    /// it stays. A key whose name merely contains a sensitive word
    /// ("keyboard") is not a match either; the word has to end the name.
    public static func redactSecrets(_ text: String) -> String {
        var result = text
        for (pattern, template) in secretPatterns {
            result = result.replacingOccurrences(
                of: pattern, with: template, options: [.regularExpression, .caseInsensitive]
            )
        }
        return result
    }

    private static let sensitiveWord =
        "(?:token|secret|password|passwd|pwd|pass|auth|credential|api[_-]?key|access[_-]?key|private[_-]?key|key)"

    /// Regex and replacement template pairs, applied in order.
    private static let secretPatterns: [(String, String)] = [
        // 1. name=value, name: value, name := value; the value runs to whitespace or a quote.
        ("\\b([\\w.-]*" + sensitiveWord + ")(\\s*(?::=|[:=])\\s*)(\"[^\"]*\"|'[^']*'|[^\\s\"'&]+)", "$1$2<redacted>"),
        // 2. --name value / -name value
        ("(?<![\\w-])(--?[\\w-]*" + sensitiveWord + ")(\\s+)([^\\s\"'-][^\\s\"']*)", "$1$2<redacted>"),
        // 3. HTTP authorization credentials
        ("\\b(Bearer|Basic)(\\s+)[A-Za-z0-9._~+/=-]{8,}", "$1$2<redacted>"),
        // 4. URL user info
        ("([a-z][a-z0-9+.-]*://)[^/\\s:@]+(?::[^/\\s@]*)?@", "$1<redacted>@"),
        // 5. sensitive query parameters
        ("([?&][\\w-]*(?:" + sensitiveWord + "|sig|signature)=)([^&\\s\"']+)", "$1<redacted>"),
        // 6. JWTs
        ("\\beyJ[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}", "<redacted>")
    ]

    // MARK: - Private

    /// Checks whether an environment variable key matches any sensitive pattern.
    private static func isSensitiveKey(_ key: String) -> Bool {
        let upper = key.uppercased()
        return sensitiveKeyPatterns.contains { upper.contains($0) }
    }
}
