//
//  CrashDiagnosis.swift
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

/// The result of classifying a Wine log for crash patterns.
///
/// Contains all matches grouped by category, a primary diagnosis,
/// and references to applicable remediation actions.
public struct CrashDiagnosis: Sendable {
    /// All pattern matches found in the log, sorted by confidence descending then severity descending.
    public let matches: [DiagnosisMatch]

    /// Count of matches per category.
    public let categoryCounts: [CrashCategory: Int]

    /// The category with the highest-confidence, highest-severity match.
    public let primaryCategory: CrashCategory?

    /// Confidence tier of the primary diagnosis.
    public let primaryConfidence: ConfidenceTier?

    /// One-line headline summarizing the primary diagnosis.
    public let headline: String?

    /// The Wine process exit code, if available.
    public let exitCode: Int32?

    /// IDs of remediation actions applicable to the matched patterns.
    public let applicableRemediationIds: [String]

    /// Whether no patterns matched.
    public var isEmpty: Bool {
        matches.isEmpty
    }

    public init(
        matches: [DiagnosisMatch],
        categoryCounts: [CrashCategory: Int],
        primaryCategory: CrashCategory?,
        primaryConfidence: ConfidenceTier?,
        headline: String?,
        exitCode: Int32?,
        applicableRemediationIds: [String]
    ) {
        self.matches = matches
        self.categoryCounts = categoryCounts
        self.primaryCategory = primaryCategory
        self.primaryConfidence = primaryConfidence
        self.headline = headline
        self.exitCode = exitCode
        self.applicableRemediationIds = applicableRemediationIds
    }

    /// Resolves remediation action IDs to full action objects.
    ///
    /// Actions are sorted by the confidence of their associated pattern match
    /// (descending), then by risk level (ascending, lowest risk first).
    ///
    /// - Parameter actions: Dictionary of all available remediation actions keyed by ID.
    /// - Returns: Sorted array of applicable remediation actions.
    public func remediations(from actions: [String: RemediationAction]) -> [RemediationAction] {
        // Build a lookup from action ID to the best confidence score from matches
        var actionConfidence: [String: Double] = [:]
        for diagMatch in matches {
            guard let actionIds = diagMatch.pattern.remediationActionIds else { continue }
            for actionId in actionIds {
                let existing = actionConfidence[actionId] ?? 0
                actionConfidence[actionId] = max(existing, diagMatch.pattern.confidence)
            }
        }

        return applicableRemediationIds.compactMap { actions[$0] }
            .sorted { lhs, rhs in
                let lhsConf = actionConfidence[lhs.id] ?? 0
                let rhsConf = actionConfidence[rhs.id] ?? 0
                if lhsConf != rhsConf {
                    return lhsConf > rhsConf // Higher confidence first
                }
                return lhs.risk < rhs.risk // Lower risk first
            }
    }
}
