//
//  CrashPattern.swift
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

/// Severity level for a crash pattern match.
public enum PatternSeverity: String, Codable, Sendable, Comparable {
    case critical
    case error
    case warning
    case info

    private var sortOrder: Int {
        switch self {
        case .critical: 3
        case .error: 2
        case .warning: 1
        case .info: 0
        }
    }

    public static func < (lhs: PatternSeverity, rhs: PatternSeverity) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

/// Result of a successful pattern match against a log line.
public struct PatternMatch: Sendable {
    /// Captured groups from the regex match.
    public let captures: [String]

    public init(captures: [String]) {
        self.captures = captures
    }
}

/// A single crash pattern definition loaded from the pattern database.
///
/// Each pattern specifies a regex to match against Wine log lines, with an
/// optional substring prefilter for performance. The prefilter is checked
/// with `String.contains()` before the regex is evaluated.
public struct CrashPattern: Codable, Sendable, Identifiable {
    /// Stable identifier for this pattern.
    public let id: String

    /// Category this pattern belongs to.
    public let category: CrashCategory

    /// Severity when this pattern matches.
    public let severity: PatternSeverity

    /// Confidence score (0...1) when this pattern matches.
    public let confidence: Double

    /// Optional fast-path substring check. If set and the line does not
    /// contain this substring, the regex is skipped entirely.
    public let substringPrefilter: String?

    /// Regular expression pattern string.
    public let regex: String

    /// Searchable tags for this pattern.
    public let tags: [String]

    /// Names for regex capture groups (documentation only).
    public let captureGroups: [String]?

    /// IDs of remediation actions applicable when this pattern matches.
    public let remediationActionIds: [String]?

    // MARK: - Transient

    /// Lazily compiled regex. Not part of Codable conformance.
    /// Safe because Regex is only mutated during single-threaded init/compile
    /// and is thereafter read-only.
    private nonisolated(unsafe) var _compiledRegex: Regex<AnyRegexOutput>?

    enum CodingKeys: String, CodingKey {
        case id, category, severity, confidence, substringPrefilter
        case regex, tags, captureGroups, remediationActionIds
    }

    public init(
        id: String,
        category: CrashCategory,
        severity: PatternSeverity,
        confidence: Double,
        substringPrefilter: String?,
        regex: String,
        tags: [String],
        captureGroups: [String]?,
        remediationActionIds: [String]?
    ) {
        self.id = id
        self.category = category
        self.severity = severity
        self.confidence = confidence
        self.substringPrefilter = substringPrefilter
        self.regex = regex
        self.tags = tags
        self.captureGroups = captureGroups
        self.remediationActionIds = remediationActionIds
    }

    /// Attempts to match this pattern against a single log line.
    ///
    /// If `substringPrefilter` is set and the line does not contain it,
    /// the regex is not evaluated (fast path).
    ///
    /// - Parameter line: A single line of Wine log output.
    /// - Returns: A `PatternMatch` with captures if the pattern matched, or `nil`.
    public mutating func match(line: String) -> PatternMatch? {
        // Fast path: substring prefilter
        if let prefilter = substringPrefilter, !line.contains(prefilter) {
            return nil
        }

        // Compile regex lazily
        if _compiledRegex == nil {
            _compiledRegex = try? Regex(regex)
        }

        guard let compiled = _compiledRegex,
              let result = try? compiled.firstMatch(in: line)
        else {
            return nil
        }

        // Extract captures (skip the full match at index 0)
        var captures: [String] = []
        for index in 1 ..< result.count {
            if let substring = result[index].substring {
                captures.append(String(substring))
            }
        }

        return PatternMatch(captures: captures)
    }

    /// Compiles the regex pattern eagerly. Call at init time for
    /// classifier performance.
    public mutating func compileRegex() {
        _compiledRegex = try? Regex(regex)
    }
}
