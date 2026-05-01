//
//  CheckResult.swift
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

/// The result of running a ``TroubleshootingCheck``.
///
/// Normalizes diverse diagnostic outputs into a uniform structure that the
/// flow engine can branch on. The ``outcome`` drives JSON-defined branching,
/// while ``evidence`` carries key-value pairs for UI display via the node's
/// `evidenceMap`.
public struct CheckResult: Sendable, Codable {
    /// The normalized outcome used for flow branching.
    public let outcome: CheckOutcome

    /// Key-value pairs surfaced in the UI via the node's `evidenceMap`.
    public let evidence: [String: String]

    /// Human-readable one-line summary of the result.
    public let summary: String

    /// Optional confidence tier reusing the Phase 5 model.
    public let confidence: ConfidenceTier?

    public init(
        outcome: CheckOutcome,
        evidence: [String: String] = [:],
        summary: String,
        confidence: ConfidenceTier? = nil
    ) {
        self.outcome = outcome
        self.evidence = evidence
        self.summary = summary
        self.confidence = confidence
    }
}

/// Normalized check outcomes for flow branching.
///
/// These values match the keys used in flow definition JSON ``FlowStepNode/on``
/// dictionaries, enabling data-driven branching without hardcoded logic.
public enum CheckOutcome: String, Sendable, Codable {
    /// The check passed -- the tested condition is satisfied.
    case pass

    /// The check failed -- the tested condition is not satisfied.
    case fail

    /// The setting is already configured as needed; no change required.
    case alreadyConfigured = "already_configured"

    /// The check could not determine a result.
    case unknown

    /// The check encountered an error during execution.
    case error
}
