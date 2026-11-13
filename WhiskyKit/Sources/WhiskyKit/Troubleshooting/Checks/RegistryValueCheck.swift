//
//  RegistryValueCheck.swift
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

/// Checks a Wine registry value against an expected value.
///
/// Reads a registry key via the Wine registry file at the bottle's
/// prefix path. Params: `key` (registry path), `valueName` (value name),
/// `type` (REG_SZ, REG_DWORD, etc.), and optionally `expected`.
/// Returns `.pass` if the value matches, `.fail` otherwise, or
/// `.unknown` if the key does not exist.
public struct RegistryValueCheck: TroubleshootingCheck {
    public let checkId = "registry.value_check"

    public init() {}

    public func run(params: [String: String], context: CheckContext) async -> CheckResult {
        guard let key = params["key"], let valueName = params["valueName"] else {
            return CheckResult(
                outcome: .error,
                evidence: [:],
                summary: "Missing 'key' or 'valueName' parameter",
                confidence: nil
            )
        }

        // Parse the registry file directly from the bottle prefix
        // to avoid needing a Wine process (which requires @MainActor Bottle).
        let registryValue = WineRegistryFile.readValue(
            bottleURL: context.bottleURL,
            key: key,
            valueName: valueName
        )

        let expected = params["expected"]

        var evidence = [
            "key": key,
            "valueName": valueName
        ]

        guard let currentValue = registryValue else {
            return CheckResult(
                outcome: .unknown,
                evidence: evidence,
                summary: "Registry key not found: \(key)\\\\\\(\(valueName))",
                confidence: .low
            )
        }

        evidence["currentValue"] = currentValue

        if let expected {
            evidence["expected"] = expected
            if currentValue == expected {
                return CheckResult(
                    outcome: .pass,
                    evidence: evidence,
                    summary: "\(valueName) = \(currentValue)",
                    confidence: .high
                )
            }
            return CheckResult(
                outcome: .fail,
                evidence: evidence,
                summary: "\(valueName) is \(currentValue), expected \(expected)",
                confidence: .high
            )
        }

        return CheckResult(
            outcome: .pass,
            evidence: evidence,
            summary: "\(valueName) = \(currentValue)",
            confidence: .high
        )
    }

    /// The summary of a result from this check in the user's language.
    ///
    /// ``CheckResult/summary`` stays in English because it is written to
    /// history and escalation exports; this rebuilds the on-screen text from
    /// the result's outcome and evidence. Summaries with no words in them
    /// (`name = value`) and the flow-authoring error for missing parameters
    /// have no localized form.
    ///
    /// - Parameter result: A result produced by ``run(params:context:)``.
    /// - Returns: The localized summary, or `nil` to show ``CheckResult/summary``.
    public static func localizedSummary(for result: CheckResult) -> String? {
        guard let key = result.evidence["key"], let valueName = result.evidence["valueName"] else {
            return nil
        }
        switch result.outcome {
        case .unknown:
            return String(localized: "troubleshooting.check.registry.notFound \(key) \(valueName)")
        case .fail:
            guard let currentValue = result.evidence["currentValue"],
                  let expected = result.evidence["expected"]
            else {
                return nil
            }
            return String(localized: "troubleshooting.check.value.mismatch \(valueName) \(currentValue) \(expected)")
        case .pass, .alreadyConfigured, .error:
            return nil
        }
    }
}
