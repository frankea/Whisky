//
//  WineAudioOutputPinTests.swift
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

/// An in-memory registry with knobs for the ways `wine reg` misbehaves.
@MainActor
private final class FakeAudioEndpointRegistry: AudioEndpointRegistry {
    struct Entry: Equatable {
        let key: String
        let name: String
    }

    var values: [String: [String: String]] = [:]
    /// Writes to these values report success but store nothing.
    var droppedWrites: Set<String> = []
    /// A GUID another Wine process stores just before ours is written.
    var racingGUID: UUID?
    var failDeletes = false
    private(set) var adds: [Entry] = []
    private(set) var deletes: [Entry] = []

    func query(key: String, name: String, type: RegistryType) async -> String? {
        values[key]?[name]
    }

    func add(key: String, name: String, data: String, type: RegistryType) async throws {
        adds.append(Entry(key: key, name: name))
        guard !droppedWrites.contains(name) else { return }
        if name == WineAudioEndpoint.guidValue, let racingGUID {
            values[key, default: [:]][name] = WineAudioEndpoint.registryHex(for: racingGUID)
            return
        }
        values[key, default: [:]][name] = data
    }

    func delete(key: String, name: String) async throws {
        deletes.append(Entry(key: key, name: name))
        if failDeletes {
            throw CocoaError(.fileNoSuchFile)
        }
        values[key]?[name] = nil
    }
}

@Suite("Wine Audio Output Pin Tests")
@MainActor
struct WineAudioOutputPinTests {
    private let uid = "AppleUSBAudioEngine:Acme:Speaker:1"
    private var deviceKey: String {
        WineAudioEndpoint.renderDeviceKey(uid: uid) ?? ""
    }

    private let defaultOutput = (key: WineAudioEndpoint.driverKey, name: WineAudioEndpoint.defaultOutputValue)

    @Test("No device removes DefaultOutput")
    func followSystemDeletesDefaultOutput() async throws {
        let registry = FakeAudioEndpointRegistry()
        registry.values[defaultOutput.key] = [defaultOutput.name: "{0.0.0.00000000}.{OLD}"]

        try await WineAudioOutputPin.apply(uid: nil, registry: registry)

        #expect(registry.values[defaultOutput.key]?[defaultOutput.name] == nil)
        #expect(registry.adds.isEmpty)
    }

    @Test("A UID that isn't a usable key is treated as following the system", arguments: ["", #"bad\uid"#])
    func unusableUIDFollowsSystem(badUID: String) async throws {
        let registry = FakeAudioEndpointRegistry()

        try await WineAudioOutputPin.apply(uid: badUID, registry: registry)

        #expect(registry.deletes.count == 1)
        #expect(registry.adds.isEmpty)
    }

    @Test("A failed delete of a missing value is not an error")
    func missingValueDeleteIsQuiet() async throws {
        let registry = FakeAudioEndpointRegistry()
        registry.failDeletes = true

        try await WineAudioOutputPin.apply(uid: nil, registry: registry)

        #expect(registry.deletes.count == 1)
    }

    @Test("An existing endpoint GUID is reused, never replaced")
    func existingGUIDIsReused() async throws {
        let registry = FakeAudioEndpointRegistry()
        let stored = UUID()
        registry.values[deviceKey] = [WineAudioEndpoint.guidValue: WineAudioEndpoint.registryHex(for: stored)]

        try await WineAudioOutputPin.apply(uid: uid, registry: registry)

        #expect(registry.values[defaultOutput.key]?[defaultOutput.name] == WineAudioEndpoint.endpointID(for: stored))
        #expect(!registry.adds.contains { $0.key == deviceKey })
    }

    @Test("A device without a GUID gets one seeded and used")
    func missingGUIDIsSeeded() async throws {
        let registry = FakeAudioEndpointRegistry()

        try await WineAudioOutputPin.apply(uid: uid, registry: registry)

        let seeded = registry.values[deviceKey]?[WineAudioEndpoint.guidValue].flatMap(
            WineAudioEndpoint.uuid(fromRegistryHex:)
        )
        let guid = try #require(seeded)
        #expect(registry.values[defaultOutput.key]?[defaultOutput.name] == WineAudioEndpoint.endpointID(for: guid))
    }

    @Test("The GUID Wine ends up storing wins over the one generated")
    func storedGUIDWinsOverGenerated() async throws {
        let registry = FakeAudioEndpointRegistry()
        let winner = UUID()
        registry.racingGUID = winner

        try await WineAudioOutputPin.apply(uid: uid, registry: registry)

        #expect(registry.values[defaultOutput.key]?[defaultOutput.name] == WineAudioEndpoint.endpointID(for: winner))
    }

    @Test("A GUID that doesn't stick throws before DefaultOutput is written")
    func unstoredGUIDThrows() async {
        let registry = FakeAudioEndpointRegistry()
        registry.droppedWrites = [WineAudioEndpoint.guidValue]

        await #expect(throws: AudioRegistryWriteError.endpointGUIDNotStored) {
            try await WineAudioOutputPin.apply(uid: uid, registry: registry)
        }
        #expect(!registry.adds.contains { $0.name == WineAudioEndpoint.defaultOutputValue })
    }

    @Test("A DefaultOutput that doesn't stick throws")
    func unstoredDefaultOutputThrows() async {
        let registry = FakeAudioEndpointRegistry()
        registry.droppedWrites = [WineAudioEndpoint.defaultOutputValue]

        await #expect(throws: AudioRegistryWriteError.defaultOutputNotStored) {
            try await WineAudioOutputPin.apply(uid: uid, registry: registry)
        }
    }
}
