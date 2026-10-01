//
//  BackendFixCoherenceTests.swift
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

/// The backend fixes must do what their cards say: the wizard's "Switch to
/// DXVK" switches to DXVK, and the crash diagnosis card that resets to
/// Recommended says so and stays out of the way on a bottle already there.
@MainActor
final class BackendFixCoherenceTests: XCTestCase {
    private var tempDir: URL!
    private var bottle: Bottle!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        bottle = Bottle(bottleUrl: tempDir, inFlight: false, isAvailable: true)
    }

    override func tearDownWithError() throws {
        bottle = nil
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        tempDir = nil
    }

    // MARK: - Guided Troubleshooting

    private func fixNode(flow fileName: String, node nodeId: String) throws -> FlowStepNode {
        let flow = try XCTUnwrap(FlowLoader.loadFlow(fileName: fileName))
        return try XCTUnwrap(flow.nodes[nodeId], "\(fileName) lost \(nodeId)")
    }

    /// The path the wizard takes on a Recommended bottle whose resolved
    /// backend is not DXVK: the card offers DXVK, previews DXVK, and applying
    /// it leaves the bottle on DXVK.
    private func assertSwitchesRecommendedBottleToDXVK(
        flow fileName: String, node nodeId: String, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let node = try fixNode(flow: fileName, node: nodeId)
        XCTAssertEqual(node.fixId, "switch-backend", file: file, line: line)
        XCTAssertEqual(node.title, "Switch to DXVK", file: file, line: line)
        bottle.settings.graphicsBackend = .recommended
        let params = node.params ?? [:]

        let preview = try XCTUnwrap(FixApplicator.preview(
            fixId: "switch-backend", params: params, bottle: bottle, program: nil
        ))
        XCTAssertEqual(preview.currentValue, GraphicsBackend.recommended.displayName, file: file, line: line)
        XCTAssertEqual(
            preview.newValue, GraphicsBackend.dxvk.displayName,
            "preview must not read Recommended to Recommended", file: file, line: line
        )

        let attempt = FixApplicator.apply(fixId: "switch-backend", params: params, bottle: bottle, program: nil)
        XCTAssertEqual(bottle.settings.graphicsBackend, .dxvk, file: file, line: line)
        XCTAssertEqual(attempt.beforeValue, "recommended", file: file, line: line)
        XCTAssertEqual(attempt.afterValue, "dxvk", file: file, line: line)

        XCTAssertTrue(FixApplicator.undo(attempt: attempt, bottle: bottle, program: nil), file: file, line: line)
        XCTAssertEqual(bottle.settings.graphicsBackend, .recommended, file: file, line: line)
    }

    func testGraphicsFlowSwitchToDXVKSetsDXVK() throws {
        try assertSwitchesRecommendedBottleToDXVK(flow: "graphics", node: "fix_enable_dxvk")
    }

    func testLaunchCrashFlowSwitchToDXVKSetsDXVK() throws {
        try assertSwitchesRecommendedBottleToDXVK(flow: "launch-crash", node: "fix_switch_backend")
    }

    func testValidatorRejectsSwitchBackendWithoutTargetBackend() {
        func flow(params: [String: String]?) -> FlowDefinition {
            FlowDefinition(
                version: 1,
                categoryId: "test",
                nodes: [
                    "start": FlowStepNode(
                        id: "start", type: .fix, phase: .fix, params: params,
                        on: ["applied": "start"], fixId: "switch-backend"
                    )
                ],
                entryNodeId: "start"
            )
        }

        for params in [nil, ["backend": "not-a-backend"]] as [[String: String]?] {
            let issues = FlowValidator.validate(flows: ["test": flow(params: params)], fragments: [:])
            XCTAssertTrue(
                issues.contains { $0.severity == .error && $0.message.contains("backend") },
                "switch-backend with params \(String(describing: params)) must fail validation, got: \(issues)"
            )
        }

        let valid = FlowValidator.validate(flows: ["test": flow(params: ["backend": "dxvk"])], fragments: [:])
        XCTAssertFalse(valid.contains { $0.message.contains("backend") }, "got: \(valid)")
    }

    // MARK: - Crash diagnosis card

    private func switchBackendRemediation() throws -> RemediationAction {
        let (_, remediations) = PatternLoader.loadDefaults()
        return try XCTUnwrap(remediations["switch-backend"])
    }

    func testSwitchBackendRemediationSaysItResetsToRecommended() throws {
        let action = try switchBackendRemediation()

        XCTAssertEqual(action.targetBackend, .recommended)
        XCTAssertTrue(action.title.contains("Recommended"), action.title)
        XCTAssertTrue(action.whatWillChange.contains("Recommended"), action.whatWillChange)
        XCTAssertFalse(action.description.contains("DXVK"), action.description)
    }

    func testSwitchBackendRemediationIsANoOpOnRecommendedBottle() throws {
        let action = try switchBackendRemediation()

        bottle.settings.graphicsBackend = .recommended
        XCTAssertFalse(action.wouldChange(bottle.settings), "a reset to Recommended changes nothing here")

        for backend in [GraphicsBackend.dxvk, .dxmt, .d3dMetal, .wined3d] {
            bottle.settings.graphicsBackend = backend
            XCTAssertTrue(action.wouldChange(bottle.settings), "\(backend) should be offered the reset")
        }
    }

    func testNonBackendRemediationsAlwaysApply() {
        let (_, remediations) = PatternLoader.loadDefaults()
        let others = remediations.values.filter { $0.actionType != .switchBackend }
        XCTAssertFalse(others.isEmpty)
        for action in others {
            XCTAssertNil(action.targetBackend, action.id)
            XCTAssertTrue(action.wouldChange(bottle.settings), action.id)
        }
    }
}
