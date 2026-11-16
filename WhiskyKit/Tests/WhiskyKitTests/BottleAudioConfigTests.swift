//
//  BottleAudioConfigTests.swift
//  WhiskyKitTests
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
import Testing
@testable import WhiskyKit

@Suite("Bottle Audio Config Tests")
struct BottleAudioConfigTests {
    private func decode(_ dictionary: [String: Any]) throws -> BottleAudioConfig {
        let data = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
        return try PropertyListDecoder().decode(BottleAudioConfig.self, from: data)
    }

    @Test("A pin saved before device UIDs existed still decodes")
    func legacyPinDecodes() throws {
        let config = try decode([
            "outputDeviceMode": "pinned",
            "pinnedDeviceName": "External Headphones"
        ])

        #expect(config.outputDeviceMode == .pinned)
        #expect(config.pinnedDeviceName == "External Headphones")
        #expect(config.pinnedDeviceUID == nil)
    }

    @Test("An unknown output device mode decodes to following the system")
    func unknownModeFollowsSystem() throws {
        let config = try decode(["outputDeviceMode": "bogus"])
        #expect(config.outputDeviceMode == .followSystem)
    }

    @Test("Wrongly typed device fields decode to nil instead of throwing")
    func wronglyTypedDeviceFieldsAreNil() throws {
        let config = try decode([
            "outputDeviceMode": "pinned",
            "pinnedDeviceName": 42,
            "pinnedDeviceUID": ["not", "a", "string"]
        ])

        #expect(config.outputDeviceMode == .pinned)
        #expect(config.pinnedDeviceName == nil)
        #expect(config.pinnedDeviceUID == nil)
    }

    @Test("The pinned device round-trips through the bottle settings plist")
    func pinnedDeviceRoundTrips() throws {
        var settings = BottleSettings()
        settings.outputDeviceMode = .pinned
        settings.pinnedDeviceName = "External Headphones"
        settings.pinnedDeviceUID = "AppleUSBAudioEngine:Vendor:DAC:1234:1"

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let decoded = try PropertyListDecoder().decode(BottleSettings.self, from: encoder.encode(settings))

        #expect(decoded.outputDeviceMode == .pinned)
        #expect(decoded.pinnedDeviceName == "External Headphones")
        #expect(decoded.pinnedDeviceUID == "AppleUSBAudioEngine:Vendor:DAC:1234:1")
    }
}
