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

    public init() {}

    public func run(params: [String: String], context: CheckContext) async -> CheckResult {
        guard let programName = context.programName else {
            return CheckResult(
                outcome: .unknown,
                evidence: [:],
                summary: "No program specified for game matching",
                confidence: .low
            )
        }

        let entries = GameDBLoader.loadDefaults()
        guard !entries.isEmpty else {
            return CheckResult(
                outcome: .unknown,
                evidence: [:],
                summary: "Game database is empty",
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

        evidence["rating"] = String(describing: result.entry.rating)

        return CheckResult(
            outcome: .pass,
            evidence: evidence,
            summary: "Known config available: \(result.entry.title)",
            confidence: .high
        )
    }
}
