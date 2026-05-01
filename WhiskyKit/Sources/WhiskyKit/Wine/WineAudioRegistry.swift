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
