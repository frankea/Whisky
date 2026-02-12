//
//  TroubleshootingSession.swift
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

/// Full state of a troubleshooting wizard session.
///
/// Captures every aspect of the wizard's progress: selected symptom, current flow
/// position, completed steps, check results, fix attempts, branch decisions, and
/// outcome. Designed for persistence so sessions can be paused and resumed.
public struct TroubleshootingSession: Codable, Sendable {
    /// Unique identifier for this session.
    public var id: UUID

    /// URL of the bottle being troubleshot.
    public var bottleURL: URL?

    /// URL of the program being troubleshot, if any.
    public var programURL: URL?

    /// The symptom category selected by the user.
    public var symptomCategory: SymptomCategory?

    /// Current wizard phase.
    public var phase: SessionPhase

    /// History of completed steps in traversal order.
    public var stepHistory: [CompletedStep]

    /// The current flow step node ID.
    public var currentNodeId: String?

    /// The category ID of the currently loaded flow.
    public var currentFlowCategoryId: String?

    /// Check results keyed by node ID.
    public var checkResults: [String: CheckResult]

    /// All fix attempts made during this session.
    public var fixAttempts: [FixAttempt]

    /// Branch decisions recorded during flow traversal.
    public var branchDecisions: [BranchDecision]

    /// The final outcome of this session, if complete.
    public var outcome: SessionOutcome?

    /// When this session was created.
    public var createdAt: Date

    /// When this session was last modified.
    public var lastUpdatedAt: Date

    /// Preflight data snapshot taken at session start.
    public var preflightSnapshot: PreflightData?

    public init(
        id: UUID = UUID(),
        bottleURL: URL? = nil,
        programURL: URL? = nil,
        symptomCategory: SymptomCategory? = nil,
        phase: SessionPhase = .symptom,
        stepHistory: [CompletedStep] = [],
        currentNodeId: String? = nil,
        currentFlowCategoryId: String? = nil,
        checkResults: [String: CheckResult] = [:],
        fixAttempts: [FixAttempt] = [],
        branchDecisions: [BranchDecision] = [],
        outcome: SessionOutcome? = nil,
        createdAt: Date = Date(),
        lastUpdatedAt: Date = Date(),
        preflightSnapshot: PreflightData? = nil
    ) {
        self.id = id
        self.bottleURL = bottleURL
        self.programURL = programURL
        self.symptomCategory = symptomCategory
        self.phase = phase
        self.stepHistory = stepHistory
        self.currentNodeId = currentNodeId
        self.currentFlowCategoryId = currentFlowCategoryId
        self.checkResults = checkResults
        self.fixAttempts = fixAttempts
        self.branchDecisions = branchDecisions
        self.outcome = outcome
        self.createdAt = createdAt
        self.lastUpdatedAt = lastUpdatedAt
        self.preflightSnapshot = preflightSnapshot
    }

    // MARK: - Computed Properties

    /// The number of fix attempts that resulted in failure.
    public var failedFixCount: Int {
        fixAttempts.filter { $0.result == .failed }.count
    }

    // MARK: - Mutating Methods

    /// Records a completed step from a flow node.
    ///
    /// - Parameter node: The flow step node that was completed.
    public mutating func pushStep(_ node: FlowStepNode) {
        let step = CompletedStep(
            nodeId: node.id,
            phase: SessionPhase(flowPhase: node.phase),
            title: node.title,
            checkResult: nil,
            isSuperseded: false
        )
        stepHistory.append(step)
        currentNodeId = node.id
        lastUpdatedAt = Date()
    }

    /// Records a check result for a specific node.
    ///
    /// - Parameters:
    ///   - nodeId: The node ID the check was run for.
    ///   - result: The check result to record.
    public mutating func recordCheckResult(nodeId: String, result: CheckResult) {
        checkResults[nodeId] = result
        // Update the most recent step with the check result
        if let index = stepHistory.lastIndex(where: { $0.nodeId == nodeId }) {
            stepHistory[index].checkResult = result
        }
        lastUpdatedAt = Date()
    }

    /// Records a fix attempt.
    ///
    /// - Parameter attempt: The fix attempt to record.
    public mutating func recordFixAttempt(_ attempt: FixAttempt) {
        fixAttempts.append(attempt)
        lastUpdatedAt = Date()
    }

    /// Records a branch decision.
    ///
    /// - Parameters:
    ///   - from: The node ID where the branch originated.
    ///   - to: The node ID that was chosen.
    ///   - reason: Optional explanation of why this branch was taken.
    public mutating func recordBranch(from: String, to: String, reason: String? = nil) {
        let decision = BranchDecision(
            fromNodeId: from,
            toNodeId: to,
            reason: reason,
            timestamp: Date()
        )
        branchDecisions.append(decision)
        lastUpdatedAt = Date()
    }

    // MARK: - Nested Types

    /// The phase of a troubleshooting wizard session.
    public enum SessionPhase: String, Codable, Sendable {
        /// User is selecting a symptom category.
        case symptom
        /// Automated checks are running.
        case checks
        /// A fix is being applied.
        case fix
        /// Post-fix verification is in progress.
        case verify
        /// Session export or summary.
        case export
        /// Escalation after exhausting automated fixes.
        case escalation

        /// Creates a session phase from a flow phase.
        public init(flowPhase: FlowPhase) {
            switch flowPhase {
            case .symptom: self = .symptom
            case .checks: self = .checks
            case .fix: self = .fix
            case .verify: self = .verify
            case .export: self = .export
            }
        }
    }

    /// The final outcome of a completed troubleshooting session.
    public enum SessionOutcome: String, Codable, Sendable {
        /// The issue was resolved during troubleshooting.
        case resolved
        /// The issue was not resolved; escalation may be needed.
        case unresolved
        /// The user abandoned the session before completion.
        case abandoned
    }

    /// A record of a completed flow step.
    public struct CompletedStep: Codable, Sendable {
        /// The flow node ID for this step.
        public let nodeId: String

        /// Which wizard phase this step belonged to.
        public let phase: SessionPhase

        /// The step title, if any.
        public let title: String?

        /// The check result, if this was a check step.
        public var checkResult: CheckResult?

        /// Whether this step has been superseded by a branch change.
        public var isSuperseded: Bool

        public init(
            nodeId: String,
            phase: SessionPhase,
            title: String? = nil,
            checkResult: CheckResult? = nil,
            isSuperseded: Bool = false
        ) {
            self.nodeId = nodeId
            self.phase = phase
            self.title = title
            self.checkResult = checkResult
            self.isSuperseded = isSuperseded
        }
    }

    /// A record of a branch decision during flow traversal.
    public struct BranchDecision: Codable, Sendable {
        /// The node ID where the branch originated.
        public let fromNodeId: String

        /// The node ID that was chosen.
        public let toNodeId: String

        /// Optional explanation of why this branch was taken.
        public let reason: String?

        /// When this branch decision was made.
        public let timestamp: Date

        public init(fromNodeId: String, toNodeId: String, reason: String? = nil, timestamp: Date = Date()) {
            self.fromNodeId = fromNodeId
            self.toNodeId = toNodeId
            self.reason = reason
            self.timestamp = timestamp
        }
    }
}
