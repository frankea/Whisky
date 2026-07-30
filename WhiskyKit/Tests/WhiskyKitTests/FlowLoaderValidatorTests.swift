//
//  FlowLoaderValidatorTests.swift
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

/// Integration tests over the flow JSON actually shipped in the package
/// resources: every flow must load, validate, and reference only checks
/// that exist. These are the tests that catch a broken flow file at CI
/// time instead of at the user's first troubleshooting attempt.
final class FlowLoaderValidatorTests: XCTestCase {
    // MARK: - Bundled resources

    func testIndexLoadsAndCoversEveryCategory() throws {
        let index = try XCTUnwrap(FlowLoader.loadIndex())
        XCTAssertFalse(index.categories.isEmpty)

        // Every SymptomCategory's flow file must be present in the index so
        // selecting any symptom in the UI reaches a real flow — except .other,
        // which by design has no flow: selecting it escalates directly to the
        // export fragment (the engine's no-flow path).
        let indexedFiles = Set(index.categories.map(\.flowFile))
        for category in SymptomCategory.allCases where category != .other {
            XCTAssertTrue(
                indexedFiles.contains(category.flowFileName),
                "index.json is missing \(category.flowFileName) for category \(category)"
            )
        }
        XCTAssertFalse(
            indexedFiles.contains(SymptomCategory.other.flowFileName),
            ".other gained a flow file — update the engine's no-flow escalation expectations"
        )
    }

    func testAllIndexedFlowsLoad() throws {
        let index = try XCTUnwrap(FlowLoader.loadIndex())
        let flows = FlowLoader.loadAllFlows()

        XCTAssertEqual(
            flows.count, index.categories.count,
            "every category in index.json must load; a silently skipped flow means a dead symptom path"
        )
    }

    func testFragmentsLoad() {
        let fragments = FlowLoader.loadFragments()

        // The engine's escalation path depends on export-escalation existing.
        XCTAssertNotNil(fragments["export-escalation"])
        XCTAssertNotNil(fragments["dependency-install"])
    }

    func testBundledFlowsPassValidationWithoutErrors() {
        let flows = FlowLoader.loadAllFlows()
        let fragments = FlowLoader.loadFragments()
        XCTAssertFalse(flows.isEmpty)

        let issues = FlowValidator.validate(flows: flows, fragments: fragments)
        let errors = issues.filter { $0.severity == .error }

        XCTAssertTrue(
            errors.isEmpty,
            "bundled flows have validation errors: \(errors.map { "\($0.flowId)/\($0.nodeId ?? "-"): \($0.message)" })"
        )
    }

    func testEveryReferencedCheckIdHasAnImplementation() {
        // Collect the checkIds the shipped flows actually reference…
        let flows = FlowLoader.loadAllFlows()
        let fragments = FlowLoader.loadFragments()
        var referenced: Set<String> = []
        for flow in flows.values.map(\.nodes) + fragments.values.map(\.nodes) {
            for node in flow.values {
                if let checkId = node.checkId {
                    referenced.insert(checkId)
                }
            }
        }
        XCTAssertFalse(referenced.isEmpty)

        // …and compare against the concrete implementations the registry
        // registers, without running any of them (several probe hardware).
        let implemented: Set<String> = Set(
            ([
                CrashLogCheck(), GraphicsBackendCheck(), DXVKSettingsCheck(),
                AudioDriverCheck(), AudioDeviceCheck(), AudioTestCheck(),
                DependencyCheck(), WinetricksVerbCheck(),
                LauncherTypeCheck(), ProcessRunningCheck(),
                EnvironmentCheck(), RegistryValueCheck(),
                GameConfigAvailableCheck(), SettingValueCheck(), DiagnosticsEnhanceCheck()
            ] as [any TroubleshootingCheck]).map(\.checkId)
        )

        let missing = referenced.subtracting(implemented)
        XCTAssertTrue(
            missing.isEmpty,
            "flow JSON references check IDs with no implementation: \(missing.sorted())"
        )
    }

    // MARK: - Validator failure detection

    private func makeNode(
        id: String,
        type: NodeType = .check,
        checkId: String? = "graphics.backend_is",
        on: [String: String]? = nil // swiftlint:disable:this identifier_name
    ) -> FlowStepNode {
        FlowStepNode(id: id, type: type, phase: .checks, checkId: checkId, on: on)
    }

    func testValidatorFlagsDanglingNodeReference() {
        let flow = FlowDefinition(
            version: 1,
            categoryId: "test",
            nodes: ["start": makeNode(id: "start", on: ["pass": "does-not-exist"])],
            entryNodeId: "start"
        )

        let issues = FlowValidator.validate(flows: ["test": flow], fragments: [:])

        XCTAssertTrue(
            issues.contains { $0.severity == .error },
            "a branch target that resolves nowhere must be a validation error, got: \(issues)"
        )
    }

    func testValidatorFlagsMissingEntryNode() {
        let flow = FlowDefinition(
            version: 1,
            categoryId: "test",
            nodes: ["start": makeNode(id: "start")],
            entryNodeId: "nope"
        )

        let issues = FlowValidator.validate(flows: ["test": flow], fragments: [:])

        XCTAssertTrue(issues.contains { $0.severity == .error })
    }

    func testValidatorAcceptsWellFormedFlow() {
        let flow = FlowDefinition(
            version: 1,
            categoryId: "test",
            nodes: [
                "start": makeNode(id: "start", on: ["pass": "done", "fail": "done"]),
                "done": makeNode(id: "done", type: .info, checkId: nil)
            ],
            entryNodeId: "start"
        )

        let issues = FlowValidator.validate(flows: ["test": flow], fragments: [:])

        XCTAssertTrue(
            issues.filter { $0.severity == .error }.isEmpty,
            "well-formed flow should have no errors, got: \(issues)"
        )
    }
}
