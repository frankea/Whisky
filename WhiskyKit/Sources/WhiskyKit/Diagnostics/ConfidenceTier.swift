//
//  ConfidenceTier.swift
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

/// Three-tier confidence model for crash diagnoses.
///
/// Maps internal numeric scores (0-1) to user-facing tiers.
/// Raw numeric scores are never shown to users.
public enum ConfidenceTier: String, Codable, Sendable, CaseIterable, Comparable {
    /// Score >= 0.8: signature match or strong multi-signal correlation.
    case high

    /// Score >= 0.5: moderate signal or multiple weak signals.
    case medium

    /// Score < 0.5: heuristic or single weak signal.
    case low

    /// Creates a confidence tier from a numeric score.
    ///
    /// - Parameter score: A value in the range 0...1.
    public init(score: Double) {
        if score >= 0.8 {
            self = .high
        } else if score >= 0.5 {
            self = .medium
        } else {
            self = .low
        }
    }

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .high:
            "High"
        case .medium:
            "Medium"
        case .low:
            "Low"
        }
    }

    // MARK: - Comparable

    private var sortOrder: Int {
        switch self {
        case .high: 2
        case .medium: 1
        case .low: 0
        }
    }

    public static func < (lhs: ConfidenceTier, rhs: ConfidenceTier) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}
