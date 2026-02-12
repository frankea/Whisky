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

        var evidence: [String: String] = [:]
        if let category = diagnosis.primaryCategory {
            evidence["primaryCategory"] = category.displayName
        }
        if let confidence = diagnosis.primaryConfidence {
            evidence["confidence"] = confidence.displayName
        }
        if let headline = diagnosis.headline {
            evidence["headline"] = headline
        }
        evidence["matchCount"] = "\(diagnosis.matches.count)"

        return CheckResult(
            outcome: .fail,
            evidence: evidence,
            summary: diagnosis.headline ?? "Crash patterns detected",
            confidence: diagnosis.primaryConfidence
        )
    }
}
