// swiftlint:disable file_length
//
//  TroubleshootingFlowEngine.swift
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

import Combine
import Foundation
import os.log

// MARK: - Session Store Protocol

/// Protocol for persisting troubleshooting sessions.
///
/// A concrete implementation is provided in Plan 05. The engine depends on
/// this protocol to auto-save session state after each navigation step.
public protocol TroubleshootingSessionStoring: Sendable {
    /// Saves the current session state.
    ///
    /// - Parameter session: The session to persist.
    func save(_ session: TroubleshootingSession)

    /// Marks a session as complete and moves it to history.
    ///
    /// - Parameter session: The completed session.
    func completeSession(_ session: TroubleshootingSession)
}

// MARK: - Flow Engine

/// A JSON-driven state machine that navigates troubleshooting flow graphs.
///
/// Generalizes the ``AudioTroubleshootingEngine`` pattern into a category-agnostic
/// engine that loads flow definitions from JSON, runs checks via a ``CheckRegistry``,
/// branches on normalized outcomes, and auto-saves session state.
///
/// The engine is `@MainActor` for safe SwiftUI observation but has **no SwiftUI imports**.
/// It publishes state via `@Published` properties that the view layer observes.
///
/// ## Usage
///
/// ```swift
/// let engine = TroubleshootingFlowEngine(
///     flowDefinitions: FlowLoader.loadAllFlows(),
///     fragments: FlowLoader.loadFragments(),
///     checkRegistry: checkRegistry,
///     sessionStore: sessionStore
/// )
/// engine.selectCategory(.graphics)
/// ```
@MainActor
public final class TroubleshootingFlowEngine: ObservableObject {
    // MARK: - Published State

    /// The current troubleshooting session state.
    @Published public var session: TroubleshootingSession

    /// Whether a check is currently running asynchronously.
    @Published public var isRunningCheck: Bool = false

    /// The current flow step node being displayed.
    @Published public var currentNode: FlowStepNode?

    /// Whether the flow path has changed due to branching.
    @Published public var pathChanged: Bool = false

    /// Explanation of why the flow path changed.
    @Published public var pathChangeReason: String?

    // MARK: - Dependencies

    private let flowDefinitions: [String: FlowDefinition]
    private let fragments: [String: FlowDefinition]
    private let checkRegistry: CheckRegistry
    private let sessionStore: any TroubleshootingSessionStoring

    private let logger = Logger(
        subsystem: "com.isaacmarovitz.Whisky",
        category: "TroubleshootingFlowEngine"
    )

    // MARK: - Cycle Protection

    /// Tracks consecutive automated steps without user interaction.
    /// Reset to 0 when a .fix or .verify node is reached.
    private var automatedStepCount: Int = 0

    /// Maximum automated steps before forced escalation.
    private static let maxAutomatedSteps = 50

    // MARK: - Init

    /// Creates a new flow engine with all dependencies injected.
    ///
    /// - Parameters:
    ///   - flowDefinitions: Flow definitions keyed by category ID.
    ///   - fragments: Fragment definitions keyed by fragment name.
    ///   - checkRegistry: Registry mapping check IDs to implementations.
    ///   - sessionStore: Storage backend for session persistence.
    ///   - session: Initial session state. Defaults to a new session.
    public init(
        flowDefinitions: [String: FlowDefinition],
        fragments: [String: FlowDefinition],
        checkRegistry: CheckRegistry,
        sessionStore: any TroubleshootingSessionStoring,
        session: TroubleshootingSession = TroubleshootingSession()
    ) {
        self.flowDefinitions = flowDefinitions
        self.fragments = fragments
        self.checkRegistry = checkRegistry
        self.sessionStore = sessionStore
        self.session = session

        // Restore current node if resuming a session
        if let nodeId = session.currentNodeId {
            currentNode = resolveNode(nodeId)
        }
    }

    // MARK: - Category Selection

    /// Selects a symptom category and begins the troubleshooting flow.
    ///
    /// Looks up the flow definition for the category and navigates to its entry node.
    /// If no flow is found for the category, the engine escalates immediately.
    ///
    /// - Parameter category: The symptom category to troubleshoot.
    public func selectCategory(_ category: SymptomCategory) {
        let categoryId = String(category.flowFileName.dropLast(5)) // Remove ".json"
        guard let flow = flowDefinitions[categoryId] else {
            logger.error("No flow definition found for category: \(category.rawValue)")
            escalate()
            return
        }

        session.symptomCategory = category
        session.currentFlowCategoryId = categoryId
        session.phase = .checks
        autoSave()

        navigateToNode(flow.entryNodeId)
    }

    // MARK: - Navigation

