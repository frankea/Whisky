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

    /// Runs the check with the given parameters and context.
    ///
    /// - Parameters:
    ///   - params: Key-value parameters from the flow step node.
    ///   - context: Bottle, program, preflight data, and session state.
    /// - Returns: A normalized ``CheckResult`` for flow branching.
    func run(params: [String: String], context: CheckContext) async -> CheckResult
}
