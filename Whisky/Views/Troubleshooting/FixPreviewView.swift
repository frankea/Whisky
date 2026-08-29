//
//  FixPreviewView.swift
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

/// Diff-style fix preview with explicit Apply button and confirmation for high-impact changes.
///
/// Shows current and proposed values side by side in a monospace diff layout.
/// Uses ``FixApplicator/preview(fixId:params:bottle:program:)`` to fetch
/// the current/new values and ``FixApplicator/apply(fixId:params:bottle:program:)``
/// to execute the fix. Per locked decision, the Apply button is explicit and gated.
struct FixPreviewView: View {
    let node: FlowStepNode
    @ObservedObject var engine: TroubleshootingFlowEngine
    let bottle: Bottle
    let program: Program?

    @State private var fixPreview: FixPreview?
    @State private var showConfirmation: Bool = false
    @State private var isApplying: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerSection
            if let fixPreview {
                diffPreviewSection(fixPreview)
                reversibilityIndicator(fixPreview)
            } else {
                fallbackDescription
            }
            actionButtons
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .onAppear(perform: loadPreview)
        .alert("troubleshooting.fix.confirmTitle", isPresented: $showConfirmation) {
            Button("button.cancel", role: .cancel) {}
            Button("troubleshooting.fix.apply") { applyFix() }
        } message: {
            Text(confirmationMessage)
        }
    }
}

// MARK: - Header

extension FixPreviewView {
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .foregroundStyle(.orange)
                    .font(.title3)
                if let title = node.title {
                    Text(title)
                        .font(.headline)
                }
            }
            if let description = node.description {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var fallbackDescription: some View {
        Group {
            if let description = node.description {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Diff Preview

extension FixPreviewView {
    private func diffPreviewSection(_ preview: FixPreview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(preview.settingName)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                // Current value (red, being removed)
                HStack(spacing: 6) {
                    Text("\u{2212}")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.red)
                    Text(preview.currentValue)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.red)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 4))

                // New value (green, being applied)
                HStack(spacing: 6) {
                    Text("+")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.green)
                    Text(preview.newValue)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.green)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            Text(String(format: String(localized: "troubleshooting.fix.scope %@"), preview.scope))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Reversibility Indicator

extension FixPreviewView {
    private func reversibilityIndicator(_ preview: FixPreview) -> some View {
        HStack(spacing: 6) {
            if preview.isReversible {
                Image(systemName: "arrow.uturn.backward.circle")
                    .foregroundStyle(.green)
                    .font(.caption)
                Text("troubleshooting.fix.reversible")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text("troubleshooting.fix.irreversible")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.orange)
            }
        }
    }
}

// MARK: - Action Buttons

extension FixPreviewView {
    private var actionButtons: some View {
        HStack {
            Button("troubleshooting.fix.skip") {
                engine.skipStep()
            }
            .buttonStyle(.bordered)

            Spacer()

            Button {
                if node.requiresConfirmation == true {
                    showConfirmation = true
                } else {
                    applyFix()
                }
            } label: {
                if isApplying {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("troubleshooting.fix.apply")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isApplying)
        }
    }

    private var confirmationMessage: String {
        if let preview = fixPreview {
            String(
                format: String(localized: "troubleshooting.fix.confirmChange %@ %@ %@"),
                preview.settingName, preview.currentValue, preview.newValue
            )
        } else {
            String(localized: "troubleshooting.fix.confirm")
        }
    }
}

// MARK: - Actions

extension FixPreviewView {
    /// The node's params, with the winetricks verb inherited from the check
    /// that found it missing when the flow does not hardcode one.
    private var resolvedParams: [String: String] {
        var params = node.params ?? [:]
        if node.fixId == "install-winetricks-verb", params["verb"] == nil,
           let missing = missingVerbsEvidence,
           let first = missing.split(separator: ",").first {
            params["verb"] = first.trimmingCharacters(in: .whitespaces)
        }
        return params
    }

    /// The `missing` evidence of the most recent check on the path here.
    ///
    /// Read from the session rather than `lastCheckResult`: that one is not
    /// persisted, so a resumed session offered to install "unknown".
    private var missingVerbsEvidence: String? {
        if let missing = engine.lastCheckResult?.evidence["missing"] {
            return missing
        }
        for step in engine.session.stepHistory.reversed() {
            if let missing = engine.session.checkResults[step.nodeId]?.evidence["missing"] {
                return missing
            }
        }
        return nil
    }

    private func loadPreview() {
        guard let fixId = node.fixId else { return }
        fixPreview = FixApplicator.preview(
            fixId: fixId,
            params: resolvedParams,
            bottle: bottle,
            program: program
        )
    }

    private func applyFix() {
        guard let fixId = node.fixId else { return }
        let params = resolvedParams

        if fixId == "install-winetricks-verb" {
            guard let verb = params["verb"] else {
                engine.skipStep()
                return
            }
            installVerb(verb, fixId: fixId)
            return
        }

        isApplying = true
        let attempt = FixApplicator.apply(
            fixId: fixId,
            params: params,
            bottle: bottle,
            program: program
        )
        engine.applyFix(
            fixId: fixId,
            beforeValue: attempt.beforeValue,
            afterValue: attempt.afterValue
        )
        if attempt.result == .failed {
            engine.markFixFailed(fixId: fixId)
        } else {
            engine.confirmFixApplied(fixId: fixId)
        }

        isApplying = false
    }

    /// Runs the winetricks install for real and only confirms the attempt
    /// once the verb actually landed.
    private func installVerb(_ verb: String, fixId: String) {
        isApplying = true
        engine.applyFix(fixId: fixId, beforeValue: nil, afterValue: verb)
        Task {
            var exitCode: Int32?
            var failure: String?
            for await progress in Winetricks.installVerb(verb, for: bottle) {
                switch progress {
                case let .completed(code): exitCode = code
                case let .failed(message): failure = message
                case .preparing, .output: break
                }
            }
            if failure == nil, exitCode == 0 {
                engine.confirmFixApplied(fixId: fixId)
            } else {
                engine.markFixFailed(fixId: fixId)
            }
            isApplying = false
        }
    }
}
