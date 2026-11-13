//
//  TroubleshootingFlowEngine+Fixes.swift
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

// MARK: - Fix Application

extension TroubleshootingFlowEngine {
    /// How many fixes may fail, by not applying or by not helping, before
    /// the session escalates.
    public static let maxFailedFixes = 3

    /// Records a fix the user is applying.
    ///
    /// Creates a ``FixAttempt`` with `.pending` result and records it in the
    /// session, tied to the flow node that offers the fix: the current node,
    /// or the flow or fragment node with this fix ID when the fix is applied
    /// from elsewhere (enhanced diagnostics on the escalation screen). The
    /// session stays on the fix step until ``confirmFixApplied(fixId:)`` or
    /// ``markFixFailed(fixId:)`` says how it went, so a fix that takes a while
    /// (a winetricks install) shows its progress there.
    ///
    /// - Parameters:
    ///   - fixId: The stable fix identifier from the flow node.
    ///   - beforeValue: The setting value before the fix, if applicable.
    ///   - afterValue: The setting value after the fix, if applicable.
    ///   - params: The params the fix was applied with. A parameterized fix
    ///     (a registry write) needs them back to be undone.
    public func applyFix(
        fixId: String,
        beforeValue: String?,
        afterValue: String?,
        params: [String: String]? = nil
    ) {
        let attempt = FixAttempt(
            fixId: fixId,
            timestamp: Date(),
            beforeValue: beforeValue,
            afterValue: afterValue,
            result: .pending,
            params: params,
            nodeId: fixNode(for: fixId)?.id
        )
        session.recordFixAttempt(attempt)
        pendingFixOrigins[fixId] = currentNode?.id ?? ""
        autoSave()
    }

    /// Marks the most recent pending fix attempt as applied and moves on.
    ///
    /// Follows the fix node's `applied` transition (`default` when it has
    /// none), which leads to the step that asks whether the fix helped. A
    /// fix with no node to follow goes straight to the verify phase.
    ///
    /// A fix that lands after the user left the step it was applied from
    /// (skipped or went back during a long install) is recorded as applied
    /// without moving the session from where the user is now.
    ///
    /// - Parameter fixId: The fix identifier to confirm.
    public func confirmFixApplied(fixId: String) {
        guard let index = session.fixAttempts.lastIndex(where: { $0.fixId == fixId && $0.result == .pending })
        else {
            return
        }
        session.fixAttempts[index].result = .applied
        session.fixAttempts[index].wasApplied = true
        // The fix changed what the snapshot describes.
        preflightIsStale = true

        guard userStayed(withFixAt: index) else {
            logger.debug("Fix \(fixId) applied after the user moved on; staying on the current step")
            autoSave()
            return
        }
        if let nodeId = session.fixAttempts[index].nodeId,
           let node = resolveNode(nodeId),
           let next = node.on?["applied"] ?? node.on?["default"] {
            logger.debug("Fix \(fixId) applied: step \(node.id) -> \(next)")
            session.recordBranch(from: node.id, targetNodeId: next, reason: "Fix applied")
            advance(to: next)
        } else {
            session.phase = .verify
        }
        autoSave()
    }

