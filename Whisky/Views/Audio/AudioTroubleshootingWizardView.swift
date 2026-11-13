//
//  AudioTroubleshootingWizardView.swift
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

/// Symptom-driven troubleshooting wizard with step navigation.
///
/// Presents as a sheet with NavigationStack. The wizard flow maps directly
/// to ``AudioTroubleshootingEngine/WizardState`` cases: symptom selection,
/// running probes, showing findings, offering fixes, confirmation gates,
/// resolved, and escalation.
struct AudioTroubleshootingWizardView: View {
    @ObservedObject var engine: AudioTroubleshootingEngine
    var onDismiss: () -> Void
    var onOpenAdvanced: (() -> Void)?
    /// Applies the fix behind a wizard step, given its action id.
    var onApplyFix: ((String) async -> Void)?

    @State private var isApplyingFix = false

    var body: some View {
        NavigationStack {
            Group {
                switch engine.wizardState {
                case .pickSymptom:
                    pickSymptomView
                case .runningProbes:
                    runningProbesView
                case .showingFindings:
                    showingFindingsView
                case let .offeringFix(fixDescription, actionId):
                    offeringFixView(fixDescription: fixDescription, actionId: actionId)
                case .askingDidItWork:
                    askingDidItWorkView
                case .resolved:
                    resolvedView
                case .escalation:
                    escalationView
                }
            }
            .navigationTitle(String(localized: "audio.troubleshoot.title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("troubleshooting.wizard.close") { onDismiss() }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }

    // MARK: - Pick Symptom

    private var pickSymptomView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "audio.troubleshoot.pickSymptom"))
                .font(.title3).fontWeight(.medium).padding(.horizontal)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(AudioSymptom.allCases) { symptom in
                        Button { engine.selectSymptom(symptom) } label: { symptomCard(symptom) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical)
    }

    private func symptomCard(_ symptom: AudioSymptom) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symptom.sfSymbol)
                .font(.title2).foregroundStyle(.secondary).frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(symptom.displayName).font(.headline).foregroundStyle(.primary)
                Text(symptom.symptomDescription).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1))
    }

    // MARK: - Running Probes

    private var runningProbesView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView().controlSize(.large)
            Text(String(localized: "audio.troubleshoot.running"))
                .font(.title3).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(engine.probeResults) { result in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                        Text(result.summary).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if engine.isRunningProbe {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("audio.troubleshoot.analyzing").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
        .padding()
    }

    // MARK: - Showing Findings

    private var showingFindingsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "audio.troubleshoot.results"))
                .font(.title3).fontWeight(.medium).padding(.horizontal)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if engine.currentFindings.isEmpty {
                        noIssuesCard
                    } else {
                        AudioFindingsView(findings: engine.currentFindings)
                    }
                }
                .padding(.horizontal)
            }
            HStack {
                Spacer()
                if !engine.currentFindings.isEmpty {
                    Button(String(localized: "audio.troubleshoot.tryFix")) { engine.offerNextFix() }
                        .buttonStyle(.borderedProminent)
                }
                Button("troubleshooting.wizard.close") { onDismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal).padding(.bottom)
        }
        .padding(.vertical)
    }

    private var noIssuesCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green)
            Text(String(localized: "audio.troubleshoot.noIssues")).foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.controlBackgroundColor)))
    }

    // MARK: - Offering Fix

    private func offeringFixView(fixDescription: String, actionId: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "wrench.and.screwdriver").font(.system(size: 40)).foregroundStyle(.blue)
            Text(String(localized: "audio.troubleshoot.suggestedFix")).font(.title3).fontWeight(.medium)
            Text(fixDescription).font(.body).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            if AudioFixAction(troubleshootingActionId: actionId)?.closesRunningPrograms == true {
                Text("audio.fix.closesPrograms").font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 32)
            }
            Spacer()
            VStack(spacing: 8) {
                Button(String(localized: "audio.troubleshoot.applyFix")) {
                    isApplyingFix = true
                    Task { @MainActor in
                        await onApplyFix?(actionId)
                        isApplyingFix = false
                        engine.applyFix(actionId: actionId)
                    }
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                Button(String(localized: "audio.troubleshoot.skipFix")) { engine.offerNextFix() }
                    .buttonStyle(.bordered)
            }
            .disabled(isApplyingFix)
            .padding(.bottom)
        }
        .padding()
    }

    // MARK: - Asking Did It Work

    private var askingDidItWorkView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "questionmark.circle").font(.system(size: 40)).foregroundStyle(.orange)
            Text(String(localized: "audio.troubleshoot.didItWork")).font(.title3).fontWeight(.medium)
            Spacer()
            VStack(spacing: 8) {
                Button(String(localized: "audio.troubleshoot.yesFixed")) { engine.userReportsFixed() }
                    .buttonStyle(.borderedProminent).tint(.green).controlSize(.large)
                Button(String(localized: "audio.troubleshoot.noStillBroken")) {
                    engine.userReportsNotFixed()
                }
                .buttonStyle(.bordered)
                Button(String(localized: "audio.troubleshoot.testAgain")) {
                    Task { await engine.runProbes() }
                }
                .buttonStyle(.borderless).font(.caption)
            }
            .padding(.bottom)
        }
        .padding()
    }

    // MARK: - Resolved

    private var resolvedView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(.green)
            Text(String(localized: "audio.troubleshoot.resolved")).font(.title3).fontWeight(.medium)
            if !engine.attemptedFixes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("troubleshooting.resolved.changesApplied").font(.caption).foregroundStyle(.secondary)
                    ForEach(engine.attemptedFixes) { fix in
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark").font(.caption2).foregroundStyle(.green)
                            Text(AudioTroubleshootingEngine.fixDescription(for: fix.actionId))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 32)
            }
            Spacer()
            Button("Done") { onDismiss() }
                .buttonStyle(.borderedProminent).controlSize(.large).padding(.bottom)
        }
        .padding()
    }

    // MARK: - Escalation

    private var escalationView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "exclamationmark.triangle").font(.system(size: 40)).foregroundStyle(.orange)
            Text(String(localized: "audio.troubleshoot.escalation")).font(.title3).fontWeight(.medium)
            Text(String(localized: "audio.troubleshoot.escalationNext"))
                .font(.body).foregroundStyle(.secondary)
            VStack(spacing: 8) {
                Button(String(localized: "audio.troubleshoot.openAdvanced")) {
                    onOpenAdvanced?()
                    onDismiss()
                }
                .buttonStyle(.bordered)
                Button(String(localized: "audio.troubleshoot.exportDiagnostics")) { exportDiagnostics() }
                    .buttonStyle(.bordered)
                Button(String(localized: "audio.troubleshoot.openSystemSound")) {
                    openSystemSoundSettings()
                }
                .buttonStyle(.bordered)
            }
            Spacer()
            Button("troubleshooting.wizard.close") { onDismiss() }.keyboardShortcut(.cancelAction).padding(.bottom)
        }
        .padding()
    }

    /// Copies an English diagnostics report to the clipboard.
    ///
    /// The report reads the same in every language: it uses stable ids and raw
    /// values plus the probes' English evidence lines, never the localized
    /// summaries and finding text shown in the wizard.
    private func exportDiagnostics() {
        var lines = ["=== Audio Diagnostics Export ===", "Date: \(Date().formatted())"]
        if let symptom = engine.selectedSymptom { lines.append("Symptom: \(symptom.rawValue)") }
        lines.append("\n--- Probe Results ---")
        for result in engine.probeResults {
            lines.append("[\(result.status.rawValue)] \(result.probeId)")
            result.evidence.forEach { lines.append("  \($0)") }
        }
        lines.append("\n--- Findings ---")
        for finding in engine.currentFindings {
            lines.append("[\(finding.confidence.rawValue)] \(finding.id)")
        }
        lines.append("\n--- Attempted Fixes ---")
        engine.attemptedFixes.forEach { lines.append("- \($0.actionId)") }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    private func openSystemSoundSettings() {
        if let url = AudioFixAction.soundSettingsURL {
            NSWorkspace.shared.open(url)
        }
    }
}
