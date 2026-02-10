//
//  AudioTransportType.swift
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

import CoreAudio
import Foundation

/// Maps CoreAudio transport type constants to Swift cases for audio device classification.
public enum AudioTransportType: String, Sendable, Codable, Equatable {
    case builtIn
    case usb
    case bluetooth
    case airPlay
    case hdmi
    case displayPort
    case thunderbolt
    case virtual
    case aggregate
    case unknown

    /// Creates a transport type from a CoreAudio transport type constant.
    ///
    /// - Parameter coreAudioTransportType: A `UInt32` value from CoreAudio
    ///   (e.g. `kAudioDeviceTransportTypeBuiltIn`).
    public init(coreAudioTransportType: UInt32) {
        switch coreAudioTransportType {
        case kAudioDeviceTransportTypeBuiltIn: self = .builtIn
        case kAudioDeviceTransportTypeUSB: self = .usb
        case kAudioDeviceTransportTypeBluetooth: self = .bluetooth
        case kAudioDeviceTransportTypeAirPlay: self = .airPlay
        case kAudioDeviceTransportTypeHDMI: self = .hdmi
        case kAudioDeviceTransportTypeDisplayPort: self = .displayPort
        case kAudioDeviceTransportTypeThunderbolt: self = .thunderbolt
        case kAudioDeviceTransportTypeVirtual: self = .virtual
        case kAudioDeviceTransportTypeAggregate: self = .aggregate
        default: self = .unknown
        }
    }

    /// Human-readable display name for the transport type.
    public var displayName: String {
        switch self {
        case .builtIn: "Built-in"
        case .usb: "USB"
        case .bluetooth: "Bluetooth"
        case .airPlay: "AirPlay"
        case .hdmi: "HDMI"
        case .displayPort: "DisplayPort"
        case .thunderbolt: "Thunderbolt"
        case .virtual: "Virtual"
        case .aggregate: "Aggregate"
        case .unknown: "Unknown"
        }
    }
}
