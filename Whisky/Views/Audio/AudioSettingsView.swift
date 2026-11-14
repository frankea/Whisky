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
    @State private var outputDevices: [AudioDeviceInfo] = []

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
            Picker("config.audio.driver", selection: $bottle.settings.audioDriver) {
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
            Picker("config.audio.latency", selection: $bottle.settings.audioLatencyPreset) {
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
            Picker("config.audio.device.output", selection: $bottle.settings.outputDeviceMode) {
                ForEach(OutputDeviceMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            if bottle.settings.outputDeviceMode == .pinned {
                pinnedDevicePicker
                if bottle.settings.pinnedDeviceUID != nil {
                    Text("config.audio.device.pinned.footer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            outputDevices = AudioDeviceMonitor().allOutputDevices().filter { $0.uid != nil }
        }
    }

    private var pinnedDevicePicker: some View {
        Picker("config.audio.device.pinnedLabel", selection: pinnedUIDBinding) {
            Text("config.buildVersion.notSet").tag(String?.none)
            ForEach(outputDevices, id: \.uid) { device in
                Text(device.name).tag(device.uid)
            }
            if let storedUID = bottle.settings.pinnedDeviceUID,
               !outputDevices.contains(where: { $0.uid == storedUID }) {
                let storedName = bottle.settings.pinnedDeviceName ?? storedUID
                Text(String(format: String(localized: "config.audio.device.disconnected"), storedName))
                    .tag(String?.some(storedUID))
            }
        }
    }

    /// Selects a device by CoreAudio UID, keeping its name for display while disconnected.
    private var pinnedUIDBinding: Binding<String?> {
        Binding(
            get: { bottle.settings.pinnedDeviceUID },
            set: { newUID in
                if let device = outputDevices.first(where: { $0.uid == newUID }) {
                    bottle.settings.pinnedDeviceName = device.name
                } else if newUID == nil {
                    bottle.settings.pinnedDeviceName = nil
                }
                bottle.settings.pinnedDeviceUID = newUID
            }
        )
    }

    // MARK: - Reset Audio State

    private var resetAudioStateButton: some View {
        HStack {
            Button("config.audio.resetState") {
                showResetConfirmation = true
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .controlSize(.small)
            .disabled(isResettingAudioState)
            .alert("config.audio.resetState.title", isPresented: $showResetConfirmation) {
                Button("button.cancel", role: .cancel) {}
                Button("config.dxvk.reset", role: .destructive) {
                    performReset()
                }
            } message: {
                Text("config.audio.resetState.message")
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
