//
//  GraphicsBackendCheck.swift
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

/// Verifies the current graphics backend against an expected value.
///
/// Reads the resolved graphics backend from preflight data and compares it
/// to the `expected` parameter. Returns `.alreadyConfigured` when the
/// backend is explicitly set, `.pass` when it resolves correctly via
/// `.recommended`, and `.fail` when the backend does not match.
public struct GraphicsBackendCheck: TroubleshootingCheck {
    public let checkId = "graphics.backend_is"

    public init() {}

    public func run(params: [String: String], context: CheckContext) async -> CheckResult {
        guard let expected = params["expected"] else {
            return CheckResult(
                outcome: .error,
                evidence: [:],
                summary: "Missing 'expected' parameter",
                confidence: nil
            )
        }

        let resolvedBackend = context.preflight.graphicsBackend

        let evidence = [
            "current": resolvedBackend,
            "expected": expected
        ]

        if resolvedBackend == expected {
            return CheckResult(
                outcome: .alreadyConfigured,
                evidence: evidence,
                summary: "Backend is already set to \(expected)",
                confidence: .high
            )
        }

        return CheckResult(
            outcome: .fail,
            evidence: evidence,
            summary: "Backend is \(resolvedBackend), expected \(expected)",
            confidence: .high
        )
    }

    /// The summary of a result from this check in the user's language.
    ///
    /// ``CheckResult/summary`` stays in English because it is written to
    /// history and escalation exports; this rebuilds the on-screen text from
    /// the result's outcome and evidence, naming backends by their display
    /// names rather than their raw identifiers.
    ///
    /// - Parameter result: A result produced by ``run(params:context:)``.
    /// - Returns: The localized summary, or `nil` if the result was not
    ///   produced by this check.
    public static func localizedSummary(for result: CheckResult) -> String? {
        guard let expected = result.evidence["expected"].map(backendName) else { return nil }
        switch result.outcome {
        case .alreadyConfigured:
            return String(localized: "troubleshooting.check.backend.matches \(expected)")
        case .fail:
            guard let current = result.evidence["current"].map(backendName) else { return nil }
            return String(localized: "troubleshooting.check.backend.mismatch \(current) \(expected)")
        case .pass, .error, .unknown:
            return nil
        }
    }

    /// The display name for a raw ``GraphicsBackend`` value, or the value itself.
    private static func backendName(_ rawValue: String) -> String {
        GraphicsBackend(rawValue: rawValue)?.displayName ?? rawValue
    }
}
