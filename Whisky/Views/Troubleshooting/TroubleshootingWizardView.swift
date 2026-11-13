//
//  TroubleshootingWizardView.swift
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

/// Main troubleshooting wizard presented as a sheet.
///
/// Displays a single-page layout with a ``ProgressRailView`` on the left
/// and a step area on the right. The step area switches content based
/// on the current session phase from the ``TroubleshootingFlowEngine``.
struct TroubleshootingWizardView: View {
    let bottle: Bottle
    let program: Program?
    let entryContext: EntryContext

    @StateObject private var engine: TroubleshootingFlowEngine
    @Environment(\.dismiss) private var dismiss

    @State private var showResumeOverlay: Bool = false
    @State private var resumeSession: TroubleshootingSession?
    @State private var stalenessChanges: [StalenessChange] = []
    @State private var showConfirmationSubSheet: Bool = false
    /// Set until the first preflight snapshot is in: no check may run, and
    /// no symptom be picked, on a session without one.
    @State private var isCollectingPreflight: Bool = true
    /// The snapshot taken on open, which a resumed session continues with.
    @State private var currentPreflight: PreflightData?

    private let sessionStore = TroubleshootingSessionStore()

    init(bottle: Bottle, program: Program?, entryContext: EntryContext) {
        self.bottle = bottle
        self.program = program
        self.entryContext = entryContext

        let store = TroubleshootingSessionStore()
        let engine = TroubleshootingFlowEngine(
            flowDefinitions: FlowLoader.loadAllFlows(),
            fragments: FlowLoader.loadFragments(),
            checkRegistry: CheckRegistry(),
            sessionStore: store
        )
        _engine = StateObject(wrappedValue: engine)
    }

