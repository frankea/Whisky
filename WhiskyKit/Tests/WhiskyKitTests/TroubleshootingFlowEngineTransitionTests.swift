//
//  TroubleshootingFlowEngineTransitionTests.swift
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

/// Transitions the wizard drives by hand: Continue on an info node, Skip's
/// fallback to it, and the hand-off to the escalation fragment.
@MainActor
final class TroubleshootingFlowEngineTransitionTests: XCTestCase {
    private func infoNode(
        _ nodeId: String,
        phase: FlowPhase = .checks,
        transitions: [String: String]? = nil,
        fragmentRef: String? = nil
    ) -> FlowStepNode {
        FlowStepNode(
            id: nodeId, type: .info, phase: phase, title: "Info \(nodeId)", on: transitions, fragmentRef: fragmentRef
        )
    }

    private func makeEngine(
        nodes: [String: FlowStepNode],
        fragments: [String: FlowDefinition] = [:]
    ) -> TroubleshootingFlowEngine {
        let flow = FlowDefinition(version: 1, categoryId: "graphics", nodes: nodes, entryNodeId: "start")
        var session = TroubleshootingSession(bottleURL: URL(filePath: "/tmp/engine-transition-test-bottle"))
        session.currentFlowCategoryId = "graphics"
        return TroubleshootingFlowEngine(
            flowDefinitions: ["graphics": flow],
            fragments: fragments,
            checkRegistry: CheckRegistry(),
            sessionStore: SpySessionStore(),
            session: session
        )
    }

    func testContinueFollowsTheInfoNodeTransition() {
        let engine = makeEngine(nodes: [
            "start": infoNode("start", transitions: ["continue": "next"]),
            "next": infoNode("next")
        ])

        engine.navigateToNode("start")
        XCTAssertTrue(engine.canContinue)

        engine.continueStep()

        XCTAssertEqual(engine.currentNode?.id, "next")
        XCTAssertFalse(engine.canContinue)
    }

    func testSkipFallsBackToTheContinueTransition() {
        let engine = makeEngine(nodes: [
            "start": infoNode("start", transitions: ["continue": "next"]),
            "next": infoNode("next")
        ])

        engine.navigateToNode("start")
        engine.skipStep()

        XCTAssertEqual(engine.currentNode?.id, "next")
    }

    func testNodeReferencingTheEscalationFragmentEscalates() {
        let fragment = FlowDefinition(
            version: 1,
            categoryId: "export-escalation",
            nodes: ["export-start": infoNode("export-start", phase: .export)],
            entryNodeId: "export-start"
        )
        let engine = makeEngine(
            nodes: [
                "start": infoNode("start", transitions: ["continue": "escalate"]),
                "escalate": infoNode("escalate", phase: .export, fragmentRef: "export-escalation")
            ],
            fragments: ["export-escalation": fragment]
        )

        engine.navigateToNode("start")
        engine.continueStep()

        XCTAssertEqual(engine.session.phase, .escalation)
        XCTAssertEqual(engine.currentNode?.id, "export-start")
    }
}
