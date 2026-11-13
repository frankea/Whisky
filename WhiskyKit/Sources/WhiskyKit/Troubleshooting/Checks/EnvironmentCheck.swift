//
//  EnvironmentCheck.swift
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

/// Checks whether a specific environment variable is set in the bottle environment.
///
/// Reads the bottle settings and resolves the environment via
/// ``EnvironmentBuilder`` to check for the key specified in `params["key"]`.
/// If `params["expected"]` is provided, the value must match.
public struct EnvironmentCheck: TroubleshootingCheck {
    public let checkId = "env.check_var"

    public init() {}

    // swiftlint:disable:next function_body_length
    public func run(params: [String: String], context: CheckContext) async -> CheckResult {
        guard let key = params["key"] else {
            return CheckResult(
                outcome: .error,
                evidence: [:],
                summary: "Missing 'key' parameter",
                confidence: nil
            )
        }

        let bottleURL = context.bottleURL
        let metadataURL = bottleURL.appending(path: "Metadata.plist")

        let settings: BottleSettings
        do {
            settings = try BottleSettings.decode(from: metadataURL)
        } catch {
            return CheckResult(
                outcome: .error,
                evidence: ["error": error.localizedDescription],
                summary: "Failed to read bottle settings",
                confidence: nil
            )
        }

        // Build the environment from bottle settings
        var builder = EnvironmentBuilder()
        _ = settings.populateBottleManagedLayer(builder: &builder)
        _ = settings.populateLauncherManagedLayer(builder: &builder)
        settings.populateInputCompatibilityLayer(builder: &builder)
        let (environment, _) = builder.resolve()

        let currentValue = environment[key]
        let expected = params["expected"]

        var evidence = ["key": key]
        if let currentValue {
            evidence["currentValue"] = currentValue
        }
        if let expected {
            evidence["expected"] = expected
        }

        if let expected {
            if currentValue == expected {
                return CheckResult(
                    outcome: .pass,
                    evidence: evidence,
                    summary: "\(key) is set to \(expected)",
                    confidence: .high
                )
            }
            return CheckResult(
                outcome: .fail,
                evidence: evidence,
                summary: "\(key) is \(currentValue ?? "not set"), expected \(expected)",
                confidence: .high
            )
        }

        // No expected value -- just check if the key is set
        if currentValue != nil {
            return CheckResult(
                outcome: .pass,
                evidence: evidence,
                summary: "\(key) is set",
                confidence: .high
            )
        }

        return CheckResult(
            outcome: .fail,
            evidence: evidence,
            summary: "\(key) is not set",
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
    /// - Returns: The localized summary, or `nil` to show ``CheckResult/summary`` (the
    ///   flow-authoring error for a missing parameter has no localized form).
    public static func localizedSummary(for result: CheckResult) -> String? {
        let evidence = result.evidence
        if result.outcome == .error {
            return evidence["error"] == nil ? nil : String(localized: "troubleshooting.check.settingsUnreadable")
        }
        guard let key = evidence["key"] else { return nil }
        let current = evidence["currentValue"]
        switch (result.outcome, evidence["expected"]) {
        case let (.pass, expected?):
            return String(localized: "troubleshooting.check.env.matches \(key) \(expected)")
        case (.pass, nil):
            return String(localized: "troubleshooting.check.env.set \(key)")
        case let (.fail, expected?):
            guard let current else {
                return String(localized: "troubleshooting.check.env.mismatchUnset \(key) \(expected)")
            }
            return String(localized: "troubleshooting.check.value.mismatch \(key) \(current) \(expected)")
        case (.fail, nil):
            return String(localized: "troubleshooting.check.env.unset \(key)")
        default:
            return nil
        }
    }
}
