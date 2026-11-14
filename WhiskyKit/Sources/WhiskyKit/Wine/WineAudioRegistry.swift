//
//  WineAudioRegistry.swift
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

private let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "WineAudioRegistry")

/// The audio registry values Whisky last wrote into a bottle, kept as a
/// marker file so launches only spawn `wine reg` when the settings changed.
struct AudioRegistryState: Codable, Equatable {
    var driver: String
    var helBuflen: Int
    /// The CoreAudio UID written as Wine's default output, or `nil` when the
    /// bottle follows the macOS default. Markers written before this field
    /// existed decode with `nil`.
    var outputDeviceUID: String?

    /// What the bottle's current settings ask the registry to contain.
    @MainActor
    static func desired(for bottle: Bottle) -> AudioRegistryState {
        AudioRegistryState(
            driver: bottle.settings.audioDriver.rawValue,
            helBuflen: bottle.settings.audioLatencyPreset.helBuflenValue,
            outputDeviceUID: bottle.settings.outputDeviceMode == .pinned ? bottle.settings.pinnedDeviceUID : nil
        )
    }

    /// Auto driver detection and Wine's own default buffer size: the state
    /// a fresh prefix already has without any registry write.
    static let factoryDefault = AudioRegistryState(
        driver: AudioDriverMode.auto.rawValue,
        helBuflen: AudioLatencyPreset.defaultPreset.helBuflenValue
    )

    static func markerURL(in bottleURL: URL) -> URL {
        bottleURL.appending(path: ".audio-registry-state.plist")
    }

    static func load(from bottleURL: URL) -> AudioRegistryState? {
        guard let data = try? Data(contentsOf: markerURL(in: bottleURL)) else { return nil }
        return try? PropertyListDecoder().decode(AudioRegistryState.self, from: data)
    }

    func save(to bottleURL: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        try encoder.encode(self).write(to: Self.markerURL(in: bottleURL))
    }
}

/// The audio registry sync running for each bottle, keyed by bottle URL.
@MainActor
private enum AudioRegistrySyncQueue {
    static var inFlight: [URL: Task<Void, Never>] = [:]
}

/// Extension on ``Wine`` providing typed read/write methods for Wine audio registry keys.
///
/// Audio driver selection and DirectSound buffer configuration are stored in the Wine
/// registry rather than environment variables. This extension provides a clean API for
/// reading and writing those settings, as well as resetting audio device state.
public extension Wine {
    private enum AudioRegistryKey: String {
        case drivers = #"HKCU\Software\Wine\Drivers"#
        case directSound = #"HKCU\Software\Wine\DirectSound"#
        case mmDevices = #"HKLM\Software\Microsoft\Windows\CurrentVersion\MMDevices"#
    }

    /// Reads the current Wine audio driver setting from the registry.
    ///
    /// - Parameter bottle: The bottle whose registry to query.
    /// - Returns: The current audio driver value (e.g., `"coreaudio"`), or `nil` if not set.
    @MainActor
    static func readAudioDriver(bottle: Bottle) async throws -> String? {
        try await queryRegistryKey(
            bottle: bottle,
            key: AudioRegistryKey.drivers.rawValue,
            name: "Audio",
            type: .string
        )
    }

    /// Sets the Wine audio driver in the registry.
    ///
    /// For ``AudioDriverMode/auto``, the registry key is deleted so Wine
    /// auto-detects the best driver. For other modes, the appropriate
    /// driver value is written.
    ///
    /// - Parameters:
    ///   - bottle: The bottle whose registry to modify.
    ///   - driver: The audio driver mode to apply.
    @MainActor
    static func setAudioDriver(bottle: Bottle, driver: AudioDriverMode) async throws {
        if let value = driver.registryValue {
            try await addRegistryKey(
                bottle: bottle,
                key: AudioRegistryKey.drivers.rawValue,
                name: "Audio",
                data: value,
                type: .string
            )
        } else {
            // .auto: remove the key to let Wine auto-detect the driver
            do {
                try await runWine(
                    ["reg", "delete", AudioRegistryKey.drivers.rawValue, "/v", "Audio", "/f"],
                    bottle: bottle
                )
            } catch {
                // Key might not exist; this is expected
                logger.info("Audio driver key not present, nothing to remove")
            }
        }
    }

    /// Reads the current DirectSound buffer length from the registry.
    ///
    /// - Parameter bottle: The bottle whose registry to query.
    /// - Returns: The `HelBuflen` value as an integer, or `nil` if not set.
    @MainActor
    static func readDirectSoundBuffer(bottle: Bottle) async throws -> Int? {
        guard let value = try await queryRegistryKey(
            bottle: bottle,
            key: AudioRegistryKey.directSound.rawValue,
            name: "HelBuflen",
            type: .string
        )
        else {
            return nil
        }
        return Int(value)
    }

