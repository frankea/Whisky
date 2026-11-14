//
//  WineAudioEndpointTests.swift
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

@Suite("Wine Audio Endpoint Tests")
struct WineAudioEndpointTests {
    private static let sample = UUID(uuidString: "B3F8FA53-0004-438E-9003-51A46E139BFC")

    @Test("REG_BINARY hex uses the Windows GUID byte order")
    func registryHexByteOrder() throws {
        let uuid = try #require(Self.sample)
        #expect(WineAudioEndpoint.registryHex(for: uuid) == "53FAF8B304008E43900351A46E139BFC")
    }

    @Test("Registry hex round-trips to the same UUID")
    func registryHexRoundTrips() throws {
        let uuid = try #require(Self.sample)
        #expect(WineAudioEndpoint.uuid(fromRegistryHex: WineAudioEndpoint.registryHex(for: uuid)) == uuid)

        let random = UUID()
        #expect(WineAudioEndpoint.uuid(fromRegistryHex: WineAudioEndpoint.registryHex(for: random)) == random)
    }

    @Test("Lowercase hex and surrounding whitespace parse")
    func lowercaseHexParses() throws {
        let uuid = try #require(Self.sample)
        #expect(WineAudioEndpoint.uuid(fromRegistryHex: "53faf8b304008e43900351a46e139bfc") == uuid)
        #expect(WineAudioEndpoint.uuid(fromRegistryHex: " 53FAF8B304008E43900351A46E139BFC\r\n") == uuid)
    }

    @Test("Malformed hex is rejected", arguments: [
        "",
        "53FAF8B304008E43900351A46E139BF",
        "53FAF8B304008E43900351A46E139B",
        "53FAF8B304008E43900351A46E139BFC00",
        "53FAF8B304008E43900351A46E139BZZ",
        "+3FAF8B304008E43900351A46E139BFC",
        "REG_BINARY"
    ])
    func malformedHexIsRejected(hex: String) {
        #expect(WineAudioEndpoint.uuid(fromRegistryHex: hex) == nil)
    }

    @Test("Endpoint ID matches Wine's render ID format")
    func endpointIDFormat() throws {
        let uuid = try #require(Self.sample)
        let endpointID = WineAudioEndpoint.endpointID(for: uuid)
        #expect(endpointID == "{0.0.0.00000000}.{B3F8FA53-0004-438E-9003-51A46E139BFC}")
        // Wine reads DefaultOutput into a 64-character buffer.
        #expect(endpointID.count <= 63)
    }

    @Test("Render device key appends the UID to the devices subkey")
    func renderDeviceKey() {
        #expect(
            WineAudioEndpoint.renderDeviceKey(uid: "BuiltInSpeakerDevice")
                == #"HKCU\Software\Wine\Drivers\winecoreaudio.drv\devices\0,BuiltInSpeakerDevice"#
        )
        #expect(
            WineAudioEndpoint.renderDeviceKey(uid: "AppleUSBAudioEngine:Vendor:DAC:1234:1")
                == #"HKCU\Software\Wine\Drivers\winecoreaudio.drv\devices\0,AppleUSBAudioEngine:Vendor:DAC:1234:1"#
        )
    }

    @Test("Empty UIDs and UIDs with a backslash have no device key")
    func invalidUIDsHaveNoKey() {
        #expect(WineAudioEndpoint.renderDeviceKey(uid: "") == nil)
        #expect(WineAudioEndpoint.renderDeviceKey(uid: #"Bad\UID"#) == nil)
    }
}