    /// Marks the most recent pending fix attempt as failed, so a fix that
    /// could not be performed never reads as applied in the session record.
    ///
    /// The session stays on the fix step, where it can be tried again or
    /// skipped, until ``maxFailedFixes`` fixes have failed; then it escalates.
    /// A fix that fails after the user moved on is recorded without moving
    /// the session; the cap then applies at the next fix that fails.
    ///
    /// - Parameter fixId: The fix identifier that failed.
    public func markFixFailed(fixId: String) {
        guard let index = session.fixAttempts.lastIndex(where: { $0.fixId == fixId && $0.result == .pending })
        else {
            return
        }
        session.fixAttempts[index].result = .failed
        autoSave()
        guard userStayed(withFixAt: index) else {
            logger.debug("Fix \(fixId) failed after the user moved on; staying on the current step")
            return
        }
        if session.failedFixCount >= Self.maxFailedFixes, session.phase != .escalation {
            logger.info("Max fix attempts reached, escalating")
            escalate()
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
    /// If ``maxFailedFixes`` fixes have failed, escalates. Otherwise follows
    /// the verify step's `no` transition (`default` when it has none) to the
    /// next check or fix.
    public func userReportsNotFixed() {
        // Mark the most recent applied fix as failed
        if let index = session.fixAttempts.lastIndex(where: { $0.result == .applied }) {
            session.fixAttempts[index].result = .failed
        }
        // Finding out meant launching the program again: there is a new log.
        preflightIsStale = true

        if session.failedFixCount >= Self.maxFailedFixes {
            logger.info("Max fix attempts reached, escalating")
            escalate()
        } else if let node = currentNode, let nextNodeId = node.on?["no"] ?? node.on?["default"] {
            session.recordBranch(from: node.id, targetNodeId: nextNodeId, reason: "Not fixed")
            advance(to: nextNodeId)
        } else {
            escalate()
        }
        autoSave()
    }

    // MARK: - Flow Transitions

    /// Follows a flow transition to a step, passing over fix steps whose fix
    /// was applied in this session and did not help.
    ///
    /// "Still broken" leads back through the flow's checks, and a check that
    /// passes whether or not its fix was applied (a game configuration the
    /// database has) offered the same fix again until the attempt cap
    /// escalated. A fix step already tried follows its `skipped` transition
    /// (`default` when it has none) instead. A fix that failed to apply is
    /// offered again, and steps reached any other way (resuming, retrying
    /// from a chosen step) are shown as they are.
    ///
    /// - Parameter nodeId: The transition's target.
    func advance(to nodeId: String) {
        var target = nodeId
        var passedOver: Set<String> = []
        while let node = resolveNode(target), node.type == .fix, fixDidNotHelp(at: node),
              passedOver.insert(node.id).inserted,
              let next = node.on?["skipped"] ?? node.on?["default"] {
            logger.debug("Fix step \(node.id) did not help this session; following skipped -> \(next)")
            session.recordBranch(from: node.id, targetNodeId: next, reason: "Fix already tried")
            target = next
        }
        navigateToNode(target)
    }

    /// Whether a fix offered from this step was applied in this session and
    /// the user said it did not help.
    func fixDidNotHelp(at node: FlowStepNode) -> Bool {
        session.fixAttempts.contains { $0.nodeId == node.id && $0.result == .failed && $0.wasApplied == true }
    }

    // MARK: - Helpers

    /// Whether the user is still on the step a pending fix was applied
    /// from, which is when its outcome may move the session. Forgets the
    /// step either way: the attempt is no longer pending.
    ///
    /// A fix applied from elsewhere (enhanced diagnostics on the escalation
    /// screen) was applied from the step the user was on then. An attempt
    /// with no recorded step is compared against its fix node.
    private func userStayed(withFixAt index: Int) -> Bool {
        let attempt = session.fixAttempts[index]
        let current = currentNode?.id ?? ""
        guard let origin = pendingFixOrigins.removeValue(forKey: attempt.fixId) else {
            return attempt.nodeId == nil || attempt.nodeId == current
        }
        return origin == current
    }

    /// The flow node that offers a fix: the current node when it does,
    /// otherwise the first node with that fix ID in the current flow and
    /// then in the fragments, in node ID order.
    func fixNode(for fixId: String) -> FlowStepNode? {
        if let currentNode, currentNode.fixId == fixId {
            return currentNode
        }
        var candidates: [FlowDefinition] = []
        if let categoryId = session.currentFlowCategoryId, let flow = flowDefinitions[categoryId] {
            candidates.append(flow)
        }
        candidates += fragments.keys.sorted().compactMap { fragments[$0] }
        for definition in candidates {
            for nodeId in definition.nodes.keys.sorted() {
                if let node = definition.nodes[nodeId], node.fixId == fixId {
                    return node
                }
            }
        }
        return nil
    }
}
