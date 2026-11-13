//
//  EscalationView+EnhancedDiagnostics.swift
//  Whisky
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

import SwiftUI
import WhiskyKit

// MARK: - Enhanced Diagnostics

extension EscalationView {
    /// Turning enhanced logging on, or back off once this session turned it
    /// on: it makes every launch of the program log verbosely until then.
    /// Nothing while the program already logs with the enhanced preset.
    @ViewBuilder
    var enhancedDiagnosticsOptions: some View {
        if let program {
            if let attempt = engine.session.appliedAttempt(of: Self.enhancedDiagnosticsFixId) {
                restoreLoggingOption(attempt)
            } else if FixApplicator.enhancedDiagnosticsAddsLogging(to: program.settings.activeWineDebugPreset) {
                enhancedDiagnosticsOption
            }
        }
    }

    private static let enhancedDiagnosticsFixId = "run-enhanced-diagnostics"

    private var enhancedDiagnosticsOption: some View {
        escalationButton(
            title: "troubleshooting.escalation.enhancedDiag",
            description: "troubleshooting.escalation.enhancedDiag.description",
            sfSymbol: "text.magnifyingglass",
            action: runEnhancedDiagnostics
        )
    }

    /// Turns on the enhanced logging preset. The engine ties the attempt to
    /// the escalation fragment's enhanced diagnostics step and follows its
    /// `applied` transition: launch the program again, then analyze the new
    /// log.
    private func runEnhancedDiagnostics() {
        let attempt = FixApplicator.apply(
            fixId: Self.enhancedDiagnosticsFixId,
            params: [:],
            bottle: bottle,
            program: program
        )
        engine.applyFix(
            fixId: attempt.fixId,
            beforeValue: attempt.beforeValue,
            afterValue: attempt.afterValue,
            params: attempt.params
        )
        if attempt.result == .failed {
            engine.markFixFailed(fixId: attempt.fixId)
        } else {
            engine.confirmFixApplied(fixId: attempt.fixId)
        }
    }

    private func restoreLoggingOption(_ attempt: FixAttempt) -> some View {
        escalationButton(
            title: "troubleshooting.escalation.restoreLogging",
            description: "troubleshooting.escalation.restoreLogging.description",
            sfSymbol: "arrow.uturn.backward",
            action: { restoreLogging(attempt) }
        )
    }

    /// Puts the program's WINEDEBUG preset back to what it was before
    /// enhanced diagnostics turned it on.
    private func restoreLogging(_ attempt: FixAttempt) {
        if FixApplicator.undo(attempt: attempt, bottle: bottle, program: program) {
            engine.markFixUndone(fixId: attempt.fixId)
        }
    }
}
