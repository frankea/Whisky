//
//  CrashClassifier.swift
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

/// Scans Wine log output line-by-line against pattern definitions and returns
/// scored ``DiagnosisMatch`` entries grouped by ``CrashCategory``.
///
/// ## Overview
///
/// `CrashClassifier` is the core classification pipeline for Wine crash diagnostics.
/// It takes raw log text and an optional exit code, then:
///
/// 1. Splits the log into lines
/// 2. Evaluates each line against all loaded patterns (with substring prefilter optimization)
/// 3. Aggregates matches by category
/// 4. Computes a primary diagnosis (highest severity + confidence)
/// 5. Returns a ``CrashDiagnosis`` with matches, category counts, and remediation IDs
///
/// ## Example
///
/// ```swift
/// let (patterns, remediations) = PatternLoader.loadDefaults()
/// let classifier = CrashClassifier(patterns: patterns, remediations: remediations)
/// let diagnosis = classifier.classify(log: wineLogOutput, exitCode: exitCode)
/// ```
public struct CrashClassifier: Sendable {
    /// Compiled patterns ready for matching.
    private var patterns: [CrashPattern]

    /// Available remediation actions keyed by ID.
    private let remediations: [String: RemediationAction]

    /// Creates a classifier with the given patterns and remediations.
    ///
    /// All regex patterns are compiled eagerly at init time for performance.
    ///
    /// - Parameters:
    ///   - patterns: Array of crash patterns to match against.
    ///   - remediations: Dictionary of remediation actions keyed by ID.
    public init(patterns: [CrashPattern], remediations: [String: RemediationAction]) {
        var compiled = patterns
        for index in compiled.indices {
            compiled[index].compileRegex()
        }
        self.patterns = compiled
        self.remediations = remediations
    }

    /// Creates a classifier using the default bundled patterns and remediations.
    public init() {
        let (patterns, remediations) = PatternLoader.loadDefaults()
        self.init(patterns: patterns, remediations: remediations)
    }

    /// Classifies Wine log output for crash patterns.
    ///
    /// Scans the log line-by-line against all loaded patterns, using substring
    /// prefilter optimization to skip regex evaluation when possible.
    ///
    /// - Parameters:
    ///   - log: The full Wine log output text.
    ///   - exitCode: The Wine process exit code, if available.
    /// - Returns: A ``CrashDiagnosis`` containing all matches, category counts,
    ///   and applicable remediation IDs.
    public func classify(log: String, exitCode: Int32? = nil) -> CrashDiagnosis {
        let lines = log.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var allMatches: [DiagnosisMatch] = []
        var mutablePatterns = patterns

        // Step 1-2: Scan each line against all patterns
        for (lineIndex, line) in lines.enumerated() {
            for patternIndex in mutablePatterns.indices {
                if let patternMatch = mutablePatterns[patternIndex].match(line: line) {
                    let diagMatch = DiagnosisMatch(
                        pattern: mutablePatterns[patternIndex],
                        lineIndex: lineIndex,
                        lineText: line,
                        captures: patternMatch.captures
                    )
                    allMatches.append(diagMatch)
                }
            }
        }

        // Step 3: Aggregate matches by category
        var categoryCounts: [CrashCategory: Int] = [:]
        for diagMatch in allMatches {
            categoryCounts[diagMatch.pattern.category, default: 0] += 1
        }

        // Step 4: Sort matches by confidence DESC, then severity DESC
        let sortedMatches = allMatches.sorted { lhs, rhs in
            if lhs.pattern.confidence != rhs.pattern.confidence {
                return lhs.pattern.confidence > rhs.pattern.confidence
            }
            return lhs.pattern.severity > rhs.pattern.severity
        }

        // Compute primary diagnosis from highest-ranked match
        let primaryMatch = sortedMatches.first
        let primaryCategory = primaryMatch?.pattern.category
        let primaryConfidence = primaryMatch.map { ConfidenceTier(score: $0.pattern.confidence) }

        // Build headline from primary match
        let headline = primaryMatch.map { buildHeadline(for: $0) }

        // Step 5: Collect unique remediation action IDs preserving order of confidence
        var seenIds = Set<String>()
        var remediationIds: [String] = []
        for diagMatch in sortedMatches {
            guard let actionIds = diagMatch.pattern.remediationActionIds else { continue }
            for actionId in actionIds where !seenIds.contains(actionId) {
                seenIds.insert(actionId)
                remediationIds.append(actionId)
            }
        }

        return CrashDiagnosis(
            matches: sortedMatches,
            categoryCounts: categoryCounts,
            primaryCategory: primaryCategory,
            primaryConfidence: primaryConfidence,
            headline: headline,
            exitCode: exitCode,
            applicableRemediationIds: remediationIds
        )
    }

    // MARK: - Private

    private func buildHeadline(for match: DiagnosisMatch) -> String {
        let category = match.pattern.category.displayName
        let confidence = ConfidenceTier(score: match.pattern.confidence).displayName

        if !match.captures.isEmpty {
            let detail = match.captures.joined(separator: ", ")
            return "\(category): \(detail) (\(confidence) confidence)"
        }

        return "\(category) (\(confidence) confidence)"
    }
}
