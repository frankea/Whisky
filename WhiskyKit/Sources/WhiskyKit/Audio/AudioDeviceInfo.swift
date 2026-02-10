//
//  AudioDeviceInfo.swift
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

/// Information about a single audio output device.
///
/// A pure data type populated by ``AudioDeviceMonitor``. Contains no CoreAudio
/// imports and can be used safely from any context.
public struct AudioDeviceInfo: Sendable, Codable, Equatable, Identifiable {
    /// Stable identifier derived from the device name and transport type.
    public var id: String {
        "\(name)-\(transportType.rawValue)"
    }

    /// The display name of the audio device.
    public let name: String

    /// The connection transport type (Built-in, USB, Bluetooth, etc.).
    public let transportType: AudioTransportType

    /// The nominal sample rate in Hz (e.g. 44100, 48000).
    public let sampleRate: Double

    /// The number of output channels (e.g. 2 for stereo).
    public let outputChannelCount: Int

    /// Whether this device is the current system default output device.
    public let isDefault: Bool

    public init(
        name: String,
        transportType: AudioTransportType,
        sampleRate: Double,
        outputChannelCount: Int,
        isDefault: Bool
    ) {
        self.name = name
        self.transportType = transportType
        self.sampleRate = sampleRate
        self.outputChannelCount = outputChannelCount
        self.isDefault = isDefault
    }
}
