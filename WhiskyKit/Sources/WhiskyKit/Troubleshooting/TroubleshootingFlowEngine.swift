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

    /// The most recent check result, exposed so fix views can inherit
    /// evidence (e.g. which winetricks verb the check found missing).
    @Published public private(set) var lastCheckResult: CheckResult?

    /// Collects a fresh preflight snapshot.
    ///
    /// The snapshot is taken when the session starts, but the user changes
    /// what it describes along the way: a fix changes settings, and "it is
    /// still broken" means the program was launched again and wrote a new
    /// log. After those the next check runs on a snapshot from this
    /// provider, so a log check reads the new log. Without a provider the
    /// checks keep the snapshot the session started with.
    public var preflightProvider: (@MainActor () async -> PreflightData)?

    /// Whether the user did something since the snapshot was taken that
    /// the next check should see.
    var preflightIsStale = false

    /// The step the user was on when each pending fix was applied, by fix
    /// ID. A fix that takes a while (a winetricks install) lands after the
    /// user may have moved on; it only moves the session when the user is
    /// still on that step.
    var pendingFixOrigins: [String: String] = [:]

    // MARK: - Dependencies

    let flowDefinitions: [String: FlowDefinition]
    let fragments: [String: FlowDefinition]
    private let checkRegistry: CheckRegistry
    let sessionStore: any TroubleshootingSessionStoring

    let logger = Logger(
        subsystem: "com.franke.Whisky",
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

        // A flow's own hand-off to the escalation fragment. Every flow ends
        // its unresolved branch on an info node that references it, tagged
        // with the export phase like the resolved node, so without this the
        // wizard showed "Problem resolved" to someone it had given up on.
        if node.fragmentRef == "export-escalation" {
            logger.debug("Node \(node.id) hands off to the escalation fragment")
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
        let nodePhase = unresolvedGuard(TroubleshootingSession.SessionPhase(flowPhase: node.phase))
        if nodePhase != session.phase {
            session.phase = nodePhase
        }

        autoSave()

        if node.type == .branch {
            routeBranch(node)
            return
        }

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

            if preflightIsStale, let preflightProvider {
                preflightIsStale = false
                session.preflightSnapshot = await preflightProvider()
            }

            let context = CheckContext(
                bottleURL: session.preflightSnapshot?.bottleURL ?? session.bottleURL ?? URL(filePath: "/"),
                bottleName: session.preflightSnapshot?.bottleName ?? "Unknown",
                programURL: session.preflightSnapshot?.programURL ?? session.programURL,
                // The name is what the game-database check matches on; a
                // wizard opened from a program page has the URL but not always
                // the name, so fall back to the executable's filename.
                programName: session.preflightSnapshot?.programName
                    ?? (session.preflightSnapshot?.programURL ?? session.programURL)?.lastPathComponent,
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
            lastCheckResult = result
            session.recordCheckResult(nodeId: node.id, result: result)

            // Branch on normalized outcome
            let outcome = result.outcome.rawValue
            if let nextNodeId = node.on?[outcome] {
                logger.debug("Check \(checkId) outcome '\(outcome)' -> navigating to \(nextNodeId)")
                session.recordBranch(from: node.id, targetNodeId: nextNodeId, reason: "Check outcome: \(outcome)")
                advance(to: nextNodeId)
            } else if let defaultNext = node.on?["default"] {
                logger.debug("Check \(checkId) outcome '\(outcome)' not mapped, using default -> \(defaultNext)")
                session.recordBranch(
                    from: node.id, targetNodeId: defaultNext,
                    reason: "Default branch (outcome: \(outcome))"
                )
                advance(to: defaultNext)
            } else {
                logger.warning("Check \(checkId) outcome '\(outcome)' has no target and no default")
            }

            autoSave()
        }
    }

    // MARK: - Skip / Back / Restart

    /// Whether the current node has a `continue` transition, which is how an
    /// info node hands over to the next step. Never while escalated: the
    /// escalation screen offers its own ways on.
    public var canContinue: Bool {
        session.phase != .escalation && currentNode?.on?["continue"] != nil
    }

    /// Whether the current step can be skipped. Never while escalated: the
    /// escalation summary's transitions lead to the report steps, which are
    /// the escalation screen's own options.
    public var canSkip: Bool {
        session.phase != .escalation && currentNode != nil
    }

    /// Follows the current node's `continue` transition.
    ///
    /// Info nodes (a findings card between a check and its fix) only carry
    /// this transition. Nothing followed it, so every flow that reached one
    /// stopped there with Skip and Back as the only controls.
    public func continueStep() {
        // Moving on from an info card is when the user acts on it, such as
        // launching the program again with enhanced logging on.
        preflightIsStale = true
        follow(["continue", "default"], reason: "Continue")
    }

    /// Skips the current step, navigating to the "skipped" or "default"
    /// target. `continue` is the last fallback: skipping an info node means
    /// moving on.
    ///
    /// Per the locked "skip for now" decision, users can skip any step.
    public func skipStep() {
        follow(["skipped", "default", "continue"], reason: "Skip")
    }

    private func follow(_ keys: [String], reason: String) {
        guard let node = currentNode else { return }
        // An escalated session stays escalated: following the summary's
        // transitions drew the resolved screen for a problem that wasn't.
        guard session.phase != .escalation else {
            logger.debug("\(reason) ignored: the session is escalated")
            return
        }
        guard let nextNodeId = keys.lazy.compactMap({ node.on?[$0] }).first else {
            logger.warning("No \(reason) target for node \(node.id)")
            return
        }
        logger.debug("\(reason): step \(node.id) -> \(nextNodeId)")
        session.recordBranch(from: node.id, targetNodeId: nextNodeId, reason: reason)
        advance(to: nextNodeId)
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
            session.phase = unresolvedGuard(previousStep.phase)
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
        pendingFixOrigins = [:]
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

    /// Marks the most recent applied attempt at one fix as undone, for a
    /// fix undone from outside the verify step (enhanced logging turned off
    /// on the escalation screen).
    ///
    /// - Parameter fixId: The fix that was undone.
    public func markFixUndone(fixId: String) {
        if let index = session.fixAttempts.lastIndex(where: { $0.fixId == fixId && $0.result == .applied }) {
            session.fixAttempts[index].result = .undone
            autoSave()
        }
    }

    // MARK: - Private Helpers

    /// The phase to show for a step's phase. The export phase is where the
    /// wizard says the problem is resolved, so a session the user has not
    /// confirmed as fixed shows escalation there instead: the escalation
    /// fragment's own steps (its summary, report and support draft) are
    /// export-phase steps.
    private func unresolvedGuard(
        _ phase: TroubleshootingSession.SessionPhase
    ) -> TroubleshootingSession.SessionPhase {
        phase == .export && session.outcome != .resolved ? .escalation : phase
    }

    /// Follows a branch node's transition for the detected launcher.
    ///
    /// Branch nodes key their transitions by ``LauncherType`` raw value
    /// (`"Steam"`, `"EA App"`), matched against the preflight's launcher
    /// type, and fall back to `default` for any other launcher or none.
    private func routeBranch(_ node: FlowStepNode) {
        let launcher = session.preflightSnapshot?.launcherType
        let launcherTarget = launcher.flatMap { node.on?[$0] }
        guard let target = launcherTarget ?? node.on?["default"] else {
            logger.warning("Branch \(node.id) has no target for launcher \(launcher ?? "none") and no default")
            return
        }
        let reason = launcherTarget != nil ? "Launcher: \(launcher ?? "")" : "Default branch"
        session.recordBranch(from: node.id, targetNodeId: target, reason: reason)
        advance(to: target)
    }

    /// Resolves a node ID to a ``FlowStepNode`` by searching the current flow
    /// and then all fragments.
    ///
    /// - Parameter nodeId: The node ID to resolve.
    /// - Returns: The resolved node, or `nil` if not found.
    func resolveNode(_ nodeId: String) -> FlowStepNode? {
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
    func autoSave() {
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

// MARK: - Entry

extension TroubleshootingFlowEngine {
    /// Starts a new session for the point the wizard was opened from.
    ///
    /// An entry point that knows the symptom (a launch failure) goes straight
    /// into that category's flow. Every other one lands on symptom selection,
    /// so the wizard always has a step or the symptom picker to show. Setting
    /// the entry point's phase alone left bottle diagnostics in the checks
    /// phase with no step, which the wizard drew as a spinner with no check
    /// running.
    ///
    /// Call this on a fresh session, after setting its preflight snapshot,
    /// which the first check reads. Symptom selection saves nothing, so a
    /// wizard closed before a symptom is picked leaves no session to resume.
    ///
    /// - Parameter entryContext: Where the user opened the wizard from.
    public func start(from entryContext: EntryContext) {
        if let category = entryContext.initialCategory {
            selectCategory(category)
        } else {
            session.phase = .symptom
        }
    }
}
