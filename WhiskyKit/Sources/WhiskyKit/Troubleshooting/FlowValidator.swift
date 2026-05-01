//
//  FlowValidator.swift
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
import os.log

/// Validates troubleshooting flow graphs for structural correctness.
///
/// Checks for dangling node references, missing fragments, unreachable nodes,
/// invalid entry points, and potential infinite loops. Run in debug builds at
/// flow load time to catch authoring errors early.
public enum FlowValidator {
    private static let logger = Logger(
        subsystem: "com.isaacmarovitz.Whisky",
        category: "FlowValidator"
    )

    /// The maximum number of automated steps allowed on any path without
    /// encountering a user-interaction node (fix or verify type).
    private static let maxAutomatedSteps = 50

    /// A structural issue found during flow validation.
    public struct ValidationIssue: Sendable {
        /// The flow or fragment ID where the issue was found.
        public let flowId: String

        /// The specific node ID involved, if applicable.
        public let nodeId: String?

        /// A human-readable description of the issue.
        public let message: String

        /// The severity of this issue.
        public let severity: Severity

        public init(flowId: String, nodeId: String? = nil, message: String, severity: Severity) {
            self.flowId = flowId
            self.nodeId = nodeId
            self.message = message
            self.severity = severity
        }
    }

    /// The severity level of a validation issue.
    public enum Severity: String, Sendable {
        /// A potential problem that may cause unexpected behavior.
        case warning
        /// A definite problem that will cause runtime failures.
        case error
    }

    // MARK: - Public API

    /// Validates all flow definitions and fragments for structural correctness.
    ///
    /// Checks performed:
    /// - Every `on` target node ID resolves within the same flow or any fragment
    /// - Every `fragmentRef` resolves to a fragment key
    /// - Every `entryNodeId` exists in the flow's nodes
    /// - No unreachable nodes (BFS from entry node)
    /// - No path longer than 50 automated steps without user interaction
    ///
    /// - Parameters:
    ///   - flows: Flow definitions keyed by category ID.
    ///   - fragments: Fragment definitions keyed by fragment name.
    /// - Returns: An array of validation issues found, empty if all flows are valid.
    public static func validate(
        flows: [String: FlowDefinition],
        fragments: [String: FlowDefinition]
    ) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        // Build a combined set of all known node IDs across all flows and fragments
        var allNodeIds: Set<String> = []
        for flow in flows.values {
            allNodeIds.formUnion(flow.nodes.keys)
        }
        for fragment in fragments.values {
            allNodeIds.formUnion(fragment.nodes.keys)
        }

        // Validate each flow
        for (categoryId, flow) in flows {
            issues.append(contentsOf: validateFlow(
                flow: flow,
                flowId: categoryId,
                allNodeIds: allNodeIds,
                fragmentKeys: Set(fragments.keys)
            ))
        }

        // Validate each fragment
        for (fragmentName, fragment) in fragments {
            issues.append(contentsOf: validateFlow(
                flow: fragment,
                flowId: fragmentName,
                allNodeIds: allNodeIds,
                fragmentKeys: Set(fragments.keys)
            ))
        }

        if !issues.isEmpty {
            let errors = issues.filter { $0.severity == .error }.count
            let warnings = issues.filter { $0.severity == .warning }.count
            logger.warning("Flow validation found \(errors) errors and \(warnings) warnings")
        }

