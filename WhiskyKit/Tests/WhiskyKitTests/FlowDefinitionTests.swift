//
//  FlowDefinitionTests.swift
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

final class FlowDefinitionTests: XCTestCase {
    // MARK: - Decoding

    func testDecodesMinimalFlow() throws {
        let json = """
        {
            "version": 1,
            "categoryId": "graphics",
            "entryNodeId": "start",
            "nodes": {
                "start": {
                    "id": "start",
                    "type": "check",
                    "phase": "checks",
                    "checkId": "graphics.backend_is",
                    "params": {"expected": "dxvk"},
                    "on": {"pass": "done", "fail": "fix-backend"}
                }
            }
        }
        """
        let flow = try JSONDecoder().decode(FlowDefinition.self, from: Data(json.utf8))

        XCTAssertEqual(flow.version, 1)
        XCTAssertEqual(flow.categoryId, "graphics")
        XCTAssertEqual(flow.entryNodeId, "start")
        let node = try XCTUnwrap(flow.nodes["start"])
        XCTAssertEqual(node.type, .check)
        XCTAssertEqual(node.phase, .checks)
        XCTAssertEqual(node.checkId, "graphics.backend_is")
        XCTAssertEqual(node.params?["expected"], "dxvk")
        XCTAssertEqual(node.on?["pass"], "done")
        // Absent optionals decode to nil rather than failing the parent decode
        XCTAssertNil(node.title)
        XCTAssertNil(node.fixId)
        XCTAssertNil(node.fixPreview)
        XCTAssertNil(node.fragmentRef)
    }

    func testDecodesFixNodeWithPreview() throws {
        let json = """
        {
            "id": "fix-backend",
            "type": "fix",
            "phase": "fix",
            "title": "Switch to DXVK",
            "fixId": "graphics.set_backend_dxvk",
            "isReversible": true,
            "requiresConfirmation": false,
            "fixPreview": {
                "settingName": "Graphics Backend",
                "currentValueKey": "current",
                "newValue": "dxvk",
                "scope": "bottle"
            }
        }
        """
        let node = try JSONDecoder().decode(FlowStepNode.self, from: Data(json.utf8))

        XCTAssertEqual(node.type, .fix)
        XCTAssertEqual(node.fixId, "graphics.set_backend_dxvk")
        XCTAssertEqual(node.isReversible, true)
        XCTAssertEqual(node.requiresConfirmation, false)
        let preview = try XCTUnwrap(node.fixPreview)
        XCTAssertEqual(preview.settingName, "Graphics Backend")
        XCTAssertEqual(preview.currentValueKey, "current")
        XCTAssertEqual(preview.newValue, "dxvk")
        XCTAssertEqual(preview.scope, "bottle")
    }

    func testUnknownNodeTypeFailsDecode() {
        let json = """
        {"id": "x", "type": "teleport", "phase": "checks"}
        """
        XCTAssertThrowsError(try JSONDecoder().decode(FlowStepNode.self, from: Data(json.utf8)))
    }

    // MARK: - CheckResult round trip

    func testCheckResultCodableRoundTrip() throws {
        let result = CheckResult(
            outcome: .alreadyConfigured,
            evidence: ["current": "dxvk"],
            summary: "Already set",
            confidence: .high
        )
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(CheckResult.self, from: data)

        XCTAssertEqual(decoded.outcome, .alreadyConfigured)
        XCTAssertEqual(decoded.evidence, ["current": "dxvk"])
        XCTAssertEqual(decoded.summary, "Already set")
        XCTAssertEqual(decoded.confidence, .high)
    }

    func testCheckOutcomeRawValuesMatchFlowJSONKeys() {
        // Branching maps in flow JSON key on these exact strings; changing a
        // raw value silently breaks every "on" table that uses it.
        XCTAssertEqual(CheckOutcome.pass.rawValue, "pass")
        XCTAssertEqual(CheckOutcome.fail.rawValue, "fail")
        XCTAssertEqual(CheckOutcome.alreadyConfigured.rawValue, "already_configured")
        XCTAssertEqual(CheckOutcome.unknown.rawValue, "unknown")
        XCTAssertEqual(CheckOutcome.error.rawValue, "error")
    }

    // MARK: - Phase mapping

    func testSessionPhaseFromFlowPhaseCoversAllCases() {
        XCTAssertEqual(TroubleshootingSession.SessionPhase(flowPhase: .symptom), .symptom)
        XCTAssertEqual(TroubleshootingSession.SessionPhase(flowPhase: .checks), .checks)
        XCTAssertEqual(TroubleshootingSession.SessionPhase(flowPhase: .fix), .fix)
        XCTAssertEqual(TroubleshootingSession.SessionPhase(flowPhase: .verify), .verify)
        XCTAssertEqual(TroubleshootingSession.SessionPhase(flowPhase: .export), .export)
    }

    // MARK: - SymptomCategory

    func testEveryCategoryHasAJSONFlowFileName() {
        for category in SymptomCategory.allCases {
            XCTAssertTrue(
                category.flowFileName.hasSuffix(".json"),
                "\(category) flow file name should end in .json"
            )
            XCTAssertFalse(category.displayTitle.isEmpty)
        }
    }
}
