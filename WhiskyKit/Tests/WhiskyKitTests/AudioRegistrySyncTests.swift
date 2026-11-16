//
//  AudioRegistrySyncTests.swift
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

/// Covers the marker bookkeeping around ``Wine/syncAudioRegistry(bottle:)``.
/// The registry-writing path itself spawns wineserver and is deliberately
/// not exercised, same policy as the restart-wineserver fix.
@Suite("Audio Registry Sync Tests")
struct AudioRegistrySyncTests {
    private func makeBottleDir() -> (url: URL, cleanup: () -> Void) {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return (tempDir, { try? FileManager.default.removeItem(at: tempDir) })
    }

    @Test("Marker round-trips through the plist")
    func markerRoundTrips() throws {
        let (dir, cleanup) = makeBottleDir()
        defer { cleanup() }

        let state = AudioRegistryState(driver: "coreaudio", helBuflen: 131_072)
        try state.save(to: dir)

        #expect(AudioRegistryState.load(from: dir) == state)
    }

    @Test("A missing or corrupt marker loads as nil")
    func missingOrCorruptMarkerIsNil() throws {
        let (dir, cleanup) = makeBottleDir()
        defer { cleanup() }

        #expect(AudioRegistryState.load(from: dir) == nil)

        try Data("not a plist".utf8).write(to: AudioRegistryState.markerURL(in: dir))
        #expect(AudioRegistryState.load(from: dir) == nil)
    }

    @Test("Desired state mirrors the bottle's audio settings")
    @MainActor
    func desiredMirrorsSettings() {
        let (dir, cleanup) = makeBottleDir()
        defer { cleanup() }

        let bottle = Bottle(bottleUrl: dir, inFlight: false, isAvailable: true)
        bottle.settings.audioDriver = .coreaudio
        bottle.settings.audioLatencyPreset = .stable

        let desired = AudioRegistryState.desired(for: bottle)
        #expect(desired.driver == "coreaudio")
        #expect(desired.helBuflen == AudioLatencyPreset.stable.helBuflenValue)
    }

    @Test("A pinned device with a UID becomes the desired default output")
    @MainActor
    func desiredPinsDeviceUID() {
        let (dir, cleanup) = makeBottleDir()
        defer { cleanup() }

        let bottle = Bottle(bottleUrl: dir, inFlight: false, isAvailable: true)
        bottle.settings.outputDeviceMode = .pinned
        bottle.settings.pinnedDeviceUID = "BuiltInSpeakerDevice"

        #expect(AudioRegistryState.desired(for: bottle).outputDeviceUID == "BuiltInSpeakerDevice")
    }

    @Test("No default output is desired without a pinned UID")
    @MainActor
    func desiredFollowsSystemWithoutPin() {
        let (dir, cleanup) = makeBottleDir()
        defer { cleanup() }

        let bottle = Bottle(bottleUrl: dir, inFlight: false, isAvailable: true)
        bottle.settings.outputDeviceMode = .pinned
        #expect(AudioRegistryState.desired(for: bottle).outputDeviceUID == nil)

        // A UID left over from an earlier pin is ignored once the mode follows the system.
        bottle.settings.pinnedDeviceUID = "BuiltInSpeakerDevice"
        bottle.settings.outputDeviceMode = .followSystem
        #expect(AudioRegistryState.desired(for: bottle).outputDeviceUID == nil)
        #expect(AudioRegistryState.desired(for: bottle) == .factoryDefault)
    }

    @Test("A marker written before the output device field still loads")
    func legacyMarkerLoads() throws {
        let (dir, cleanup) = makeBottleDir()
        defer { cleanup() }

        let legacy: [String: Any] = [
            "driver": AudioDriverMode.auto.rawValue,
            "helBuflen": AudioLatencyPreset.defaultPreset.helBuflenValue
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: legacy, format: .xml, options: 0)
        try data.write(to: AudioRegistryState.markerURL(in: dir))

        let loaded = try #require(AudioRegistryState.load(from: dir))
        #expect(loaded.outputDeviceUID == nil)
        #expect(loaded == .factoryDefault)
    }

    @Test("The output device UID round-trips through the marker")
    func markerRoundTripsOutputDevice() throws {
        let (dir, cleanup) = makeBottleDir()
        defer { cleanup() }

        let state = AudioRegistryState(driver: "auto", helBuflen: 65_536, outputDeviceUID: "BuiltInSpeakerDevice")
        try state.save(to: dir)

        #expect(AudioRegistryState.load(from: dir) == state)
    }

    @Test("Factory settings stamp the marker without booting wineserver")
    @MainActor
    func factoryDefaultsStampWithoutWine() async {
        let (dir, cleanup) = makeBottleDir()
        defer { cleanup() }

        let bottle = Bottle(bottleUrl: dir, inFlight: false, isAvailable: true)
        await Wine.syncAudioRegistry(bottle: bottle)

        #expect(AudioRegistryState.load(from: dir) == .factoryDefault)
    }

    @Test("Concurrent syncs of one bottle all finish and leave one marker")
    @MainActor
    func concurrentSyncsFinish() async {
        let (dir, cleanup) = makeBottleDir()
        defer { cleanup() }

        let bottle = Bottle(bottleUrl: dir, inFlight: false, isAvailable: true)
        async let first: Void = Wine.syncAudioRegistry(bottle: bottle)
        async let second: Void = Wine.syncAudioRegistry(bottle: bottle)
        _ = await (first, second)

        #expect(AudioRegistryState.load(from: dir) == .factoryDefault)
    }

    @Test("A marker matching the settings makes sync a no-op")
    @MainActor
    func matchingMarkerIsNoOp() async throws {
        let (dir, cleanup) = makeBottleDir()
        defer { cleanup() }

        let bottle = Bottle(bottleUrl: dir, inFlight: false, isAvailable: true)
        bottle.settings.audioDriver = .coreaudio
        try AudioRegistryState.desired(for: bottle).save(to: dir)
        let before = try Data(contentsOf: AudioRegistryState.markerURL(in: dir))

        await Wine.syncAudioRegistry(bottle: bottle)

        let after = try Data(contentsOf: AudioRegistryState.markerURL(in: dir))
        #expect(before == after)
    }
}