    var body: some View {
        ZStack {
            mainContent
            if showResumeOverlay, let session = resumeSession {
                SessionResumeView(
                    session: session,
                    stalenessChanges: stalenessChanges,
                    onResume: resumeSession(session:),
                    onStartOver: startOver,
                    onDiscard: discardSession
                )
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .task { await onAppear() }
    }
}

// MARK: - Main Content

extension TroubleshootingWizardView {
    private var mainContent: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                ProgressRailView(session: engine.session)
                    .frame(width: 180)
                Divider()
                stepArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Toolbar

extension TroubleshootingWizardView {
    private var toolbar: some View {
        HStack {
            Button("troubleshooting.wizard.close") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            stepIndicator
            Spacer()
            HStack(spacing: 8) {
                Button("troubleshooting.back") { engine.goBack() }
                    .disabled(engine.session.stepHistory.count <= 1)
                Button("troubleshooting.wizard.skip") { engine.skipStep() }
                    .disabled(!engine.canSkip)
                if engine.canContinue {
                    Button("troubleshooting.wizard.continue") { engine.continueStep() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var stepIndicator: some View {
        Group {
            let totalSteps = engine.session.stepHistory.count
            if totalSteps > 0 {
                Text(String(format: String(localized: "troubleshooting.wizard.step %d"), totalSteps))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Step Area

extension TroubleshootingWizardView {
    private var stepArea: some View {
        VStack(spacing: 0) {
            if engine.pathChanged {
                BranchExplanationView(reason: engine.pathChangeReason) {
                    engine.pathChanged = false
                }
            }
            ScrollView {
                stepContent
                    .padding(20)
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        if isCollectingPreflight {
            checksPlaceholder
        } else {
            phaseContent
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch engine.session.phase {
        case .symptom:
            SymptomPickerView(engine: engine)
        case .checks:
            if let node = engine.currentNode {
                StepCardView(
                    node: node,
                    checkResult: engine.session.checkResults[node.id],
                    isRunning: engine.isRunningCheck
                )
            } else if engine.isRunningCheck {
                checksPlaceholder
            } else {
                // No step and no check running: a spinner here would never
                // finish, so let the user pick a symptom instead.
                SymptomPickerView(engine: engine)
            }
        case .fix:
            if let node = engine.currentNode {
                FixPreviewView(
                    node: node,
                    engine: engine,
                    bottle: bottle,
                    program: program
                )
            }
        case .verify:
            FixVerifyView(engine: engine, bottle: bottle, program: program)
        case .export:
            resolvedSummary
        case .escalation:
            EscalationView(engine: engine, bottle: bottle, program: program)
        }
    }
}

// MARK: - Placeholder Views

extension TroubleshootingWizardView {
    private var checksPlaceholder: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("troubleshooting.wizard.runningChecks")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resolvedSummary: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("troubleshooting.resolved.title")
                .font(.title2)
                .fontWeight(.semibold)

            if !engine.session.fixAttempts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("troubleshooting.resolved.changesApplied")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(engine.session.fixAttempts, id: \.fixId) { attempt in
                        HStack(spacing: 6) {
                            Image(systemName: resultIcon(for: attempt.result))
                                .font(.caption)
                                .foregroundStyle(resultColor(for: attempt.result))
                            Text(attempt.localizedFixName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 32)
            }

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
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

// MARK: - Lifecycle

extension TroubleshootingWizardView {
    private func onAppear() async {
        // Configure session with bottle/program context
        engine.session.bottleURL = entryContext.bottleURL
        engine.session.programURL = entryContext.programURL
        // Fixes and relaunches change what the snapshot describes; the
        // engine takes a new one before the next check after them.
        engine.preflightProvider = { [bottle, program, entryContext] in
            await PreflightCollector.collect(
                bottle: bottle, program: program, programURL: entryContext.programURL
            )
        }

        let preflight = await collectPreflight()
        currentPreflight = preflight
        isCollectingPreflight = false

        // Check for existing active session
        if let existingSession = sessionStore.loadActiveSession(for: entryContext.bottleURL) {
            stalenessChanges = sessionStore.checkStaleness(
                session: existingSession,
                currentPreflight: preflight
            )
            resumeSession = existingSession
            showResumeOverlay = true
        } else {
            engine.session.preflightSnapshot = preflight
            engine.start(from: entryContext)
        }
    }

    private func collectPreflight() async -> PreflightData {
        await PreflightCollector.collect(bottle: bottle, program: program, programURL: entryContext.programURL)
    }

    private func resumeSession(session: TroubleshootingSession) {
        engine.session = session
        // The resumed checks run against the bottle as it is now; the resume
        // screen has shown what changed since.
        if let currentPreflight {
            engine.session.preflightSnapshot = currentPreflight
        }
        if let nodeId = session.currentNodeId {
            engine.navigateToNode(nodeId)
        }
        showResumeOverlay = false
    }

    private func startOver() {
        sessionStore.deleteActiveSession(for: entryContext.bottleURL)
        engine.startOver()
        showResumeOverlay = false
    }

    private func discardSession() {
        sessionStore.deleteActiveSession(for: entryContext.bottleURL)
        showResumeOverlay = false
        dismiss()
    }
}

// MARK: - Fix Attempt Display

extension FixResult {
    /// The result in the user's language. Exports and issue drafts keep
    /// ``rawValue`` so they read the same in every language.
    var localizedName: String {
        switch self {
        case .pending: String(localized: "troubleshooting.fixResult.pending")
        case .applied: String(localized: "troubleshooting.fixResult.applied")
        case .verified: String(localized: "troubleshooting.fixResult.verified")
        case .failed: String(localized: "troubleshooting.fixResult.failed")
        case .undone: String(localized: "troubleshooting.fixResult.undone")
        }
    }
}

extension FixAttempt {
    /// A readable name for the attempted fix in the user's language.
    ///
    /// Falls back to the raw ``fixId`` for an id with no catalog entry.
    /// Exports and issue drafts keep ``fixId``.
    var localizedFixName: String {
        switch fixId {
        case "switch-backend": String(localized: "troubleshooting.fixName.switchBackend")
        case "enable-dxvk-async": String(localized: "troubleshooting.fixName.enableDxvkAsync")
        case "set-audio-driver": String(localized: "troubleshooting.fixName.setAudioDriver")
        case "set-buffer-size": String(localized: "troubleshooting.fixName.setBufferSize")
        case "enable-esync": String(localized: "troubleshooting.fixName.enableEsync")
        case "enable-controller-compat": String(localized: "troubleshooting.fixName.enableControllerCompat")
        case "install-winetricks-verb": String(localized: "troubleshooting.fixName.installWinetricksVerb")
        case "run-enhanced-diagnostics": String(localized: "troubleshooting.fixName.runEnhancedDiagnostics")
        case "set-registry-value": String(localized: "troubleshooting.fixName.setRegistryValue")
        case "apply-launcher-fixes": String(localized: "troubleshooting.fixName.applyLauncherFixes")
        case "apply-game-config": String(localized: "troubleshooting.fixName.applyGameConfig")
        case "restart-wineserver": String(localized: "troubleshooting.fixName.restartWineserver")
        default: fixId
        }
    }
}
