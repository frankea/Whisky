//
//  WinetricksVerbCheck.swift
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

/// Checks whether specific winetricks verbs are installed in the bottle.
///
/// Loads the installed verbs from the ``WinetricksVerbCache`` for the
/// bottle and compares against the comma-separated list in `params["verbs"]`.
/// Returns `.alreadyConfigured` if all verbs are present, `.fail` with
/// evidence listing missing verbs otherwise.
public struct WinetricksVerbCheck: TroubleshootingCheck {
    public let checkId = "winetricks.verb_check"

    public init() {}

    public let signature: CheckSignature? = CheckSignature(
        requiredParams: ["verbs"], outcomes: [.alreadyConfigured, .fail]
    )

    public func run(params: [String: String], context: CheckContext) async -> CheckResult {
        guard let verbsParam = params["verbs"], !verbsParam.isEmpty else {
            return CheckResult(
                outcome: .error,
                evidence: [:],
                summary: "Missing 'verbs' parameter",
                confidence: nil
            )
        }

        let expectedVerbs = verbsParam.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }

        let cache = WinetricksVerbCache.load(from: context.bottleURL)
        let installedVerbs = cache?.installedVerbs ?? []

        let missingVerbs = expectedVerbs.filter { !installedVerbs.contains($0) }

        var evidence = [
            "expected": expectedVerbs.joined(separator: ", "),
            "installed": installedVerbs.sorted().joined(separator: ", ")
        ]

        if missingVerbs.isEmpty {
            return CheckResult(
                outcome: .alreadyConfigured,
                evidence: evidence,
                summary: "All required verbs are installed",
                confidence: .high
            )
        }

        evidence["missing"] = missingVerbs.joined(separator: ", ")
        return CheckResult(
            outcome: .fail,
            evidence: evidence,
            summary: "\(missingVerbs.count) missing verb(s): \(missingVerbs.joined(separator: ", "))",
            confidence: .high
        )
    }

    /// The verbs in a comma-separated list, as flows and this check's
    /// evidence write them (`"vcrun2019, dotnet48"`).
    ///
    /// - Parameter list: The comma-separated verbs.
    /// - Returns: Each verb, trimmed, in order.
    public static func verbs(in list: String) -> [String] {
        list.flowParamList
    }

    /// The verbs a result from this check found missing.
    ///
    /// - Parameter result: A result produced by ``run(params:context:)``.
    /// - Returns: The missing verbs in the order checked; empty when none
    ///   are missing or the result is not this check's.
    public static func missingVerbs(in result: CheckResult) -> [String] {
        result.evidence["missing"].map(verbs(in:)) ?? []
    }

    /// The summary of a result from this check in the user's language.
    ///
    /// ``CheckResult/summary`` stays in English because it is written to
    /// history and escalation exports; this rebuilds the on-screen text from
    /// the result's outcome and evidence. Verb names are winetricks
    /// identifiers and stay as they are.
    ///
    /// - Parameter result: A result produced by ``run(params:context:)``.
    /// - Returns: The localized summary, or `nil` if the result was not
    ///   produced by this check.
    public static func localizedSummary(for result: CheckResult) -> String? {
        switch result.outcome {
        case .alreadyConfigured:
            return String(localized: "troubleshooting.check.winetricks.allInstalled")
        case .fail:
            guard let missing = result.evidence["missing"], !missing.isEmpty else { return nil }
            let count = missing.components(separatedBy: ", ").count
            return String(localized: "troubleshooting.check.winetricks.missing \(count) \(missing)")
        case .pass, .error, .unknown:
            return nil
        }
    }
}