        return issues
    }

    /// Validates flows and asserts on errors in debug builds. Logs warnings in release builds.
    ///
    /// Call after loading flows to catch authoring errors early during development.
    ///
    /// - Parameters:
    ///   - flows: Flow definitions keyed by category ID.
    ///   - fragments: Fragment definitions keyed by fragment name.
    public static func validateAndReport(
        flows: [String: FlowDefinition],
        fragments: [String: FlowDefinition]
    ) {
        let issues = validate(flows: flows, fragments: fragments)

        #if DEBUG
        let errors = issues.filter { $0.severity == .error }
        if !errors.isEmpty {
            let descriptions = errors.map { "[\($0.flowId)] \($0.nodeId ?? "?"): \($0.message)" }
            assertionFailure("Flow validation errors:\n\(descriptions.joined(separator: "\n"))")
        }
        #else
        for issue in issues {
            switch issue.severity {
            case .error:
                logger.error("Flow validation error in \(issue.flowId): \(issue.message)")
            case .warning:
                logger.warning("Flow validation warning in \(issue.flowId): \(issue.message)")
            }
        }
        #endif
    }

    // MARK: - Private Validation

    // swiftlint:disable:next function_body_length
    private static func validateFlow(
        flow: FlowDefinition,
        flowId: String,
        allNodeIds: Set<String>,
        fragmentKeys: Set<String>
    ) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        // Check entry node exists
        if flow.nodes[flow.entryNodeId] == nil {
            issues.append(ValidationIssue(
                flowId: flowId,
                nodeId: flow.entryNodeId,
                message: "Entry node ID '\(flow.entryNodeId)' not found in flow nodes",
                severity: .error
            ))
        }

        // Check each node
        for (nodeId, node) in flow.nodes {
            // Check on-map targets resolve
            if let onMap = node.on {
                for (outcome, targetId) in onMap where !allNodeIds.contains(targetId) {
                    issues.append(ValidationIssue(
                        flowId: flowId,
                        nodeId: nodeId,
                        message: "Target node '\(targetId)' for outcome '\(outcome)'"
                            + " not found in any flow or fragment",
                        severity: .error
                    ))
                }
            }

            // Check fragment references resolve
            if let fragmentRef = node.fragmentRef {
                if !fragmentKeys.contains(fragmentRef) {
                    issues.append(ValidationIssue(
                        flowId: flowId,
                        nodeId: nodeId,
                        message: "Fragment reference '\(fragmentRef)' not found in loaded fragments",
                        severity: .error
                    ))
                }
            }
        }

        // Check for unreachable nodes (BFS from entry)
        let reachable = findReachableNodes(from: flow.entryNodeId, in: flow)
        let unreachableNodes = Set(flow.nodes.keys).subtracting(reachable)
        for nodeId in unreachableNodes.sorted() {
            issues.append(ValidationIssue(
                flowId: flowId,
                nodeId: nodeId,
                message: "Node '\(nodeId)' is unreachable from entry node '\(flow.entryNodeId)'",
                severity: .warning
            ))
        }

        // Check for long automated paths without user interaction
        if flow.nodes[flow.entryNodeId] != nil {
            let maxDepth = findMaxAutomatedDepth(from: flow.entryNodeId, in: flow)
            if maxDepth > maxAutomatedSteps {
                issues.append(ValidationIssue(
                    flowId: flowId,
                    message: "Flow has a path with \(maxDepth) automated steps"
                        + " without user interaction (limit: \(maxAutomatedSteps))",
                    severity: .warning
                ))
            }
        }

        return issues
    }

    /// Finds all nodes reachable from a starting node via BFS.
    private static func findReachableNodes(from startId: String, in flow: FlowDefinition) -> Set<String> {
        var visited: Set<String> = []
        var queue: [String] = [startId]

        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard !visited.contains(current) else { continue }
            visited.insert(current)

            guard let node = flow.nodes[current] else { continue }
            if let onMap = node.on {
                for targetId in onMap.values where flow.nodes[targetId] != nil {
                    if !visited.contains(targetId) {
                        queue.append(targetId)
                    }
                }
            }
        }

        return visited
    }

    /// Finds the maximum depth of automated steps on any path from the start node
    /// without encountering a user-interaction node (fix or verify type).
    /// Uses iterative DFS with cycle detection.
    private static func findMaxAutomatedDepth(from startId: String, in flow: FlowDefinition) -> Int {
        var maxDepth = 0

        // Stack entries: (nodeId, currentDepth, visited set for this path)
        // swiftlint:disable:next large_tuple
        var stack: [(String, Int, Set<String>)] = [(startId, 0, [])]

        while !stack.isEmpty {
            let (nodeId, depth, visited) = stack.removeLast()

            guard !visited.contains(nodeId) else { continue }
            guard let node = flow.nodes[nodeId] else { continue }

            var currentVisited = visited
            currentVisited.insert(nodeId)

            // User-interaction nodes reset the counter
            let isUserInteraction = node.type == .fix || node.type == .verify
            let newDepth = isUserInteraction ? 0 : depth + 1

            maxDepth = max(maxDepth, newDepth)

            if let onMap = node.on {
                for targetId in onMap.values where flow.nodes[targetId] != nil {
                    stack.append((targetId, newDepth, currentVisited))
                }
            }
        }

        return maxDepth
    }
}
