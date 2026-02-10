//
//  AudioSettingsView.swift
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

/// Audio settings controls with Simple/Advanced mode toggle.
///
/// Simple mode shows at most 2 controls (Audio Driver and Latency Preset).
/// Advanced mode adds all controls including output device pinning and
/// a destructive Reset Audio State button.
struct AudioSettingsView: View {
    @ObservedObject var bottle: Bottle
    let advancedMode: Bool

    @State private var isWritingDriver: Bool = false
    @State private var isWritingLatency: Bool = false
    @State private var isResettingAudioState: Bool = false
    @State private var showResetConfirmation: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            audioDriverPicker
            latencyPresetPicker
            if advancedMode {
                advancedControls
            }
        }
    }

    // MARK: - Audio Driver Picker

    private var audioDriverPicker: some View {
        HStack {
            Picker("Audio Driver", selection: $bottle.settings.audioDriver) {
                if advancedMode {
                    ForEach(AudioDriverMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                } else {
                    Text(AudioDriverMode.auto.displayName).tag(AudioDriverMode.auto)
                    Text(AudioDriverMode.disabled.displayName).tag(AudioDriverMode.disabled)
                }
            }
            if isWritingDriver {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .onChange(of: bottle.settings.audioDriver) { _, newValue in
            isWritingDriver = true
            Task { @MainActor in
                try? await Wine.setAudioDriver(bottle: bottle, driver: newValue)
                isWritingDriver = false
            }
        }
    }

    // MARK: - Latency Preset Picker

    private var latencyPresetPicker: some View {
        HStack {
            Picker("Latency", selection: $bottle.settings.audioLatencyPreset) {
                if advancedMode {
                    ForEach(AudioLatencyPreset.allCases, id: \.self) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                } else {
                    Text(AudioLatencyPreset.defaultPreset.displayName)
                        .tag(AudioLatencyPreset.defaultPreset)
                    Text(AudioLatencyPreset.stable.displayName)
                        .tag(AudioLatencyPreset.stable)
                }
            }
            if isWritingLatency {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .onChange(of: bottle.settings.audioLatencyPreset) { _, newValue in
            isWritingLatency = true
            Task { @MainActor in
                try? await Wine.setDirectSoundBuffer(bottle: bottle, helBuflen: newValue.helBuflenValue)
                isWritingLatency = false
            }
        }
    }

    // MARK: - Advanced Controls

    private var advancedControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            outputDeviceModePicker
            resetAudioStateButton
        }
    }

    // MARK: - Output Device Mode Picker

    private var outputDeviceModePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Output Device", selection: $bottle.settings.outputDeviceMode) {
                ForEach(OutputDeviceMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            if bottle.settings.outputDeviceMode == .pinned {
                HStack {
                    Text("Pinned device:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(bottle.settings.pinnedDeviceName ?? "Not set")
                        .font(.caption)
                        .foregroundStyle(bottle.settings.pinnedDeviceName != nil ? .primary : .tertiary)
                }
            }
        }
    }

    // MARK: - Reset Audio State

    private var resetAudioStateButton: some View {
        HStack {
            Button("Reset Audio State") {
                showResetConfirmation = true
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .controlSize(.small)
            .disabled(isResettingAudioState)
            .alert("Reset Audio State?", isPresented: $showResetConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    performReset()
                }
            } message: {
                Text("This will clear Wine cached audio device mappings and restart the Wine server.")
            }
            if isResettingAudioState {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private func performReset() {
        isResettingAudioState = true
        Task { @MainActor in
            try? await Wine.resetAudioState(bottle: bottle)
            isResettingAudioState = false
        }
    }
}
