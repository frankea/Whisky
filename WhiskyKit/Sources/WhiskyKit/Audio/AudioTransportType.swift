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
public enum AudioTransportType: String, Sendable, Codable, Equatable, CaseIterable {
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

    /// Display name for the transport type in the app's language.
    ///
    /// Only the generic words are translated; USB, Bluetooth, AirPlay, HDMI,
    /// DisplayPort, and Thunderbolt are standard names and stay as they are.
    /// The English default is what a lookup without the app's string catalog
    /// (such as the package tests) returns. Stored preflight data and exports
    /// use ``exportName``.
    public var displayName: String {
        switch self {
        case .builtIn: String(localized: "audio.transport.builtIn", defaultValue: "Built-in")
        case .virtual: String(localized: "audio.transport.virtual", defaultValue: "Virtual")
        case .aggregate: String(localized: "audio.transport.aggregate", defaultValue: "Aggregate")
        case .unknown: String(localized: "audio.transport.unknown", defaultValue: "Unknown")
        case .usb, .bluetooth, .airPlay, .hdmi, .displayPort, .thunderbolt: exportName
        }
    }

    /// English name of the transport type, for stored preflight data and exports.
    public var exportName: String {
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
