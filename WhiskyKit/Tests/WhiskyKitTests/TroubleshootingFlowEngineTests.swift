//
//  TroubleshootingFlowEngineTests.swift
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

/// In-memory session store so engine tests observe auto-save and completion
/// behavior without touching the filesystem.
final class SpySessionStore: TroubleshootingSessionStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var savedSessions: [TroubleshootingSession] = []
    private var completedSessions: [TroubleshootingSession] = []

    var saveCount: Int {
        lock.withLock { savedSessions.count }
    }

    var completed: [TroubleshootingSession] {
        lock.withLock { completedSessions }
    }

    func save(_ session: TroubleshootingSession) {
        lock.withLock { savedSessions.append(session) }
    }

    func completeSession(_ session: TroubleshootingSession) {
        lock.withLock { completedSessions.append(session) }
    }
}

@MainActor
final class TroubleshootingFlowEngineTests: XCTestCase {
    // MARK: - Fixtures

    private func checkNode(
        _ id: String,
        outcome: String = "pass",
        on: [String: String] // swiftlint:disable:this identifier_name
    ) -> FlowStepNode {
        FlowStepNode(
            id: id, type: .check, phase: .checks,
            checkId: "stub.outcome", params: ["outcome": outcome], on: on
        )
    }

    private func infoNode(_ id: String, on: [String: String]? = nil) -> FlowStepNode {
        // swiftlint:disable:previous identifier_name
        FlowStepNode(id: id, type: .info, phase: .checks, title: "Info \(id)", on: on)
    }

    /// The "graphics" key matches SymptomCategory.graphics.flowFileName minus
    /// its .json suffix, which is how the engine derives flow lookup keys.
    private func makeEngine(
        nodes: [String: FlowStepNode],
        entry: String = "start",
        fragments: [String: FlowDefinition] = [:],
        session: TroubleshootingSession? = nil
    ) -> (TroubleshootingFlowEngine, SpySessionStore) {
        let flow = FlowDefinition(version: 1, categoryId: "graphics", nodes: nodes, entryNodeId: entry)
        let registry = CheckRegistry()
        registry.register(StubCheck(checkId: "stub.outcome"))
        let store = SpySessionStore()
        // Node resolution goes through the session's active flow category, so
        // direct navigateToNode calls need it preset the way selectCategory
        // would have set it.
        var defaultSession = TroubleshootingSession(bottleURL: URL(filePath: "/tmp/engine-test-bottle"))
        defaultSession.currentFlowCategoryId = "graphics"
        let engine = TroubleshootingFlowEngine(
            flowDefinitions: ["graphics": flow],
            fragments: fragments,
            checkRegistry: registry,
            sessionStore: store,
            session: session ?? defaultSession
        )
        return (engine, store)
    }