    /// Navigates to a specific flow step node by ID.
    ///
    /// Resolves the node from the current flow or fragments, pushes it onto
    /// the step history, and auto-saves. If the node has a check, runs it
    /// automatically. Includes cycle protection that escalates after too many
    /// automated steps without user interaction.
    ///
    /// - Parameter nodeId: The target node ID.
    public func navigateToNode(_ nodeId: String) {
        guard let node = resolveNode(nodeId) else {
            logger.error("Failed to resolve node: \(nodeId)")
            escalate()
            return
        }

        // Cycle protection
        let isUserInteraction = node.type == .fix || node.type == .verify
        if isUserInteraction {
            automatedStepCount = 0
        } else {
            automatedStepCount += 1
            if automatedStepCount > Self.maxAutomatedSteps {
                logger.warning("Cycle protection triggered after \(self.automatedStepCount) automated steps")
                escalate()
                return
            }
        }

        currentNode = node
        session.pushStep(node)

        // Update session phase if the node's phase differs
        let nodePhase = TroubleshootingSession.SessionPhase(flowPhase: node.phase)
        if nodePhase != session.phase {
            session.phase = nodePhase
        }

        autoSave()

        // Auto-run checks for check-type nodes
        if let checkId = node.checkId {
            runCheck(checkId: checkId, params: node.params ?? [:], node: node)
        }
    }

    // MARK: - Check Execution

    /// Runs a check and branches based on the normalized result.
    private func runCheck(checkId: String, params: [String: String], node: FlowStepNode) {
        isRunningCheck = true

        Task { [weak self] in
            guard let self else { return }

            let context = CheckContext(
                bottleURL: session.preflightSnapshot?.bottleURL ?? session.bottleURL ?? URL(filePath: "/"),
                bottleName: session.preflightSnapshot?.bottleName ?? "Unknown",
                programURL: session.preflightSnapshot?.programURL ?? session.programURL,
                programName: session.preflightSnapshot?.programName,
                preflight: session.preflightSnapshot ?? PreflightData(
                    bottleURL: session.bottleURL ?? URL(filePath: "/"),
                    bottleName: "Unknown",
                    isWineserverRunning: false,
                    processCount: 0,
                    graphicsBackend: "unknown"
                ),
                session: session
            )

            let result = await checkRegistry.run(checkId: checkId, params: params, context: context)

            isRunningCheck = false
            session.recordCheckResult(nodeId: node.id, result: result)

            // Branch on normalized outcome
            let outcome = result.outcome.rawValue
            if let nextNodeId = node.on?[outcome] {
                logger.debug("Check \(checkId) outcome '\(outcome)' -> navigating to \(nextNodeId)")
                session.recordBranch(from: node.id, targetNodeId: nextNodeId, reason: "Check outcome: \(outcome)")
                navigateToNode(nextNodeId)
            } else if let defaultNext = node.on?["default"] {
                logger.debug("Check \(checkId) outcome '\(outcome)' not mapped, using default -> \(defaultNext)")
                session.recordBranch(
                    from: node.id, targetNodeId: defaultNext,
                    reason: "Default branch (outcome: \(outcome))"
                )
                navigateToNode(defaultNext)
            } else {
                logger.warning("Check \(checkId) outcome '\(outcome)' has no target and no default")
            }

            autoSave()
        }
    }

    // MARK: - Fix Application

    /// Records a fix application and transitions to the verify phase.
    ///
    /// Creates a ``FixAttempt`` with `.pending` result and records it in the session.
    ///
    /// - Parameters:
    ///   - fixId: The stable fix identifier from the flow node.
    ///   - beforeValue: The setting value before the fix, if applicable.
    ///   - afterValue: The setting value after the fix, if applicable.
    public func applyFix(fixId: String, beforeValue: String?, afterValue: String?) {
        let attempt = FixAttempt(
            fixId: fixId,
            timestamp: Date(),
            beforeValue: beforeValue,
            afterValue: afterValue,
            result: .pending
        )
        session.recordFixAttempt(attempt)
        session.phase = .verify
        autoSave()
    }

    /// Marks the most recent pending fix attempt as applied.
    ///
    /// - Parameter fixId: The fix identifier to confirm.
    public func confirmFixApplied(fixId: String) {
        if let index = session.fixAttempts.lastIndex(where: { $0.fixId == fixId && $0.result == .pending }) {
            session.fixAttempts[index].result = .applied
            autoSave()
        }
    }

    // MARK: - Verification

