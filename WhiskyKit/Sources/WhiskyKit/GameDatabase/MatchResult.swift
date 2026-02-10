//
//  MatchResult.swift
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

/// The tier of confidence for a game database match.
///
/// Higher tiers indicate stronger identification signals.
/// - ``hardIdentifier``: Definitive match (Steam App ID, exe fingerprint). Auto-apply eligible.
/// - ``strongHeuristic``: High-confidence match (exe name, path pattern). Requires confirmation.
/// - ``fuzzy``: Low-confidence match (name similarity). Search results only.
public enum MatchTier: Int, Codable, Sendable, Comparable {
    /// Definitive match via Steam App ID or executable fingerprint.
    case fuzzy = 1
    /// High-confidence match via executable name or path pattern.
    case strongHeuristic = 2
    /// Definitive match via hard identifier.
    case hardIdentifier = 3

    public static func < (lhs: MatchTier, rhs: MatchTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The result of matching a program against the game compatibility database.
///
/// Contains the matched entry, a confidence score, the match tier,
/// a human-readable explanation, and an optionally auto-selected variant.
public struct MatchResult: Sendable {
    /// The matched game database entry.
    public let entry: GameDBEntry
    /// Confidence score in the range 0.0...1.0.
    public let confidence: Double
    /// The tier of the match (hard identifier, strong heuristic, or fuzzy).
    public let tier: MatchTier
    /// A human-readable explanation of why this match was made.
    public let explanation: String
    /// The recommended variant for the current machine, if auto-selected.
    public let recommendedVariant: GameConfigVariant?

    public init(
        entry: GameDBEntry,
        confidence: Double,
        tier: MatchTier,
        explanation: String,
        recommendedVariant: GameConfigVariant? = nil
    ) {
        self.entry = entry
        self.confidence = confidence
        self.tier = tier
        self.explanation = explanation
        self.recommendedVariant = recommendedVariant
    }
}
