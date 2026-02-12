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
}