    /// Called when the user reports the problem is fixed.
    ///
    /// Sets the session outcome to resolved, transitions to the export phase,
    /// and saves the completed session to history.
    public func userReportsFixed() {
        session.outcome = .resolved
        session.phase = .export

        // Mark the most recent applied fix as verified
        if let index = session.fixAttempts.lastIndex(where: { $0.result == .applied }) {
            session.fixAttempts[index].result = .verified
        }

        autoSave()
        sessionStore.completeSession(session)
    }

    /// Called when the user reports the fix did not help.
    ///
    /// If the maximum fix attempts (3) have been exhausted, escalates.
    /// Otherwise, navigates to the next fix or re-branches from the current check.
    public func userReportsNotFixed() {
        // Mark the most recent applied fix as failed
        if let index = session.fixAttempts.lastIndex(where: { $0.result == .applied }) {
            session.fixAttempts[index].result = .failed
        }

        if session.failedFixCount >= 3 {
            logger.info("Max fix attempts reached, escalating")
            escalate()
        } else {
            // Navigate to the "no" or "default" target from current node
            if let node = currentNode, let nextNodeId = node.on?["no"] ?? node.on?["default"] {
                navigateToNode(nextNodeId)
            } else {
                escalate()
            }
        }
        autoSave()
    }

    // MARK: - Skip / Back / Restart

    /// Skips the current step, navigating to the "skipped" or "default" target.
    ///
    /// Per the locked "skip for now" decision, users can skip any step.
    public func skipStep() {
        guard let node = currentNode else { return }

        if let nextNodeId = node.on?["skipped"] ?? node.on?["default"] {
            logger.debug("Skipping step \(node.id) -> \(nextNodeId)")
            navigateToNode(nextNodeId)
        } else {
            logger.warning("No skip target for node \(node.id)")
        }
    }

    /// Goes back to the previous step in the history.
    ///
    /// Pops the last step from history and restores the previous node.
    public func goBack() {
        guard session.stepHistory.count > 1 else { return }

        // Remove the current step
        session.stepHistory.removeLast()

        // Restore the previous step
        if let previousStep = session.stepHistory.last {
            session.currentNodeId = previousStep.nodeId
            session.phase = previousStep.phase
            currentNode = resolveNode(previousStep.nodeId)
            automatedStepCount = 0
            autoSave()
        }
    }

    /// Escalates the session when automated troubleshooting is exhausted.
    ///
    /// Sets the session phase to escalation and navigates to the export-escalation
    /// fragment if available.
    public func escalate() {
        session.phase = .escalation

        // Try to navigate to the export-escalation fragment
        if let fragment = fragments["export-escalation"] {
            currentNode = fragment.nodes[fragment.entryNodeId]
            if let node = currentNode {
                session.pushStep(node)
            }
        }

        autoSave()
    }

    /// Resets the session to start over from symptom selection.
    ///
    /// Preserves the bottle and program URLs but clears all progress.
    public func startOver() {
        let bottleURL = session.bottleURL
        let programURL = session.programURL
        let preflight = session.preflightSnapshot

        session = TroubleshootingSession(
            bottleURL: bottleURL,
            programURL: programURL,
            preflightSnapshot: preflight
        )
        currentNode = nil
        automatedStepCount = 0
        pathChanged = false
        pathChangeReason = nil
        autoSave()
    }

    /// Marks the most recent applied fix as undone.
    ///
    /// Records the undo intent in the session. The actual undo logic
    /// is in the FixApplicator (Plan 05).
    public func undoLastFix() {
        if let index = session.fixAttempts.lastIndex(where: { $0.result == .applied }) {
            session.fixAttempts[index].result = .undone
            autoSave()
        }
    }

    // MARK: - Private Helpers

    /// Resolves a node ID to a ``FlowStepNode`` by searching the current flow
    /// and then all fragments.
    ///
    /// - Parameter nodeId: The node ID to resolve.
    /// - Returns: The resolved node, or `nil` if not found.
    private func resolveNode(_ nodeId: String) -> FlowStepNode? {
        // Check current flow first
        if let categoryId = session.currentFlowCategoryId,
           let flow = flowDefinitions[categoryId],
           let node = flow.nodes[nodeId] {
            return node
        }

        // Search all fragments
        for fragment in fragments.values {
            if let node = fragment.nodes[nodeId] {
                return node
            }
        }

        return nil
    }

    /// Auto-saves the session via the session store.
    private func autoSave() {
        session.lastUpdatedAt = Date()
        sessionStore.save(session)
    }

    /// Records a path change with explanation for the UI.
    ///
    /// - Parameters:
    ///   - oldPath: Description of the previous path.
    ///   - newPath: Description of the new path.
    ///   - reason: Why the path changed.
    private func handleBranchChange(from oldPath: String, to newPath: String, reason: String) {
        pathChanged = true
        pathChangeReason = reason
    }
}
