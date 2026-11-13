//
//  TroubleshootingFixLifecycleTests.swift
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

/// What happens to the session when a fix lands late, when a fix that did
/// not help comes up again, and when a fix is undone from elsewhere.
@MainActor
final class TroubleshootingFixLifecycleTests: XCTestCase {
    // MARK: - Fixtures

    private func makeEngine(scripted: [String: CheckOutcome]) -> TroubleshootingFlowEngine {
        let registry = CheckRegistry()
        for (checkId, outcome) in scripted {
            registry.register(ScriptedCheck(checkId, outcome: outcome))
        }
        let bottleURL = URL(filePath: "/tmp/fix-lifecycle-\(UUID().uuidString)")
        var session = TroubleshootingSession(bottleURL: bottleURL)
        session.preflightSnapshot = PreflightData(
            bottleURL: bottleURL,
            bottleName: "Lifecycle",
            isWineserverRunning: false,
            processCount: 0,
            graphicsBackend: "dxvk"
        )
        return TroubleshootingFlowEngine(
            flowDefinitions: FlowLoader.loadAllFlows(),
            fragments: FlowLoader.loadFragments(),
            checkRegistry: registry,
            sessionStore: SpySessionStore(),
            session: session
        )
    }

    private func waitUntil(
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: () -> Bool
    ) async {
        for _ in 0 ..< 200 where !condition() {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(condition(), "timed out waiting for: \(message)", file: file, line: line)
    }

    /// An install-dependencies session on its install step, with every
    /// later check scripted to lead to escalation.
    private func engineOnInstallStep() async -> TroubleshootingFlowEngine {
        let engine = makeEngine(scripted: [
            "winetricks.verb_check": .fail,
            "dependency.check_missing": .pass,
            "game.config_available": .fail
        ])
        engine.selectCategory(.installDependencies)
        await waitUntil("missing dependencies shown") { engine.currentNode?.id == "show_missing_deps" }
        engine.continueStep()
        XCTAssertEqual(engine.currentNode?.id, "fix_install_deps")
        return engine
    }

    // MARK: - A fix that lands late

    func testInstallThatLandsAfterTheUserSkippedLeavesTheSessionWhereItIs() async {
        let engine = await engineOnInstallStep()
        engine.applyFix(fixId: "install-winetricks-verb", beforeValue: nil, afterValue: "vcrun2019")

        engine.skipStep()
        await waitUntil("flow escalated") { engine.session.phase == .escalation }
        XCTAssertEqual(engine.currentNode?.id, "escalation_summary")

        engine.confirmFixApplied(fixId: "install-winetricks-verb")

        XCTAssertEqual(engine.currentNode?.id, "escalation_summary", "the install must not pull the user to verify")
        XCTAssertEqual(engine.session.phase, .escalation)
        XCTAssertEqual(engine.session.fixAttempts.last?.result, .applied, "the install is still recorded")
    }

    func testInstallThatFailsAfterTheUserWentBackLeavesTheSessionWhereItIs() async {
        let engine = await engineOnInstallStep()
        engine.applyFix(fixId: "install-winetricks-verb", beforeValue: nil, afterValue: "vcrun2019")

        engine.goBack()
        XCTAssertEqual(engine.currentNode?.id, "show_missing_deps")
        engine.markFixFailed(fixId: "install-winetricks-verb")

        XCTAssertEqual(engine.currentNode?.id, "show_missing_deps")
        XCTAssertEqual(engine.session.fixAttempts.last?.result, .failed)
    }

    func testInstallThatLandsWhileTheUserWaitsMovesOnToVerify() async {
        let engine = await engineOnInstallStep()
        engine.applyFix(fixId: "install-winetricks-verb", beforeValue: nil, afterValue: "vcrun2019")

        engine.confirmFixApplied(fixId: "install-winetricks-verb")

        XCTAssertEqual(engine.currentNode?.id, "verify_install")
        XCTAssertEqual(engine.session.phase, .verify)
    }

    func testStartingOverForgetsAPendingInstall() async {
        let engine = await engineOnInstallStep()
        engine.applyFix(fixId: "install-winetricks-verb", beforeValue: nil, afterValue: "vcrun2019")

        engine.startOver()
        engine.confirmFixApplied(fixId: "install-winetricks-verb")

        XCTAssertNil(engine.currentNode)
        XCTAssertTrue(engine.session.fixAttempts.isEmpty)
    }

    // MARK: - A fix that did not help

    func testGameConfigThatDidNotHelpIsNotOfferedAgain() async {
        let engine = makeEngine(scripted: [
            "graphics.backend_is": .pass,
            "crash.log_classify": .pass,
            "dxvk.settings_check": .pass,
            "game.config_available": .pass
        ])
        engine.selectCategory(.graphics)
        await waitUntil("game config offered") { engine.currentNode?.id == "suggest_game_config" }

        engine.applyFix(fixId: "apply-game-config", beforeValue: nil, afterValue: nil)
        engine.confirmFixApplied(fixId: "apply-game-config")
        XCTAssertEqual(engine.currentNode?.id, "verify_fix")
        engine.userReportsNotFixed()

        await waitUntil("flow escalated") { engine.session.phase == .escalation }
        XCTAssertEqual(engine.session.failedFixCount, 1, "escalated by the flow, not by the attempt cap")
        XCTAssertEqual(engine.session.fixAttempts.count, 1)
        XCTAssertTrue(engine.session.branchDecisions.contains {
            $0.fromNodeId == "suggest_game_config" && $0.toNodeId == "escalate"
        })
    }

    func testFixThatFailedToApplyIsOfferedAgain() async {
        let engine = await engineOnInstallStep()
        engine.applyFix(fixId: "install-winetricks-verb", beforeValue: nil, afterValue: "vcrun2019")
        engine.markFixFailed(fixId: "install-winetricks-verb")
        XCTAssertEqual(engine.currentNode?.id, "fix_install_deps")

        engine.goBack()
        engine.continueStep()

        XCTAssertEqual(engine.currentNode?.id, "fix_install_deps")
    }

    func testFixDidNotHelpOnlyCountsAttemptsThatLanded() throws {
        let engine = makeEngine(scripted: [:])
        let node = try XCTUnwrap(engine.flowDefinitions["graphics"]?.nodes["fix_enable_dxvk"])
        var notApplied = FixAttempt(fixId: "switch-backend", result: .failed, nodeId: node.id)
        engine.session.fixAttempts = [notApplied]
        XCTAssertFalse(engine.fixDidNotHelp(at: node))

        notApplied.wasApplied = true
        engine.session.fixAttempts = [notApplied]
        XCTAssertTrue(engine.fixDidNotHelp(at: node))
    }

    // MARK: - Undo from elsewhere

    func testMarkingAFixUndoneTargetsThatFix() {
        let engine = makeEngine(scripted: [:])
        engine.session.fixAttempts = [
            FixAttempt(fixId: "run-enhanced-diagnostics", result: .applied),
            FixAttempt(fixId: "switch-backend", result: .applied)
        ]

        engine.markFixUndone(fixId: "run-enhanced-diagnostics")

        XCTAssertEqual(engine.session.fixAttempts.map(\.result), [.undone, .applied])
        XCTAssertNil(engine.session.appliedAttempt(of: "run-enhanced-diagnostics"))
        XCTAssertEqual(engine.session.appliedAttempt(of: "switch-backend")?.fixId, "switch-backend")
    }

    func testAppliedAttemptIsTheLastAttemptStillInEffect() {
        var session = TroubleshootingSession()
        session.fixAttempts = [
            FixAttempt(fixId: "run-enhanced-diagnostics", result: .applied),
            FixAttempt(fixId: "run-enhanced-diagnostics", result: .undone)
        ]
        XCTAssertNil(session.appliedAttempt(of: "run-enhanced-diagnostics"), "the last attempt was undone")

        session.fixAttempts.append(FixAttempt(fixId: "run-enhanced-diagnostics", result: .pending))
        XCTAssertNil(session.appliedAttempt(of: "run-enhanced-diagnostics"))
        XCTAssertNil(session.appliedAttempt(of: "switch-backend"))
    }

    func testEnhancedDiagnosticsOnlyOfferedWhenTheyAddLogging() {
        XCTAssertTrue(FixApplicator.enhancedDiagnosticsAddsLogging(to: nil))
        XCTAssertTrue(FixApplicator.enhancedDiagnosticsAddsLogging(to: .normal))
        XCTAssertFalse(FixApplicator.enhancedDiagnosticsAddsLogging(to: FixApplicator.enhancedDiagnosticsPreset))
    }

    func testEscalationSummaryDescribesTheScreensOptions() throws {
        let fragment = try XCTUnwrap(FlowLoader.loadFragments()["export-escalation"])
        let summary = try XCTUnwrap(fragment.nodes[fragment.entryNodeId])

        XCTAssertEqual(summary.on?["enhanced_diagnostics"], "run_enhanced_diagnostics")
        XCTAssertNil(summary.on?["continue"], "Continue does nothing on the escalation screen")
        XCTAssertFalse(
            fragment.nodes.values.contains { $0.checkId == "diagnostics.can_enhance" },
            "no step the engine never reaches"
        )
    }
}
