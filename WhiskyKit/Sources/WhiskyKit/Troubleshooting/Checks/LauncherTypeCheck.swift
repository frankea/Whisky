//
//  LauncherTypeCheck.swift
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

/// Detects the launcher type for the program being troubleshot.
///
/// Uses the launcher type from preflight data. If `params["expected"]`
/// is provided, compares the detected type against the expected value.
/// Returns `.pass` with the detected launcher type, or `.unknown`
/// if no launcher was detected.
public struct LauncherTypeCheck: TroubleshootingCheck {
    public let checkId = "launcher.type_check"

    /// Ends the English summary of a detection that matched `params["expected"]`;
    /// the evidence is the same with or without an expected launcher.
    private static let matchesExpectedSuffix = " (matches expected)"

    public init() {}

    public let signature: CheckSignature? = CheckSignature(
        acceptedParams: ["expected"], outcomes: [.pass, .fail, .unknown]
    )

    public func run(params: [String: String], context: CheckContext) async -> CheckResult {
        let detectedLauncher = context.preflight.launcherType

        guard let launcher = detectedLauncher else {
            return CheckResult(
                outcome: .unknown,
                evidence: [:],
                summary: "No launcher type detected",
                confidence: .low
            )
        }

        let evidence = ["detectedLauncher": launcher]

        if let expected = params["expected"] {
            if launcher.lowercased() == expected.lowercased() {
                return CheckResult(
                    outcome: .pass,
                    evidence: evidence,
                    summary: "Launcher detected: \(launcher)\(Self.matchesExpectedSuffix)",
                    confidence: .high
                )
            }
            return CheckResult(
                outcome: .fail,
                evidence: [
                    "detectedLauncher": launcher,
                    "expected": expected
                ],
                summary: "Launcher is \(launcher), expected \(expected)",
                confidence: .high
            )
        }

        return CheckResult(
            outcome: .pass,
            evidence: evidence,
            summary: "Launcher detected: \(launcher)",
            confidence: .high
        )
    }

    /// The summary of a result from this check in the user's language.
    ///
    /// ``CheckResult/summary`` stays in English because it is written to
    /// history and escalation exports; this rebuilds the on-screen text from
    /// the result's outcome and evidence.
    ///
    /// - Parameter result: A result produced by ``run(params:context:)``.
    /// - Returns: The localized summary, or `nil` to show ``CheckResult/summary``.
    public static func localizedSummary(for result: CheckResult) -> String? {
        guard let launcher = result.evidence["detectedLauncher"] else {
            return result.outcome == .unknown ? String(localized: "troubleshooting.check.launcher.none") : nil
        }
        switch result.outcome {
        case .pass:
            if result.summary.hasSuffix(matchesExpectedSuffix) {
                return String(localized: "troubleshooting.check.launcher.matches \(launcher)")
            }
            return String(localized: "troubleshooting.check.launcher.detected \(launcher)")
        case .fail:
            guard let expected = result.evidence["expected"] else { return nil }
            return String(localized: "troubleshooting.check.launcher.mismatch \(launcher) \(expected)")
        case .alreadyConfigured, .error, .unknown:
            return nil
        }
    }
}
