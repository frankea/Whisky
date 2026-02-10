//
//  RemediationAction.swift
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

/// A remediation action that can be suggested to users after crash classification.
public struct RemediationAction: Codable, Sendable, Identifiable {
    /// Stable identifier for this action.
    public let id: String

    /// Short user-facing title.
    public let title: String

    /// Detailed description of what this action does.
    public let description: String

    /// The crash category this action addresses.
    public let category: CrashCategory

    /// The type of action to perform.
    public let actionType: ActionType

    /// Risk level for performing this action.
    public let risk: RiskLevel

    /// Key path for a bottle setting to change (for `changeSetting` actions).
    public let settingKeyPath: String?

    /// Value to set (for `changeSetting` actions).
    public let settingValue: String?

    /// Winetricks verb to install (for `installVerb` actions).
    public let winetricksVerb: String?

    /// One-sentence explanation of what will change.
    public let whatWillChange: String

    /// How to undo this action.
    public let undoPath: String

    /// Whether this action takes effect on the next launch.
    public let appliesNextLaunch: Bool

    /// Types of remediation actions.
    public enum ActionType: String, Codable, Sendable {
        /// Change a bottle or program setting.
        case changeSetting

        /// Install a Winetricks verb.
        case installVerb

        /// Switch graphics backend.
        case switchBackend

        /// Informational only, no automated action.
        case informational
    }

    /// Risk levels for remediation actions.
    public enum RiskLevel: String, Codable, Sendable, Comparable {
        case low
        case medium
        case high

        private var sortOrder: Int {
            switch self {
            case .low: 0
            case .medium: 1
            case .high: 2
            }
        }

        public static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
            lhs.sortOrder < rhs.sortOrder
        }
    }
}