    /// Waits until `condition` holds, yielding to let the engine's check
    /// tasks run; fails the test after ~2 seconds.
    private func waitUntil(
        _ message: String,
        condition: () -> Bool
    ) async {
        for _ in 0 ..< 200 where !condition() {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(condition(), "timed out waiting for: \(message)")
    }

    // MARK: - Category selection

    func testSelectCategoryNavigatesToEntryAndBranchesOnPass() async {
        let (engine, store) = makeEngine(nodes: [
            "start": checkNode("start", outcome: "pass", on: ["pass": "done-pass", "fail": "done-fail"]),
            "done-pass": infoNode("done-pass"),
            "done-fail": infoNode("done-fail")
        ])

        engine.selectCategory(.graphics)

        await waitUntil("branch to done-pass") { engine.currentNode?.id == "done-pass" }
        XCTAssertEqual(engine.session.phase, .checks)
        XCTAssertEqual(engine.session.checkResults["start"]?.outcome, .pass)
        XCTAssertEqual(engine.session.branchDecisions.last?.toNodeId, "done-pass")
        XCTAssertEqual(engine.session.stepHistory.map(\.nodeId), ["start", "done-pass"])
        XCTAssertGreaterThan(store.saveCount, 0)
    }

    func testUnmappedOutcomeFallsBackToDefaultBranch() async {
        let (engine, _) = makeEngine(nodes: [
            "start": checkNode("start", outcome: "unknown", on: ["pass": "done-pass", "default": "done-default"]),
            "done-pass": infoNode("done-pass"),
            "done-default": infoNode("done-default")
        ])

        engine.selectCategory(.graphics)

        await waitUntil("default branch") { engine.currentNode?.id == "done-default" }
        XCTAssertEqual(engine.session.checkResults["start"]?.outcome, .unknown)
    }

    func testOutcomeWithNoTargetStaysOnNodeButRecordsResult() async {
        let (engine, _) = makeEngine(nodes: [
            "start": checkNode("start", outcome: "fail", on: ["pass": "done"]),
            "done": infoNode("done")
        ])

        engine.selectCategory(.graphics)

        await waitUntil("check result recorded") { engine.session.checkResults["start"] != nil }
        XCTAssertEqual(engine.currentNode?.id, "start")
        XCTAssertFalse(engine.isRunningCheck)
    }

    func testUnknownCategoryEscalates() {
        let registry = CheckRegistry()
        let store = SpySessionStore()
        let engine = TroubleshootingFlowEngine(
            flowDefinitions: [:],
            fragments: [:],
            checkRegistry: registry,
            sessionStore: store
        )

        engine.selectCategory(.audio)

        XCTAssertEqual(engine.session.phase, .escalation)
    }

    func testEscalationNavigatesToFragmentEntryWhenAvailable() {
        let fragment = FlowDefinition(
            version: 1,
            categoryId: "export-escalation",
            nodes: ["export-start": infoNode("export-start")],
            entryNodeId: "export-start"
        )
        let (engine, _) = makeEngine(
            nodes: ["start": infoNode("start")],
            fragments: ["export-escalation": fragment]
        )

        engine.escalate()

        XCTAssertEqual(engine.session.phase, .escalation)
        XCTAssertEqual(engine.currentNode?.id, "export-start")
        XCTAssertEqual(engine.session.stepHistory.last?.nodeId, "export-start")
    }

    // MARK: - Cycle protection

    func testSelfLoopingCheckEscalatesInsteadOfSpinningForever() async {
        let (engine, _) = makeEngine(nodes: [
            "start": checkNode("start", outcome: "pass", on: ["pass": "start"])
        ])

        engine.selectCategory(.graphics)

        await waitUntil("cycle protection escalation") { engine.session.phase == .escalation }
    }

    // MARK: - Navigation helpers

    func testSkipStepFollowsSkippedTarget() {
        let (engine, _) = makeEngine(nodes: [
            "start": infoNode("start", on: ["skipped": "after-skip"]),
            "after-skip": infoNode("after-skip")
        ])
        engine.navigateToNode("start")

        engine.skipStep()

        XCTAssertEqual(engine.currentNode?.id, "after-skip")
    }

    func testGoBackRestoresPreviousNode() {
        let (engine, _) = makeEngine(nodes: [
            "start": infoNode("start"),
            "second": infoNode("second")
        ])
        engine.navigateToNode("start")
        engine.navigateToNode("second")

        engine.goBack()

        XCTAssertEqual(engine.currentNode?.id, "start")
        XCTAssertEqual(engine.session.currentNodeId, "start")
        XCTAssertEqual(engine.session.stepHistory.count, 1)
    }

    func testGoBackAtHistoryRootIsNoOp() {
        let (engine, _) = makeEngine(nodes: ["start": infoNode("start")])
        engine.navigateToNode("start")

        engine.goBack()

        XCTAssertEqual(engine.currentNode?.id, "start")
    }

    func testNavigateToMissingNodeEscalates() {
        let (engine, _) = makeEngine(nodes: ["start": infoNode("start")])

        engine.navigateToNode("no-such-node")

        XCTAssertEqual(engine.session.phase, .escalation)
    }

    func testInitRestoresCurrentNodeFromResumedSession() {
        var session = TroubleshootingSession(bottleURL: URL(filePath: "/tmp/engine-test-bottle"))
        session.currentFlowCategoryId = "graphics"
        session.currentNodeId = "second"

        let (engine, _) = makeEngine(
            nodes: ["start": infoNode("start"), "second": infoNode("second")],
            session: session
        )

        XCTAssertEqual(engine.currentNode?.id, "second")
    }

    // MARK: - Fix lifecycle

    func testFixLifecycleThroughUserReportsFixed() {
        let (engine, store) = makeEngine(nodes: ["start": infoNode("start")])

        engine.applyFix(fixId: "graphics.set_backend_dxvk", beforeValue: "wined3d", afterValue: "dxvk")
        XCTAssertEqual(engine.session.phase, .verify)
        XCTAssertEqual(engine.session.fixAttempts.last?.result, .pending)

        engine.confirmFixApplied(fixId: "graphics.set_backend_dxvk")
        XCTAssertEqual(engine.session.fixAttempts.last?.result, .applied)

        engine.userReportsFixed()
        XCTAssertEqual(engine.session.outcome, .resolved)
        XCTAssertEqual(engine.session.phase, .export)
        XCTAssertEqual(engine.session.fixAttempts.last?.result, .verified)
        XCTAssertEqual(store.completed.count, 1)
    }

    func testUndoLastFixMarksApplied() {
        let (engine, _) = makeEngine(nodes: ["start": infoNode("start")])
        engine.applyFix(fixId: "fix.a", beforeValue: nil, afterValue: nil)
        engine.confirmFixApplied(fixId: "fix.a")

        engine.undoLastFix()

        XCTAssertEqual(engine.session.fixAttempts.last?.result, .undone)
    }

    func testThreeFailedFixesEscalate() {
        let (engine, _) = makeEngine(nodes: ["start": infoNode("start")])

        for attempt in 0 ..< 3 {
            engine.applyFix(fixId: "fix.\(attempt)", beforeValue: nil, afterValue: nil)
            engine.confirmFixApplied(fixId: "fix.\(attempt)")
            engine.userReportsNotFixed()
        }

        XCTAssertEqual(engine.session.failedFixCount, 3)
        XCTAssertEqual(engine.session.phase, .escalation)
    }

    func testNotFixedFollowsNoTargetWhenAvailable() {
        let (engine, _) = makeEngine(nodes: [
            "verify": infoNode("verify", on: ["no": "second-fix"]),
            "second-fix": infoNode("second-fix")
        ])
        engine.navigateToNode("verify")
        engine.applyFix(fixId: "fix.a", beforeValue: nil, afterValue: nil)
        engine.confirmFixApplied(fixId: "fix.a")

        engine.userReportsNotFixed()

        XCTAssertEqual(engine.session.fixAttempts.last?.result, .failed)
        XCTAssertEqual(engine.currentNode?.id, "second-fix")
    }

    // MARK: - Start over

    func testStartOverPreservesIdentityButClearsProgress() {
        let bottleURL = URL(filePath: "/tmp/engine-test-bottle")
        let (engine, _) = makeEngine(nodes: [
            "start": infoNode("start"),
            "second": infoNode("second")
        ])
        let originalSessionId = engine.session.id
        engine.navigateToNode("start")
        engine.applyFix(fixId: "fix.a", beforeValue: nil, afterValue: nil)

        engine.startOver()

        XCTAssertNotEqual(engine.session.id, originalSessionId)
        XCTAssertEqual(engine.session.bottleURL, bottleURL)
        XCTAssertTrue(engine.session.stepHistory.isEmpty)
        XCTAssertTrue(engine.session.fixAttempts.isEmpty)
        XCTAssertNil(engine.currentNode)
        XCTAssertEqual(engine.session.phase, .symptom)
    }
}
