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
        .onAppear(perform: onAppear)
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
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            stepIndicator
            Spacer()
            HStack(spacing: 8) {
                Button("Back") { engine.goBack() }
                    .disabled(engine.session.stepHistory.count <= 1)
                Button("Skip") { engine.skipStep() }
                    .disabled(engine.currentNode == nil)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var stepIndicator: some View {
        Group {
            let totalSteps = engine.session.stepHistory.count
            if totalSteps > 0 {
                Text("Step \(totalSteps)")
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
            } else {
                checksPlaceholder
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
            Text("Running checks\u{2026}")
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
            Text("Problem Resolved")
                .font(.title2)
                .fontWeight(.semibold)

            if !engine.session.fixAttempts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Changes applied:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(engine.session.fixAttempts, id: \.fixId) { attempt in
                        HStack(spacing: 6) {
                            Image(systemName: resultIcon(for: attempt.result))
                                .font(.caption)
                                .foregroundStyle(resultColor(for: attempt.result))
                            Text(attempt.fixId)
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
    private func onAppear() {
        // Configure session with bottle/program context
        engine.session.bottleURL = entryContext.bottleURL
        engine.session.programURL = entryContext.programURL

        // Check for existing active session
        if let existingSession = sessionStore.loadActiveSession(for: entryContext.bottleURL) {
            let currentPreflight = collectPreflight()
            stalenessChanges = sessionStore.checkStaleness(
                session: existingSession,
                currentPreflight: currentPreflight
            )
            resumeSession = existingSession
            showResumeOverlay = true
        } else {
            // Collect preflight and populate session
            let preflight = collectPreflight()
            engine.session.preflightSnapshot = preflight
            engine.session.phase = entryContext.initialPhase

            // If entry context provides evidence, start at checks phase
            if case let .launchFailure(_, _, evidence) = entryContext {
                engine.session.phase = .checks
                // Pre-populate with launch crash category
                engine.selectCategory(.launchCrash)
                _ = evidence
            }
        }
    }

    private func collectPreflight() -> PreflightData {
        PreflightData(
            bottleURL: entryContext.bottleURL,
            bottleName: bottle.settings.name,
            programURL: entryContext.programURL,
            programName: program?.name,
            isWineserverRunning: false,
            processCount: 0,
            graphicsBackend: bottle.settings.graphicsBackend.rawValue
        )
    }

    private func resumeSession(session: TroubleshootingSession) {
        engine.session = session
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
