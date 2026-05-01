//
//  AudioDeviceChangeEvent.swift
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

/// A recorded change in the audio device configuration.
///
/// Events are stored in ``AudioDeviceHistory`` for troubleshooting context.
/// Per project decisions, only the device display name and transport type are
/// stored -- no unique hardware identifiers.
public struct AudioDeviceChangeEvent: Sendable, Codable, Equatable, Identifiable {
    /// Unique identifier for this event.
    public let id: UUID

    /// When the change was detected.
    public let timestamp: Date

    /// The type of change that occurred.
    public let eventType: EventType

    /// The display name of the affected device.
    public let deviceName: String

    /// The transport type of the affected device.
    public let transportType: AudioTransportType

    /// Types of device change events tracked by the audio subsystem.
    public enum EventType: String, Sendable, Codable, Equatable {
        /// The system default output device changed.
        case defaultOutputChanged
        /// A previously connected device was disconnected.
        case disconnected
        /// A previously disconnected device was reconnected.
        case reconnected
        /// The nominal sample rate of a device changed.
        case sampleRateChanged
    }

    public init(
        timestamp: Date,
        eventType: EventType,
        deviceName: String,
        transportType: AudioTransportType
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.eventType = eventType
        self.deviceName = deviceName
        self.transportType = transportType
    }
}
