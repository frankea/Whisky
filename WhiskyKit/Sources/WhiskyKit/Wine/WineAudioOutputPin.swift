//
//  WineAudioOutputPin.swift
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
import os.log

private let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "WineAudioOutputPin")

/// Registry writes that `wine reg` reported as done but did not store.
enum AudioRegistryWriteError: Error {
    case endpointGUIDNotStored
    case defaultOutputNotStored
    case defaultOutputNotRemoved
}

/// The registry operations pinning Wine's default output needs.
///
/// Launches go through `wine reg` on the bottle; tests use an in-memory
/// registry, so the seeding and read-back logic runs without Wine.
@MainActor
protocol AudioEndpointRegistry {
    /// The value's data, or `nil` when it is missing or unreadable.
    func query(key: String, name: String, type: RegistryType) async -> String?
    func add(key: String, name: String, data: String, type: RegistryType) async throws
    func delete(key: String, name: String) async throws
}

/// ``AudioEndpointRegistry`` backed by a bottle's Wine registry.
@MainActor
struct BottleAudioEndpointRegistry: AudioEndpointRegistry {
    let bottle: Bottle

    func query(key: String, name: String, type: RegistryType) async -> String? {
        try? await Wine.queryRegistryKey(bottle: bottle, key: key, name: name, type: type)
    }

    func add(key: String, name: String, data: String, type: RegistryType) async throws {
        try await Wine.addRegistryKey(bottle: bottle, key: key, name: name, data: data, type: type)
    }

    func delete(key: String, name: String) async throws {
        try await Wine.deleteRegistryValue(bottle: bottle, key: key, name: name)
    }
}

/// Points Wine's default audio output at a CoreAudio device.
///
/// See ``WineAudioEndpoint`` for the registry layout Wine reads.
@MainActor
enum WineAudioOutputPin {
    /// Writes `DefaultOutput` as the device's endpoint ID, or removes it
    /// when `uid` is `nil` (or not a usable device UID) so Wine follows the
    /// macOS default.
    ///
    /// The device's endpoint GUID is read from the registry, or seeded when
    /// Wine has not stored one yet; an existing GUID is never replaced, since
    /// programs may have saved the endpoint ID it forms.
    ///
    /// - Throws: ``AudioRegistryWriteError`` when a write or removal did not stick, so
    ///   the caller keeps its marker stale and the next launch retries.
    static func apply(uid: String?, registry: some AudioEndpointRegistry) async throws {
        guard let uid, let deviceKey = WineAudioEndpoint.renderDeviceKey(uid: uid) else {
            do {
                try await registry.delete(
                    key: WineAudioEndpoint.driverKey,
                    name: WineAudioEndpoint.defaultOutputValue
                )
            } catch {
                // The value might not exist; this is expected
                logger.info("Default output device not pinned, nothing to remove")
            }
            // A failed delete of a value that does exist would leave the old
            // device pinned while the marker says the bottle follows macOS.
            let remaining = await registry.query(
                key: WineAudioEndpoint.driverKey,
                name: WineAudioEndpoint.defaultOutputValue,
                type: .string
            )
            guard remaining == nil else { throw AudioRegistryWriteError.defaultOutputNotRemoved }
            return
        }

        let guid = try await endpointGUID(deviceKey: deviceKey, registry: registry)
        let endpointID = WineAudioEndpoint.endpointID(for: guid)
        try await registry.add(
            key: WineAudioEndpoint.driverKey,
            name: WineAudioEndpoint.defaultOutputValue,
            data: endpointID,
            type: .string
        )

        // `wine reg` does not report failures through its exit status, so the
        // write is read back.
        let written = await registry.query(
            key: WineAudioEndpoint.driverKey,
            name: WineAudioEndpoint.defaultOutputValue,
            type: .string
        )
        guard written == endpointID else { throw AudioRegistryWriteError.defaultOutputNotStored }
    }

    /// The endpoint GUID Wine uses for a device, seeding one if none is stored.
    ///
    /// The GUID is always the one read back from the registry, never the one
    /// generated here: a Wine process in the bottle may store its own first,
    /// and Wine keeps whichever GUID is stored.
    private static func endpointGUID(deviceKey: String, registry: some AudioEndpointRegistry) async throws -> UUID {
        if let guid = await storedEndpointGUID(deviceKey: deviceKey, registry: registry) {
            return guid
        }

        try await registry.add(
            key: deviceKey,
            name: WineAudioEndpoint.guidValue,
            data: WineAudioEndpoint.registryHex(for: UUID()),
            type: .binary
        )
        guard let guid = await storedEndpointGUID(deviceKey: deviceKey, registry: registry) else {
            throw AudioRegistryWriteError.endpointGUIDNotStored
        }
        return guid
    }

    private static func storedEndpointGUID(deviceKey: String, registry: some AudioEndpointRegistry) async -> UUID? {
        let value = await registry.query(key: deviceKey, name: WineAudioEndpoint.guidValue, type: .binary)
        return value.flatMap(WineAudioEndpoint.uuid(fromRegistryHex:))
    }
}
