//
//  TroubleshootingFlowValidationTests.swift
//  WhiskyKitTests
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

@testable import WhiskyKit
import XCTest

/// The shipped flow definitions against the engine and the checks they
/// call: transitions resolve, check params are ones the checks read, every
/// outcome has somewhere to go, and branch keys name launchers.
final class TroubleshootingFlowValidationTests: XCTestCase {
    func testBranchKeysAreLauncherTypeRawValues() {
        let launcherValues = Set(LauncherType.allCases.map(\.rawValue))
        let definitions = Array(FlowLoader.loadAllFlows().values) + Array(FlowLoader.loadFragments().values)
        var branchCount = 0
        for definition in definitions {
            for node in definition.nodes.values where node.type == .branch {
                branchCount += 1
                let keys = Set((node.on ?? [:]).keys).subtracting(["default"])
                XCTAssertTrue(
                    keys.isSubset(of: launcherValues),
                    "\(definition.categoryId)/\(node.id) keys \(keys.subtracting(launcherValues)) name no launcher"
                )
            }
        }
        XCTAssertEqual(branchCount, 2, "both launcher flows branch with a branch node")
    }

    // MARK: - Flow definitions

    func testShippedFlowsHaveNoStructuralErrors() {
        let issues = FlowValidator.validate(flows: FlowLoader.loadAllFlows(), fragments: FlowLoader.loadFragments())

        XCTAssertEqual(issues.filter { $0.severity == .error }.map(\.message), [], "every on[...] target resolves")
    }

    func testShippedFlowCheckNodesMatchTheirChecks() {
        let issues = FlowValidator.checkIssues(
            flows: FlowLoader.loadAllFlows(),
            fragments: FlowLoader.loadFragments(),
            registry: CheckRegistry()
        )

        XCTAssertEqual(issues.map { "\($0.flowId)/\($0.nodeId ?? "?"): \($0.message)" }, [])
    }

    func testEveryBuiltInCheckDeclaresItsSignature() {
        let registry = CheckRegistry()
        let checkIds = Set(
            (Array(FlowLoader.loadAllFlows().values) + Array(FlowLoader.loadFragments().values))
                .flatMap { $0.nodes.values.compactMap(\.checkId) }
        )
        XCTAssertFalse(checkIds.isEmpty)
        for checkId in checkIds {
            XCTAssertNotNil(registry.check(for: checkId)?.signature, "\(checkId) declares no signature")
        }
    }

    func testCheckValidationCatchesParamAndRoutingMistakes() {
        let nodes: [String: FlowStepNode] = [
            "misnamed": FlowStepNode(
                id: "misnamed", type: .check, phase: .checks, checkId: "dxvk.settings_check",
                params: ["check": "async_enabled"],
                on: ["already_configured": "end", "fail": "end", "error": "end"]
            ),
            "unrouted": FlowStepNode(
                id: "unrouted", type: .check, phase: .checks, checkId: "winetricks.verb_check",
                params: ["verbs": "d3dx9"], on: ["fail": "end"]
            ),
            "unregistered": FlowStepNode(id: "unregistered", type: .check, phase: .checks, checkId: "no.such_check"),
            "branch": FlowStepNode(id: "branch", type: .branch, phase: .checks, on: ["Steam": "end"]),
            "end": FlowStepNode(id: "end", type: .info, phase: .checks)
        ]
        let flow = FlowDefinition(version: 1, categoryId: "test", nodes: nodes, entryNodeId: "end")

        let issues = FlowValidator.checkIssues(flows: ["test": flow], fragments: [:], registry: CheckRegistry())
        let messages = issues.map { "\($0.nodeId ?? "?"): \($0.message)" }

        XCTAssertTrue(
            messages.contains("misnamed: Check 'dxvk.settings_check' does not read param 'check'"),
            "\(messages)"
        )
        XCTAssertTrue(messages.contains("misnamed: Check 'dxvk.settings_check' needs param 'setting'"), "\(messages)")
        XCTAssertTrue(messages.contains {
            $0.hasPrefix("unrouted:") && $0.contains("already_configured")
        }, "\(messages)")
        XCTAssertTrue(messages.contains { $0.hasPrefix("unregistered:") }, "\(messages)")
        XCTAssertTrue(messages.contains { $0.hasPrefix("branch:") && $0.contains("default") }, "\(messages)")
    }

    /// Node lookup tries the session's flow before the fragments, so a
    /// fragment node sharing an ID with a flow node is unreachable: the
    /// enhanced diagnostics' findings once led to every flow's "Problem
    /// resolved" node that way.
    func testFragmentNodeIDsDoNotShadowFlowNodes() {
        let flowNodeIds = Set(FlowLoader.loadAllFlows().values.flatMap(\.nodes.keys))
        for (name, fragment) in FlowLoader.loadFragments() {
            let shared = flowNodeIds.intersection(fragment.nodes.keys)
            XCTAssertTrue(shared.isEmpty, "\(name) shares node IDs with a flow: \(shared.sorted())")
        }
    }
}
