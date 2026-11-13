//
//  EscalationView.swift
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

/// Unresolved outcome view with enhanced diagnostics, export, support draft, and retry options.
///
/// Shown when the flow reaches escalation (unresolved after 3 fix attempts or dead end).
/// Per locked escalation path decisions: offers WINEDEBUG preset re-run, diagnostic
/// export, GitHub issue draft, and retry from a previous step.
struct EscalationView: View {
    @ObservedObject var engine: TroubleshootingFlowEngine
    let bottle: Bottle
    let program: Program?

    @State private var showRetryPicker: Bool = false
    @State private var exportedPath: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            headerSection
            fixAttemptsSummary
            optionsSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Header

extension EscalationView {
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.title2)
                Text("troubleshooting.escalation.title")
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            Text("troubleshooting.escalation.description")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Fix Attempts Summary

extension EscalationView {
    @ViewBuilder
    private var fixAttemptsSummary: some View {
        if !engine.session.fixAttempts.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("troubleshooting.escalation.whatWasTried")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                ForEach(engine.session.fixAttempts, id: \.fixId) { attempt in
                    HStack(spacing: 6) {
                        Image(systemName: resultIcon(for: attempt.result))
                            .foregroundStyle(resultColor(for: attempt.result))
                            .font(.caption)
                        Text(attempt.localizedFixName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(attempt.result.localizedName)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.controlBackgroundColor))
            )
        }
    }

    private func resultIcon(for result: FixResult) -> String {
        switch result {
        case .verified: "checkmark.circle.fill"
        case .applied: "checkmark.circle"
        case .failed: "xmark.circle"
        case .undone: "arrow.uturn.backward.circle"
        case .pending: "clock"
        }
    }

    private func resultColor(for result: FixResult) -> Color {
        switch result {
        case .verified: .green
        case .applied: .blue
        case .failed: .red
        case .undone: .orange
        case .pending: .gray
        }
    }
}

// MARK: - Options

extension EscalationView {
    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if program != nil {
                enhancedDiagnosticsOption
            }
            exportDiagnosticsOption
            supportIssueOption
            retryOption
        }
    }
}

// MARK: - Enhanced Diagnostics

extension EscalationView {
    private var enhancedDiagnosticsOption: some View {
        escalationButton(
            title: "troubleshooting.escalation.enhancedDiag",
            description: "troubleshooting.escalation.enhancedDiag.description",
            sfSymbol: "text.magnifyingglass",
            action: runEnhancedDiagnostics
        )
    }

    private func runEnhancedDiagnostics() {
        let attempt = FixApplicator.apply(
            fixId: "run-enhanced-diagnostics",
            params: [:],
            bottle: bottle,
            program: program
        )
        engine.applyFix(
            fixId: attempt.fixId,
            beforeValue: attempt.beforeValue,
            afterValue: attempt.afterValue
        )
        if attempt.result == .failed {
            engine.markFixFailed(fixId: attempt.fixId)
        } else {
            engine.confirmFixApplied(fixId: attempt.fixId)
        }
    }
}

// MARK: - Export Diagnostics

