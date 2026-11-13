//
//  CrashLogCheck.swift
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

/// Classifies the most recent Wine log for crash patterns.
///
/// Delegates to ``CrashClassifier`` and normalizes the diagnosis into a
/// ``CheckResult`` for flow branching. Returns `.unknown` when no log is
/// available, `.pass` when no patterns match, and `.fail` with evidence
/// when crash patterns are detected.
public struct CrashLogCheck: TroubleshootingCheck {
    public let checkId = "crash.log_classify"

    public init() {}

    public func run(params: [String: String], context: CheckContext) async -> CheckResult {
        guard let logURL = context.preflight.recentLogURL else {
            return CheckResult(
                outcome: .unknown,
                evidence: [:],
                summary: "No recent log file available",
                confidence: .low
            )
        }

        let logText: String
        do {
            logText = try String(contentsOf: logURL, encoding: .utf8)
        } catch {
            return CheckResult(
                outcome: .error,
                evidence: ["error": error.localizedDescription],
                summary: "Failed to read log file",
                confidence: nil
            )
        }

        let classifier = CrashClassifier()
        let diagnosis = classifier.classify(log: logText, exitCode: context.preflight.lastExitCode)

        if diagnosis.isEmpty {
            return CheckResult(
                outcome: .pass,
                evidence: [:],
                summary: "No crash patterns detected in log",
                confidence: .medium
            )
        }

        // Language-neutral values (raw values and log captures) so the UI can
        // rebuild them in the user's language; `headline` and `summary` stay
        // English for history and exports.
        var evidence: [String: String] = [:]
        if let category = diagnosis.primaryCategory {
            evidence[EvidenceKey.category] = category.rawValue
        }
        if let confidence = diagnosis.primaryConfidence {
            evidence[EvidenceKey.confidence] = confidence.rawValue
        }
        if let captures = diagnosis.matches.first?.captures, !captures.isEmpty {
            evidence[EvidenceKey.captures] = captures.joined(separator: ", ")
        }
        if let headline = diagnosis.headline {
            evidence[EvidenceKey.headline] = headline
        }
        evidence["matchCount"] = "\(diagnosis.matches.count)"

        return CheckResult(
            outcome: .fail,
            evidence: evidence,
            summary: diagnosis.headline ?? "Crash patterns detected",
            confidence: diagnosis.primaryConfidence
        )
    }

    /// The summary of a result from this check in the user's language.
    ///
    /// ``CheckResult/summary`` stays in English because it is written to
    /// history and escalation exports; this rebuilds the on-screen text from
    /// the result's outcome and evidence.
    ///
    /// - Parameter result: A result produced by ``run(params:context:)``.
    /// - Returns: The localized summary, or `nil` if the result was not
    ///   produced by this check or its evidence can't be read back.
    public static func localizedSummary(for result: CheckResult) -> String? {
        switch result.outcome {
        case .unknown:
            return String(localized: "troubleshooting.check.crashLog.noLog")
        case .error:
            return String(localized: "troubleshooting.check.crashLog.readFailed")
        case .pass:
            return String(localized: "troubleshooting.check.crashLog.clean")
        case .fail:
            if let headline = localizedHeadline(from: result.evidence) {
                return headline
            }
            // A headline whose parts can't be read back is shown as is.
            guard result.evidence[EvidenceKey.headline] == nil else { return nil }
            return String(localized: "troubleshooting.check.crashLog.detected")
        case .alreadyConfigured:
            return nil
        }
    }

    /// The result's evidence with its values in the user's language.
    ///
    /// The category and confidence are stored as raw values and the headline
    /// in English; this maps them to their localized names for display. The
    /// log captures are folded into the headline and not listed separately.
    ///
    /// - Parameter result: A result produced by ``run(params:context:)``.
    /// - Returns: The evidence to display.
    public static func localizedEvidence(for result: CheckResult) -> [String: String] {
        var evidence = result.evidence
        evidence[EvidenceKey.captures] = nil
        if let category = result.evidence[EvidenceKey.category].flatMap(CrashCategory.init(rawValue:)) {
            evidence[EvidenceKey.category] = category.displayName
        }
        if let confidence = result.evidence[EvidenceKey.confidence].flatMap(ConfidenceTier.init(rawValue:)) {
            evidence[EvidenceKey.confidence] = confidence.localizedName
        }
        if let headline = localizedHeadline(from: result.evidence) {
            evidence[EvidenceKey.headline] = headline
        }
        return evidence
    }

    private static func localizedHeadline(from evidence: [String: String]) -> String? {
        guard let category = evidence[EvidenceKey.category].flatMap(CrashCategory.init(rawValue:)),
              let confidence = evidence[EvidenceKey.confidence].flatMap(ConfidenceTier.init(rawValue:))
        else {
            return nil
        }
        return CrashDiagnosis.localizedHeadline(
            category: category,
            confidence: confidence,
            detail: evidence[EvidenceKey.captures]
        )
    }

    /// Evidence keys, which the flow definitions' `evidenceMap` labels.
    enum EvidenceKey {
        static let category = "primaryCategory"
        static let confidence = "confidence"
        static let captures = "captures"
        static let headline = "headline"
    }
}
