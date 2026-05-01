//
//  BottleAudioConfig.swift
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

/// The audio driver mode for a Wine bottle.
///
/// Controls which audio driver Wine uses at launch time.
/// `.auto` defers the choice to Wine's built-in auto-detection,
/// which selects CoreAudio on macOS.
public enum AudioDriverMode: String, Codable, CaseIterable, Equatable, Sendable {
    /// Let Wine choose the best audio driver (recommended).
    case auto
    /// Force the CoreAudio driver.
    case coreaudio
    /// Disable audio entirely.
    case disabled

    /// A human-readable display name for this driver mode.
    public var displayName: String {
        switch self {
        case .auto:
            String(localized: "config.audio.driver.auto")
        case .coreaudio:
            "CoreAudio"
        case .disabled:
            String(localized: "config.audio.driver.disabled")
        }
    }

    /// The Wine registry value for `HKCU\Software\Wine\Drivers` Audio key.
    ///
    /// Returns `nil` for `.auto`, which means the registry key should be
    /// removed to let Wine auto-detect the driver.
    public var registryValue: String? {
        switch self {
        case .auto:
            nil
        case .coreaudio:
            "coreaudio"
        case .disabled:
            ""
        }
    }
}

/// The audio latency preset for a Wine bottle.
///
/// Controls the DirectSound `HelBuflen` registry value, which determines
/// the audio buffer size. Smaller buffers reduce latency but may cause
/// crackling on slower systems or Bluetooth audio.
public enum AudioLatencyPreset: String, Codable, CaseIterable, Equatable, Sendable {
    /// Wine default buffer size (recommended for most setups).
    case defaultPreset
    /// Low latency buffer for responsive audio.
    case lowLatency
    /// Larger buffer for stability with Bluetooth or USB audio.
    case stable

    /// A human-readable display name for this latency preset.
    public var displayName: String {
        switch self {
        case .defaultPreset:
            String(localized: "config.audio.latency.default")
        case .lowLatency:
            String(localized: "config.audio.latency.low")
        case .stable:
            String(localized: "config.audio.latency.stable")
        }
    }

    /// The DirectSound `HelBuflen` value in bytes for this preset.
    public var helBuflenValue: Int {
        switch self {
        case .defaultPreset:
            65_536
        case .lowLatency:
            512
        case .stable:
            131_072
        }
    }
}

/// The output device routing mode for a Wine bottle.
///
/// Controls whether Wine follows the macOS default output device
/// or is pinned to a specific device by name.
public enum OutputDeviceMode: String, Codable, CaseIterable, Equatable, Sendable {
    /// Follow the macOS default output device (recommended).
    case followSystem
    /// Pin audio output to a specific device by name.
    case pinned

    /// A human-readable display name for this device mode.
    public var displayName: String {
        switch self {
        case .followSystem:
            String(localized: "config.audio.device.followSystem")
        case .pinned:
            String(localized: "config.audio.device.pinned")
        }
    }
}

/// Stores the audio configuration for a bottle.
///
/// This config is serialized alongside other bottle config groups in
/// ``BottleSettings``. The defensive `init(from:)` ensures unknown or
/// corrupt values decode gracefully to defaults.
public struct BottleAudioConfig: Codable, Equatable {
    /// The selected audio driver mode. Defaults to `.auto`.
    var audioDriver: AudioDriverMode = .auto

    /// The audio latency preset. Defaults to `.defaultPreset`.
    var latencyPreset: AudioLatencyPreset = .defaultPreset

    /// The output device routing mode. Defaults to `.followSystem`.
    var outputDeviceMode: OutputDeviceMode = .followSystem

    /// The name of the pinned output device, if any.
    var pinnedDeviceName: String?

    /// Creates a new audio config with default values.
    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.audioDriver = try container.decodeIfPresent(
            AudioDriverMode.self, forKey: .audioDriver
        ) ?? .auto
        self.latencyPreset = try container.decodeIfPresent(
            AudioLatencyPreset.self, forKey: .latencyPreset
        ) ?? .defaultPreset
        self.outputDeviceMode = try container.decodeIfPresent(
            OutputDeviceMode.self, forKey: .outputDeviceMode
        ) ?? .followSystem
        self.pinnedDeviceName = try container.decodeIfPresent(
            String.self, forKey: .pinnedDeviceName
        )
    }
}