    /// Sets the DirectSound buffer length in the registry.
    ///
    /// Controls audio latency via the `HelBuflen` value. Smaller values reduce
    /// latency but may cause crackling. Larger values improve stability.
    ///
    /// - Parameters:
    ///   - bottle: The bottle whose registry to modify.
    ///   - helBuflen: The buffer length in bytes.
    @MainActor
    static func setDirectSoundBuffer(bottle: Bottle, helBuflen: Int) async throws {
        try await addRegistryKey(
            bottle: bottle,
            key: AudioRegistryKey.directSound.rawValue,
            name: "HelBuflen",
            data: String(helBuflen),
            type: .string
        )
    }

    /// Points Wine's default audio output at a CoreAudio device, or back at
    /// the macOS default.
    ///
    /// Writes `DefaultOutput` under the CoreAudio driver key as the device's
    /// endpoint ID. The device's endpoint GUID is read from the registry, or
    /// seeded when Wine has not stored one yet; an existing GUID is never
    /// replaced, since programs may have saved the endpoint ID it forms.
    /// Wine ignores the value while the device is disconnected.
    ///
    /// - Parameters:
    ///   - bottle: The bottle whose registry to modify.
    ///   - uid: The CoreAudio device UID, or `nil` to follow the macOS default.
    @MainActor
    static func setDefaultOutputDevice(bottle: Bottle, uid: String?) async throws {
        try await WineAudioOutputPin.apply(uid: uid, registry: BottleAudioEndpointRegistry(bottle: bottle))
    }

    /// Brings the bottle's Wine registry in line with its audio settings.
    ///
    /// The settings UI and the troubleshooting fixes only mutate
    /// ``BottleSettings``; the registry values Wine actually reads are written
    /// here, from the launch path, and only when the marker file shows they
    /// changed. A missing marker on factory settings is stamped without
    /// booting wineserver, since a fresh prefix already behaves that way.
    ///
    /// Syncs of one bottle run one after another, so two launches at once
    /// cannot interleave their writes; the later one finds the marker current.
    @MainActor
    static func syncAudioRegistry(bottle: Bottle) async {
        let bottleURL = bottle.url
        let previous = AudioRegistrySyncQueue.inFlight[bottleURL]
        let task = Task { @MainActor in
            await previous?.value
            await applyAudioRegistry(bottle: bottle)
        }
        AudioRegistrySyncQueue.inFlight[bottleURL] = task
        await task.value
        if AudioRegistrySyncQueue.inFlight[bottleURL] == task {
            AudioRegistrySyncQueue.inFlight[bottleURL] = nil
        }
    }

    @MainActor
    private static func applyAudioRegistry(bottle: Bottle) async {
        let desired = AudioRegistryState.desired(for: bottle)
        let applied = AudioRegistryState.load(from: bottle.url)
        guard desired != applied else { return }

        if applied == nil, desired == .factoryDefault {
            try? desired.save(to: bottle.url)
            return
        }

        do {
            if applied?.driver != desired.driver {
                try await setAudioDriver(bottle: bottle, driver: bottle.settings.audioDriver)
            }
            if applied?.helBuflen != desired.helBuflen {
                try await setDirectSoundBuffer(bottle: bottle, helBuflen: desired.helBuflen)
            }
            if applied?.outputDeviceUID != desired.outputDeviceUID {
                try await setDefaultOutputDevice(bottle: bottle, uid: desired.outputDeviceUID)
            }
            try desired.save(to: bottle.url)
        } catch {
            logger.error(
                "Audio registry sync failed for '\(bottle.settings.name)': \(error.localizedDescription)"
            )
        }
    }

    /// Resets Wine audio device state by clearing cached device mappings and restarting wineserver.
    ///
    /// This deletes the MMDevices registry subtree (which stores device GUID/UID mappings)
    /// and kills the wineserver to force a fresh audio device enumeration on next launch.
    ///
    /// - Parameter bottle: The bottle whose audio state to reset.
    @MainActor
    static func resetAudioState(bottle: Bottle) async throws {
        logger.info("Resetting audio state for bottle '\(bottle.settings.name)'")

        // Delete the MMDevices registry subtree to clear cached device mappings
        do {
            try await runWine(
                ["reg", "delete", AudioRegistryKey.mmDevices.rawValue, "/f"],
                bottle: bottle
            )
            logger.info("Cleared MMDevices registry subtree")
        } catch {
            // Subtree might not exist; this is expected on fresh bottles
            logger.info("MMDevices registry subtree not present, nothing to clear")
        }

        // Kill wineserver to force a fresh restart with re-enumerated devices
        Wine.killBottle(bottle: bottle)
        logger.info("Audio state reset complete for bottle '\(bottle.settings.name)'")
    }
}
