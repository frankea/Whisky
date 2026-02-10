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
    @State private var showTroubleshootingWizard: Bool = false

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
                },
                onTestComplete: { results in
                    probeResults = results
                },
                testExeURL: Bundle.main.url(forResource: "WhiskyAudioTest", withExtension: "exe")
            )

            // 3. Simple/Advanced toggle
            Picker("", selection: $advancedMode) {
                Text("Simple").tag(false)
                Text("Advanced").tag(true)
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
                AudioFindingsView(findings: currentFindings, onApplyFix: handleApplyFix)
            }

            // 7. Troubleshooting link
            Button("Audio Troubleshooting\u{2026}") {
                showTroubleshootingWizard = true
            }
        }
        .animation(.default, value: advancedMode)
        .onAppear {
            // AudioDeviceMonitor dispatches on DispatchQueue.main.
            // The @Sendable closure annotation causes a compiler warning,
            // but mutation is main-thread-safe since the callback runs on main queue.
            monitor.startListening { _ in
                audioStatus = .unknown
            }
        }
        .sheet(isPresented: $showTroubleshootingWizard) {
            troubleshootingWizardPlaceholder
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

// MARK: - Fix Application

extension AudioConfigSection {
    private func handleApplyFix(_ actionId: String) {
        Task { @MainActor in
            switch actionId {
            case "check-audio-driver", "set-coreaudio-driver":
                bottle.settings.audioDriver = .coreaudio
                try? await Wine.setAudioDriver(bottle: bottle, driver: .coreaudio)
            case "set-stable-latency":
                bottle.settings.audioLatencyPreset = .stable
                try? await Wine.setDirectSoundBuffer(
                    bottle: bottle,
                    helBuflen: AudioLatencyPreset.stable.helBuflenValue
                )
            case "reset-audio-state":
                try? await Wine.resetAudioState(bottle: bottle)
            default:
                break
            }
        }
    }
}

// MARK: - Troubleshooting Wizard Placeholder

extension AudioConfigSection {
    /// Placeholder for the full troubleshooting wizard (Plan 06-05).
    private var troubleshootingWizardPlaceholder: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "waveform.badge.magnifyingglass")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Audio Troubleshooting")
                    .font(.title2)
                Text("The guided troubleshooting wizard will be available in a future update.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        showTroubleshootingWizard = false
                    }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}
