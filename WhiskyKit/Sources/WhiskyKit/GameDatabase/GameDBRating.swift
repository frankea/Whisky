//
//  GameDBRating.swift
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

/// The compatibility rating for a game in the database.
///
/// Ratings indicate how well a game runs under Wine on macOS.
/// The five tiers are ordered from best to worst: ``works`` is the
/// highest rating, ``notSupported`` the lowest.
public enum CompatibilityRating: String, Codable, Sendable, CaseIterable, Comparable {
    /// Game runs flawlessly with no issues.
    case works
    /// Game is playable with minor issues or workarounds.
    case playable
    /// Game has not been tested or verified.
    case unverified
    /// Game has significant issues preventing normal play.
    case broken
    /// Game is not supported (e.g., requires anti-cheat or kernel driver).
    case notSupported

    /// Severity ordering for ``Comparable`` conformance.
    ///
    /// Lower values indicate better compatibility.
    private var severityOrder: Int {
        switch self {
        case .works: 0
        case .playable: 1
        case .unverified: 2
        case .broken: 3
        case .notSupported: 4
        }
    }

    public static func < (lhs: CompatibilityRating, rhs: CompatibilityRating) -> Bool {
        lhs.severityOrder < rhs.severityOrder
    }

    /// A localized, human-readable display name for this rating.
    public var displayName: String {
        switch self {
        case .works:
            String(localized: "gamedb.rating.works")
        case .playable:
            String(localized: "gamedb.rating.playable")
        case .unverified:
            String(localized: "gamedb.rating.unverified")
        case .broken:
            String(localized: "gamedb.rating.broken")
        case .notSupported:
            String(localized: "gamedb.rating.notSupported")
        }
    }

    /// The SF Symbol name appropriate for this rating tier.
    public var systemImage: String {
        switch self {
        case .works:
            "checkmark.circle"
        case .playable:
            "exclamationmark.triangle"
        case .unverified:
            "questionmark.circle"
        case .broken:
            "xmark.circle"
        case .notSupported:
            "nosign"
        }
    }
}
