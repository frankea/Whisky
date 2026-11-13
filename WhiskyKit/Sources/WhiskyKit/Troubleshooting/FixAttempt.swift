//
//  FixAttempt.swift
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

/// A record of a single fix application during a troubleshooting session.
///
/// Extends the pattern from ``TroubleshootingFixAttempt`` (Phase 6) with
/// explicit result tracking and before/after value capture for undo support.
public struct FixAttempt: Codable, Sendable {
    /// The stable fix identifier from the flow step node.
    public let fixId: String

    /// When the fix was applied.
    public let timestamp: Date

    /// The setting value before the fix was applied, if applicable.
    public let beforeValue: String?

    /// The setting value after the fix was applied, if applicable.
    public let afterValue: String?

    /// The current result of this fix attempt.
    public var result: FixResult

    /// The flow node params the fix was applied with. Parameterized fixes
    /// (registry writes) need these back to undo, since the fixId alone
    /// does not identify the target.
    public var params: [String: String]?

    /// The flow node the fix was applied from, whose `applied` transition
    /// the session follows once the fix lands. `nil` for a fix applied
    /// outside a flow node.
    public var nodeId: String?

    public init(
        fixId: String,
        timestamp: Date = Date(),
        beforeValue: String? = nil,
        afterValue: String? = nil,
        result: FixResult = .pending,
        params: [String: String]? = nil,
        nodeId: String? = nil
    ) {
        self.fixId = fixId
        self.timestamp = timestamp
        self.beforeValue = beforeValue
        self.afterValue = afterValue
        self.result = result
        self.params = params
        self.nodeId = nodeId
    }
}

/// The lifecycle state of a fix attempt.
public enum FixResult: String, Codable, Sendable {
    /// Fix has been queued but not yet applied.
    case pending

    /// Fix has been applied to the bottle or program settings.
    case applied

    /// Fix was applied and verified to resolve the issue.
    case verified

    /// Fix was applied but did not resolve the issue.
    case failed

    /// Fix was applied and subsequently undone.
    case undone
}
