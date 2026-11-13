//
//  GameConfigAvailableCheck.swift
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

/// Checks whether a known game configuration exists for the current program.
///
/// Delegates to ``GameMatcher`` using the program name from context to
/// find a match in the game compatibility database. Returns `.pass`
/// with game details if a match is found, enabling flows to suggest
/// "Apply known-good config" actions.
public struct GameConfigAvailableCheck: TroubleshootingCheck {
    public let checkId = "game.config_available"

    private static let noProgramSummary = "No program specified for game matching"
    private static let emptyDatabaseSummary = "Game database is empty"

    public init() {}

    public func run(params: [String: String], context: CheckContext) async -> CheckResult {
        guard let programName = context.programName else {
            return CheckResult(
                outcome: .unknown,
                evidence: [:],
                summary: Self.noProgramSummary,
                confidence: .low
            )
        }

        let entries = GameDBLoader.loadDefaults()
        guard !entries.isEmpty else {
            return CheckResult(
                outcome: .unknown,
                evidence: [:],
                summary: Self.emptyDatabaseSummary,
                confidence: .low
            )
        }

        // Build minimal metadata from the program name
        let metadata = ProgramMetadata(exeName: programName)
        let bestMatch = GameMatcher.bestMatch(metadata: metadata, against: entries)

        guard let result = bestMatch else {
            return CheckResult(
                outcome: .fail,
                evidence: ["programName": programName],
                summary: "No known game configuration for \(programName)",
                confidence: .medium
            )
        }

        var evidence = [
            "gameName": result.entry.title,
            "confidence": String(format: "%.0f%%", result.confidence * 100),
            "tier": String(describing: result.tier),
            "variantCount": "\(result.entry.variants.count)"
        ]

        evidence["rating"] = result.entry.rating.displayName

        return CheckResult(
            outcome: .pass,
            evidence: evidence,
            summary: "Known config available: \(result.entry.title)",
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
    /// - Returns: The localized summary, or `nil` if the result was not
    ///   produced by this check.
    public static func localizedSummary(for result: CheckResult) -> String? {
        switch result.outcome {
        case .unknown:
            switch result.summary {
            case noProgramSummary:
                return String(localized: "troubleshooting.check.gameConfig.noProgram")
            case emptyDatabaseSummary:
                return String(localized: "troubleshooting.check.gameConfig.emptyDatabase")
            default:
                return nil
            }
        case .fail:
            guard let programName = result.evidence["programName"] else { return nil }
            return String(localized: "troubleshooting.check.gameConfig.none \(programName)")
        case .pass:
            guard let gameName = result.evidence["gameName"] else { return nil }
            return String(localized: "troubleshooting.check.gameConfig.available \(gameName)")
        case .alreadyConfigured, .error:
            return nil
        }
    }
}