extension EscalationView {
    private var exportDiagnosticsOption: some View {
        VStack(alignment: .leading, spacing: 4) {
            escalationButton(
                title: "troubleshooting.escalation.export",
                description: "troubleshooting.escalation.export.description",
                sfSymbol: "square.and.arrow.up",
                action: exportDiagnostics
            )
            if let exportedPath {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption2)
                    Text(String(format: String(localized: "troubleshooting.escalation.exportedTo %@"), exportedPath))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 44)
            }
        }
    }

    private func exportDiagnostics() {
        // Build a summary of the session for clipboard/export
        var lines: [String] = [
            "=== Troubleshooting Diagnostics Export ===",
            "Date: \(Date().formatted())"
        ]

        if let category = engine.session.symptomCategory {
            lines.append("Category: \(category.displayTitle)")
        }

        lines.append("\n--- Check Results ---")
        for (nodeId, result) in engine.session.checkResults {
            lines.append("[\(result.outcome.rawValue)] \(nodeId): \(result.summary)")
        }

        lines.append("\n--- Fix Attempts ---")
        for attempt in engine.session.fixAttempts {
            var line = "- \(attempt.fixId): \(attempt.result.rawValue)"
            if let before = attempt.beforeValue, let after = attempt.afterValue {
                line += " (\(before) -> \(after))"
            }
            lines.append(line)
        }

        lines.append("\n--- Environment ---")
        if let preflight = engine.session.preflightSnapshot {
            lines.append("Bottle: \(preflight.bottleName)")
            lines.append("Graphics: \(preflight.graphicsBackend)")
            if let audio = preflight.audioDeviceName {
                lines.append("Audio: \(audio)")
            }
            lines.append("Wineserver: \(preflight.isWineserverRunning ? "running" : "stopped")")
            lines.append("Processes: \(preflight.processCount)")
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        exportedPath = String(localized: "troubleshooting.escalation.clipboardReady")
    }
}

// MARK: - Support Issue Draft

extension EscalationView {
    private var supportIssueOption: some View {
        escalationButton(
            title: "troubleshooting.escalation.supportDraft",
            description: "troubleshooting.escalation.supportDraft.description",
            sfSymbol: "doc.on.clipboard",
            action: copyIssueDraft
        )
    }

    private func copyIssueDraft() {
        var draft = "## Problem Description\n\n"
        draft += "Automated troubleshooting could not resolve the issue.\n\n"

        if let category = engine.session.symptomCategory {
            draft += "**Category:** \(category.displayTitle)\n"
        }
        if let preflight = engine.session.preflightSnapshot {
            draft += "**Bottle:** \(preflight.bottleName)\n"
            draft += "**Graphics Backend:** \(preflight.graphicsBackend)\n"
            if let programName = preflight.programName {
                draft += "**Program:** \(programName)\n"
            }
        }

        draft += "\n## What Was Tried\n\n"
        for attempt in engine.session.fixAttempts {
            draft += "- \(attempt.fixId): \(attempt.result.rawValue)\n"
        }

        draft += "\n## Check Results\n\n"
        for (nodeId, result) in engine.session.checkResults {
            draft += "- \(nodeId): \(result.outcome.rawValue) - \(result.summary)\n"
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(draft, forType: .string)
    }
}

// MARK: - Retry

extension EscalationView {
    private var retryOption: some View {
        VStack(alignment: .leading, spacing: 4) {
            escalationButton(
                title: "troubleshooting.escalation.retry",
                description: "troubleshooting.escalation.retry.description",
                sfSymbol: "arrow.counterclockwise",
                action: { showRetryPicker = true }
            )

            if showRetryPicker {
                retryStepPicker
            }
        }
    }

    @ViewBuilder
    private var retryStepPicker: some View {
        let steps = engine.session.stepHistory.filter { $0.title != nil }
        if steps.isEmpty {
            Text("troubleshooting.escalation.noPreviousSteps")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.leading, 44)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    Button {
                        retryFromStep(step, index: index)
                    } label: {
                        HStack(spacing: 6) {
                            Text(String(
                                format: String(localized: "troubleshooting.escalation.stepNumber %d"),
                                index + 1
                            ))
                            .font(.caption)
                            .fontWeight(.medium)
                            Text(step.title ?? step.nodeId)
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.leading, 44)
        }
    }

    private func retryFromStep(
        _ step: TroubleshootingSession.CompletedStep,
        index: Int
    ) {
        // Trim step history to the chosen point
        engine.session.stepHistory = Array(engine.session.stepHistory.prefix(index))
        engine.navigateToNode(step.nodeId)
        showRetryPicker = false
    }
}

// MARK: - Shared Escalation Button

extension EscalationView {
    private func escalationButton(
        title: LocalizedStringKey,
        description: LocalizedStringKey,
        sfSymbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: sfSymbol)
                    .foregroundStyle(.secondary)
                    .font(.body)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
