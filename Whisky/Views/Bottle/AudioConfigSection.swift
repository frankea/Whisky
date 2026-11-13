//
//  AudioConfigSection.swift
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

/// The main Audio section composing status, test buttons, settings, and findings.
///
/// Placed in ConfigView between Graphics and Performance, matching the
/// section-per-subsystem pattern established in Phase 4.
struct AudioConfigSection: View {
    @ObservedObject var bottle: Bottle

    @AppStorage("audioAdvancedMode") private var advancedMode: Bool = false
    @State private var monitor = AudioDeviceMonitor()

    @State private var audioStatus: AudioStatus = .unknown
    @State private var probeResults: [AudioProbeResult] = []
    @State private var lastTestedDate: Date?
    @State private var deviceHistory = AudioDeviceHistory()

    /// Debounce timer for Bluetooth device change events.
    @State private var debounceTask: Task<Void, Never>?

    /// The wizard and its engine, created when it opens. Item-based so the
    /// sheet is built from the engine that presents it; with a flag plus a
    /// separate optional the content closure could run before the engine
    /// landed and show an empty sheet.
    @State private var wizardPresentation: AudioWizardPresentation?

    /// A fix that closes running programs, waiting for the user to confirm it.
    @State private var pendingFix: PendingAudioFix?

    /// The outcome of the last fix applied from the findings list.
    @State private var fixOutcome: AudioFixOutcome?

    /// True while a findings-list fix is being applied.
    @State private var isApplyingFix = false

    var body: some View {
        Section("Audio") {
            // 1. Status line
            AudioStatusView(
                audioStatus: audioStatus,
                lastTestedDate: lastTestedDate,
                defaultDeviceName: monitor.defaultOutputDevice()?.name,
                transportType: monitor.defaultOutputDevice()?.transportType,
                sampleRate: monitor.defaultOutputDevice()?.sampleRate,
                channelCount: monitor.defaultOutputDevice()?.outputChannelCount
            )

            // 2. Test buttons row
            AudioTestButtonsView(
                bottle: bottle,
                onStatusUpdate: { status in
                    audioStatus = status
                    lastTestedDate = Date()
                    fixOutcome = nil
                },
                onTestComplete: { results in
                    probeResults = results
                    fixOutcome = nil
                },
                testExeURL: Bundle.main.url(forResource: "WhiskyAudioTest", withExtension: "exe")
            )
            .disabled(isApplyingFix)

            // 3. Simple/Advanced toggle
            Picker("", selection: $advancedMode) {
                Text("config.graphics.simple").tag(false)
                Text("config.graphics.advanced").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            // 4. Settings
            AudioSettingsView(bottle: bottle, advancedMode: advancedMode)

            // 5. Badge if advanced overrides in Simple mode
            if !advancedMode, hasAdvancedAudioOverrides {
                advancedOverridesBadge
            }

            // 6. Findings (if any from last test)
            if !currentFindings.isEmpty {
                AudioFindingsView(findings: currentFindings, onApplyFix: requestFix)
                    .disabled(isApplyingFix)
            }
            if let fixOutcome {
                fixOutcomeLabel(fixOutcome)
            }

            // 7. Advanced device views
            if advancedMode {
                advancedDeviceViews
            }

            // 8. Troubleshooting link
            Button("Audio Troubleshooting\u{2026}") {
                openTroubleshootingWizard()
            }
        }
        .animation(.default, value: advancedMode)
        .onAppear {
            startDeviceListening()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openAudioTroubleshooting)) { _ in
            openTroubleshootingWizard()
        }
        .sheet(item: $wizardPresentation) { presentation in
            AudioTroubleshootingWizardView(
                engine: presentation.engine,
                onDismiss: {
                    wizardPresentation = nil
                },
                onOpenAdvanced: {
                    advancedMode = true
                },
                onApplyFix: applyWizardFix
            )
        }
        .confirmationDialog(
            AudioTroubleshootingEngine.fixDescription(for: "reset-audio-state"),
            isPresented: Binding(get: { pendingFix != nil }, set: { if !$0 { pendingFix = nil } }),
            presenting: pendingFix
        ) { pending in
            Button("audio.troubleshoot.applyFix") {
                applyFix(pending.action, for: pending.finding)
            }
            Button("button.cancel", role: .cancel) {}
        } message: { _ in
            Text("audio.fix.closesPrograms")
        }
    }
}

// MARK: - Computed Properties

extension AudioConfigSection {
    /// True if any advanced-only audio settings differ from defaults.
    private var hasAdvancedAudioOverrides: Bool {
        bottle.settings.audioDriver != .auto
            || bottle.settings.audioLatencyPreset != .defaultPreset
            || bottle.settings.outputDeviceMode != .followSystem
    }

    /// Aggregated findings from the most recent probe results.
    private var currentFindings: [AudioFinding] {
        probeResults.flatMap(\.findings)
    }
}

// MARK: - Advanced Overrides Badge

