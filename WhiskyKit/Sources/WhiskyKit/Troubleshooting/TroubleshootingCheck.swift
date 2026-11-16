//
//  TroubleshootingCheck.swift
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

/// A diagnostic check that can be executed by the troubleshooting flow engine.
///
/// Each implementation wraps an existing diagnostic primitive (e.g., ``CrashClassifier``,
/// audio probes, graphics backend resolver) and returns a normalized ``CheckResult``.
/// Implementations are registered in a check registry by their stable ``checkId``.
///
/// ## Implementing a Check
///
/// ```swift
/// public struct MyCheck: TroubleshootingCheck {
///     public let checkId = "my.check_id"
///
///     public func run(
///         params: [String: String],
///         context: CheckContext
///     ) async -> CheckResult {
///         // Wrap existing diagnostic logic
///         let result = existingDiagnostic()
///         return CheckResult(
///             outcome: result.isGood ? .pass : .fail,
///             evidence: ["key": "value"],
///             summary: "Check completed"
///         )
///     }
/// }
/// ```
public protocol TroubleshootingCheck: Sendable {
    /// Stable identifier matching the `checkId` referenced in flow definition JSON.
    var checkId: String { get }

    /// The params the check reads and the outcomes it can return.
    ///
    /// ``FlowValidator/checkIssues(flows:fragments:registry:)`` holds every
    /// check node in the flow definitions to this, so a misspelled param
    /// or an outcome with nowhere to go fails the tests instead of leaving
    /// the wizard on a dead end. `nil` declares nothing and skips that
    /// validation.
    var signature: CheckSignature? { get }

    /// Runs the check with the given parameters and context.
    ///
    /// - Parameters:
    ///   - params: Key-value parameters from the flow step node.
    ///   - context: Bottle, program, preflight data, and session state.
    /// - Returns: A normalized ``CheckResult`` for flow branching.
    func run(params: [String: String], context: CheckContext) async -> CheckResult
}

public extension TroubleshootingCheck {
    /// Declares nothing, so flows referencing the check are not validated
    /// against it.
    var signature: CheckSignature? {
        nil
    }
}

/// What a ``TroubleshootingCheck`` accepts from a flow node and what it can
/// return to it.
public struct CheckSignature: Sendable, Equatable {
    /// Every param key the check reads.
    public let acceptedParams: Set<String>

    /// The params the check cannot run without.
    public let requiredParams: Set<String>

    /// Every outcome ``TroubleshootingCheck/run(params:context:)`` can
    /// return with valid params.
    public let outcomes: Set<CheckOutcome>

    public init(
        acceptedParams: Set<String> = [],
        requiredParams: Set<String> = [],
        outcomes: Set<CheckOutcome>
    ) {
        self.acceptedParams = acceptedParams.union(requiredParams)
        self.requiredParams = requiredParams
        self.outcomes = outcomes
    }
}

extension String {
    /// The entries of a comma-separated flow param (`"msync,esync"`), trimmed,
    /// with empty entries dropped.
    var flowParamList: [String] {
        split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
