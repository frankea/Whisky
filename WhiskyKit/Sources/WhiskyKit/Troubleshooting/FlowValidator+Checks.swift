//
//  FlowValidator+Checks.swift
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

public extension FlowValidator {
    /// Validates every check and branch node against what the engine will
    /// do with it.
    ///
    /// Checks performed:
    /// - Every `checkId` is registered
    /// - Every param a check node passes is one its check reads, and every
    ///   param the check needs is there (``CheckSignature``)
    /// - Every outcome the check can return has a transition, or the node
    ///   has a `default`, so the wizard never stops on a finished check
    /// - Every branch node has a `default` for the launchers it doesn't name
    ///
    /// Checks that declare no ``TroubleshootingCheck/signature`` are only
    /// checked for registration.
    ///
    /// - Parameters:
    ///   - flows: Flow definitions keyed by category ID.
    ///   - fragments: Fragment definitions keyed by fragment name.
    ///   - registry: The registry the engine runs checks from.
    /// - Returns: The issues found, all errors; empty if every node is valid.
    static func checkIssues(
        flows: [String: FlowDefinition],
        fragments: [String: FlowDefinition],
        registry: CheckRegistry
    ) -> [ValidationIssue] {
        let definitions = flows.merging(fragments) { flow, _ in flow }
        var issues: [ValidationIssue] = []
        for flowId in definitions.keys.sorted() {
            guard let definition = definitions[flowId] else { continue }
            for nodeId in definition.nodes.keys.sorted() {
                guard let node = definition.nodes[nodeId] else { continue }
                issues += nodeIssues(node, flowId: flowId, registry: registry)
            }
        }
        return issues
    }

    private static func nodeIssues(
        _ node: FlowStepNode,
        flowId: String,
        registry: CheckRegistry
    ) -> [ValidationIssue] {
        func issue(_ message: String) -> ValidationIssue {
            ValidationIssue(flowId: flowId, nodeId: node.id, message: message, severity: .error)
        }
        let transitions = node.on ?? [:]

        if node.type == .branch, transitions["default"] == nil {
            return [issue("Branch node has no 'default' transition")]
        }
        guard let checkId = node.checkId else {
            return []
        }
        guard let check = registry.check(for: checkId) else {
            return [issue("Check ID '\(checkId)' is not registered")]
        }
        guard let signature = check.signature else {
            return []
        }

        var issues: [ValidationIssue] = []
        let params = Set((node.params ?? [:]).keys)
        for param in params.subtracting(signature.acceptedParams).sorted() {
            issues.append(issue("Check '\(checkId)' does not read param '\(param)'"))
        }
        for param in signature.requiredParams.subtracting(params).sorted() {
            issues.append(issue("Check '\(checkId)' needs param '\(param)'"))
        }
        if transitions["default"] == nil {
            let unrouted = signature.outcomes.filter { transitions[$0.rawValue] == nil }
            for outcome in unrouted.map(\.rawValue).sorted() {
                issues.append(issue("Outcome '\(outcome)' of check '\(checkId)' has no transition"))
            }
        }
        return issues
    }
}