extension AudioConfigSection {
    private var advancedOverridesBadge: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
            Text("Advanced audio settings active")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Show") {
                advancedMode = true
            }
            .font(.caption)
        }
    }
}

// MARK: - Advanced Device Views

extension AudioConfigSection {
    private var advancedDeviceViews: some View {
        Group {
            DisclosureGroup(String(localized: "audio.devices.title")) {
                AudioDeviceListView(devices: monitor.allOutputDevices())
            }

            DisclosureGroup(String(localized: "audio.history.title")) {
                AudioDeviceHistoryView(history: deviceHistory)
            }
        }
    }
}

// MARK: - Fix Application

extension AudioConfigSection {
    /// Applies a finding's fix, first asking for confirmation when it would
    /// close programs and the bottle's wineserver is running.
    private func requestFix(_ finding: AudioFinding, _ action: AudioFixAction) {
        guard action.changesBottle else {
            openSoundSettings()
            return
        }
        guard action.closesRunningPrograms else {
            applyFix(action, for: finding)
            return
        }
        isApplyingFix = true
        Task { @MainActor in
            let running = await Wine.isWineserverRunning(for: bottle)
            isApplyingFix = false
            if running {
                pendingFix = PendingAudioFix(finding: finding, action: action)
            } else {
                applyFix(action, for: finding)
            }
        }
    }

    private func applyFix(_ action: AudioFixAction, for finding: AudioFinding) {
        isApplyingFix = true
        Task { @MainActor in
            defer { isApplyingFix = false }
            do {
                try await Wine.applyAudioFix(action, bottle: bottle)
            } catch {
                fixOutcome = .failed(error.localizedDescription)
                return
            }
            // The finding no longer describes the bottle; the status is
            // unknown until the user tests again.
            probeResults = probeResults.map { $0.removingFinding(id: finding.id) }
            audioStatus = .unknown
            fixOutcome = .applied
        }
    }

    /// Applies the fix behind a troubleshooting wizard step.
    ///
    /// - Returns: Why the fix failed, or `nil` when it was applied. On failure
    ///   the bottle is unchanged, so the section keeps its last results.
    private func applyWizardFix(_ actionId: String) async -> String? {
        guard let action = AudioFixAction(troubleshootingActionId: actionId) else { return nil }
        guard action.changesBottle else {
            openSoundSettings()
            return nil
        }
        do {
            try await Wine.applyAudioFix(action, bottle: bottle)
        } catch {
            return error.localizedDescription
        }
        // The section's last results describe the bottle before the fix.
        probeResults = []
        audioStatus = .unknown
        fixOutcome = nil
        return nil
    }

    private func openSoundSettings() {
        if let url = AudioFixAction.soundSettingsURL {
            NSWorkspace.shared.open(url)
        }
    }

    private func fixOutcomeLabel(_ outcome: AudioFixOutcome) -> some View {
        switch outcome {
        case .applied:
            Label("audio.fix.applied", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case let .failed(reason):
            Label("audio.fix.failed \(reason)", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Troubleshooting Wizard

extension AudioConfigSection {
    private func openTroubleshootingWizard() {
        let probes: [any AudioProbe] = [
            CoreAudioDeviceProbe(monitor: monitor),
            WineRegistryAudioProbe(bottle: bottle),
            WineAudioTestProbe(
                bottle: bottle,
                testExeURL: Bundle.main.url(forResource: "WhiskyAudioTest", withExtension: "exe")
            )
        ]
        wizardPresentation = AudioWizardPresentation(engine: AudioTroubleshootingEngine(probes: probes))
    }
}

// MARK: - Device Listening

extension AudioConfigSection {
    private func startDeviceListening() {
        // AudioDeviceMonitor dispatches on DispatchQueue.main.
        // The @Sendable closure annotation causes a compiler warning,
        // but mutation is main-thread-safe since the callback runs on main queue.
        monitor.startListening { event in
            // Record event in session history
            deviceHistory.append(event)

            // Debounce status update for Bluetooth connections (2-3 second delay)
            // to avoid spurious state changes during BT negotiation.
            debounceTask?.cancel()
            debounceTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                audioStatus = .unknown
            }
        }
    }
}

/// What the audio troubleshooting sheet is built from.
struct AudioWizardPresentation: Identifiable {
    let id = UUID()
    let engine: AudioTroubleshootingEngine
}

/// A findings-list fix waiting for the user to confirm it.
struct PendingAudioFix {
    let finding: AudioFinding
    let action: AudioFixAction
}

/// What happened to the last fix applied from the findings list.
enum AudioFixOutcome {
    case applied
    case failed(String)
}

private extension AudioProbeResult {
    /// This result without the finding with the given id.
    func removingFinding(id: String) -> AudioProbeResult {
        AudioProbeResult(
            probeId: probeId,
            status: status,
            summary: summary,
            evidence: evidence,
            findings: findings.filter { $0.id != id },
            timestamp: timestamp
        )
    }
}
