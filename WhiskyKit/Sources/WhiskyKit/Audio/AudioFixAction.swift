//
//  AudioFixAction.swift
//  WhiskyKit
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

import Foundation

/// A change Whisky can make for an audio finding or a troubleshooting wizard step.
///
/// Findings and wizard steps carry string ids; this type is what those ids
/// resolve to, so a Fix button exists only where there is something to apply.
public enum AudioFixAction: String, CaseIterable, Sendable {
    /// Turns the Wine audio driver back on (Auto) if it is disabled, and
    /// writes the bottle's driver setting to the registry.
    case enableAudioDriver

    /// Sets the Wine audio driver to CoreAudio.
    case useCoreAudioDriver

    /// Restores the default DirectSound buffer size.
    case useDefaultLatency

    /// Switches to the larger DirectSound buffer of the Stable preset.
    case useStableLatency

    /// Clears Wine's cached audio device mappings and restarts the bottle's wineserver.
    case resetAudioState

    /// ``enableAudioDriver`` followed by ``resetAudioState``: the general
    /// repair for Wine producing no sound.
    case restoreAudio

    /// Opens the Sound pane of System Settings. Changes nothing in the bottle.
    case openSoundSettings

    /// The Sound pane of System Settings.
    public static let soundSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")

    /// The fix for a finding from the audio probes or the test tone check.
    ///
    /// - Parameter findingId: An ``AudioFinding/id``.
    /// - Returns: `nil` for findings that are advice only, such as a Bluetooth device.
    public init?(findingId: String) {
        switch findingId {
        case "audio-disabled":
            self = .enableAudioDriver
        case "low-buffer-size":
            self = .useDefaultLatency
        case "tone-not-audible", "wine-audio-test-error":
            self = .restoreAudio
        case "no-default-device", "no-output-channels":
            self = .openSoundSettings
        default:
            return nil
        }
    }

    /// The fix behind a troubleshooting wizard step.
    ///
    /// - Parameter troubleshootingActionId: A step id such as `"reset-audio-state"`,
    ///   as offered by ``AudioTroubleshootingEngine``.
    public init?(troubleshootingActionId: String) {
        switch troubleshootingActionId {
        case "check-audio-driver":
            self = .enableAudioDriver
        case "set-coreaudio-driver":
            self = .useCoreAudioDriver
        case "set-stable-latency":
            self = .useStableLatency
        case "check-dsound":
            self = .useDefaultLatency
        case "reset-audio-state":
            self = .resetAudioState
        case "check-system-settings":
            self = .openSoundSettings
        default:
            return nil
        }
    }

    /// Whether applying the fix closes the programs running in the bottle.
    public var closesRunningPrograms: Bool {
        switch self {
        case .resetAudioState, .restoreAudio:
            true
        default:
            false
        }
    }

    /// Whether the fix changes the bottle, as opposed to opening System Settings.
    public var changesBottle: Bool {
        self != .openSoundSettings
    }

    /// Applies the fix's change to bottle settings.
    ///
    /// Registry writes and the wineserver restart happen in
    /// ``Wine/applyAudioFix(_:bottle:)``, which calls this first.
    public func updateSettings(_ settings: inout BottleSettings) {
        switch self {
        case .enableAudioDriver, .restoreAudio:
            if settings.audioDriver == .disabled {
                settings.audioDriver = .auto
            }
        case .useCoreAudioDriver:
            settings.audioDriver = .coreaudio
        case .useDefaultLatency:
            settings.audioLatencyPreset = .defaultPreset
        case .useStableLatency:
            settings.audioLatencyPreset = .stable
        case .resetAudioState, .openSoundSettings:
            break
        }
    }
}

public extension Wine {
    /// Applies an audio fix to a bottle.
    ///
    /// Updates the bottle's settings, then writes the affected registry value
    /// directly rather than waiting for the launch-time sync, so the next audio
    /// test sees the change and a value edited outside Whisky is corrected too.
    /// ``AudioFixAction/openSoundSettings`` changes nothing here; the app opens
    /// System Settings for it.
    @MainActor
    static func applyAudioFix(_ action: AudioFixAction, bottle: Bottle) async throws {
        action.updateSettings(&bottle.settings)
        switch action {
        case .enableAudioDriver, .useCoreAudioDriver:
            try await setAudioDriver(bottle: bottle, driver: bottle.settings.audioDriver)
        case .useDefaultLatency, .useStableLatency:
            try await setDirectSoundBuffer(
                bottle: bottle,
                helBuflen: bottle.settings.audioLatencyPreset.helBuflenValue
            )
        case .resetAudioState:
            try await resetAudioState(bottle: bottle)
        case .restoreAudio:
            try await setAudioDriver(bottle: bottle, driver: bottle.settings.audioDriver)
            try await resetAudioState(bottle: bottle)
        case .openSoundSettings:
            break
        }
    }
}
