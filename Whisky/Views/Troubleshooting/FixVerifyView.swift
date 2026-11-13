//
//  FixVerifyView.swift
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

/// "Did this fix it?" confirmation gate with Yes/No options.
///
/// Shown after a fix is applied. Gates progress on explicit user confirmation.
/// Displays the fix attempt count and offers an undo option when available.
/// Per locked decision: 3-attempt cap before escalation.
struct FixVerifyView: View {
    @ObservedObject var engine: TroubleshootingFlowEngine
    let bottle: Bottle
    let program: Program?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            headerSection
            descriptionSection
            attemptCounter
            actionButtons
            undoButton
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(20)
    }
}

// MARK: - Header

extension FixVerifyView {
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("troubleshooting.verify.title")
                .font(.title3)
                .fontWeight(.semibold)
        }
    }

    private var descriptionSection: some View {
        Text("troubleshooting.verify.description")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
    }
}

// MARK: - Attempt Counter

extension FixVerifyView {
    private var attemptCounter: some View {
        let totalAttempts = engine.session.fixAttempts.count
        let maxAttempts = 3
        return Text(String(
            format: String(localized: "troubleshooting.verify.attempt %d %d"),
            totalAttempts,
            maxAttempts
        ))
        .font(.caption)
        .foregroundStyle(.tertiary)
    }
}

// MARK: - Action Buttons

extension FixVerifyView {
    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                engine.userReportsFixed()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("troubleshooting.verify.fixed")
                }
                .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.large)

            Button {
                engine.userReportsNotFixed()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle")
                    Text("troubleshooting.verify.notFixed")
                }
                .frame(minWidth: 200)
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - Undo Button

extension FixVerifyView {
    @ViewBuilder
    private var undoButton: some View {
        if canUndo {
            Button {
                performUndo()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward")
                    Text("troubleshooting.verify.undoLast")
                }
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var canUndo: Bool {
        guard let lastApplied = engine.session.fixAttempts.last(where: {
            $0.result == .applied
        })
        else {
            return false
        }
        // Decided from the attempt alone: this runs on every render, and a
        // preview reads the current value (all of system.reg for a registry
        // fix) on the main actor.
        return FixApplicator.canUndo(lastApplied, hasProgram: program != nil)
    }

    private func performUndo() {
        guard let lastApplied = engine.session.fixAttempts.last(where: {
            $0.result == .applied
        })
        else {
            return
        }
        let success = FixApplicator.undo(
            attempt: lastApplied,
            bottle: bottle,
            program: program
        )
        if success {
            engine.undoLastFix()
        }
    }
}
