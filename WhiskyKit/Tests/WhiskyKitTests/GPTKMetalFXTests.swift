//
//  GPTKMetalFXTests.swift
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

@Suite("GPTK MetalFX Bridge Tests")
struct GPTKMetalFXTests {
    private let tempDir: URL

    init() throws {
        tempDir = try makeGPTKTempDir()
    }

    /// A store whose payload carries the bridge, and a runtime to deploy into.
    private func makeBridgeableRuntime() throws -> (store: URL, runtime: URL) {
        let store = try makeImportedStore(in: tempDir)
        try makeStoreMetalFXBridge(inStore: store)
        let runtime = tempDir.appending(path: "Libraries")
        try makeRuntime(at: runtime)
        return (store, runtime)
    }

    private func makeBottle(named name: String = "bottle") throws -> URL {
        let bottle = tempDir.appending(path: name)
        try FileManager.default.createDirectory(
            at: bottle.appending(path: "drive_c").appending(path: "windows").appending(path: "system32"),
            withIntermediateDirectories: true
        )
        return bottle
    }

    // MARK: - Install

    @Test("Deploy installs the bridge under its export name with a unix half")
    func deployInstallsBridge() throws {
        let (store, runtime) = try makeBridgeableRuntime()

        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)

        #expect(GPTKImporter.isMetalFXBridgeInstalled(inLibraryFolder: runtime, usingStore: store))
        // the filename Apple ships is not the name the loader will accept
        let shipped = runtime.appending(path: "Wine").appending(path: "lib").appending(path: "wine")
            .appending(path: "x86_64-windows").appending(path: GPTKImporter.metalFXBridgeSourceName)
        #expect(!FileManager.default.fileExists(atPath: shipped.path(percentEncoded: false)))

        // without the unix half DllMain fails and the PE is useless
        let link = GPTKImporter.metalFXBridgeUnixLink(inLibraryFolder: runtime)
        let destination = try FileManager.default.destinationOfSymbolicLink(
            atPath: link.path(percentEncoded: false)
        )
        #expect(destination == GPTKImporter.unixLinkDestination)
    }

    @Test("A payload with no bridge deploys without one")
    func deploySkipsPayloadWithoutBridge() throws {
        let store = try makeImportedStore(in: tempDir)
        let runtime = tempDir.appending(path: "Libraries")
        try makeRuntime(at: runtime)

        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)

        #expect(!GPTKImporter.isMetalFXBridgeInstalled(inLibraryFolder: runtime, usingStore: store))
        let bridge = GPTKImporter.metalFXBridgePE(inLibraryFolder: runtime)
        #expect(!FileManager.default.fileExists(atPath: bridge.path(percentEncoded: false)))
    }

    @Test("Installing twice changes nothing")
    func installIsIdempotent() throws {
        let (store, runtime) = try makeBridgeableRuntime()
        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)

        try GPTKImporter.installMetalFXBridge(intoLibraryFolder: runtime, usingStore: store)

        #expect(GPTKImporter.isMetalFXBridgeInstalled(inLibraryFolder: runtime, usingStore: store))
    }

    @Test("Installing leaves a foreign shared bridge alone")
    func installLeavesForeignBridge() throws {
        let (store, runtime) = try makeBridgeableRuntime()
        let bridge = GPTKImporter.metalFXBridgePE(inLibraryFolder: runtime)
        try FileManager.default.createDirectory(
            at: bridge.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let foreign = Data("someone else's nvngx".utf8)
        try foreign.write(to: bridge)

        try GPTKImporter.installMetalFXBridge(intoLibraryFolder: runtime, usingStore: store)

        #expect(try Data(contentsOf: bridge) == foreign)
    }

    @Test("Installing leaves a foreign unix half alone")
    func installLeavesForeignUnixHalf() throws {
        let (store, runtime) = try makeBridgeableRuntime()
        let link = GPTKImporter.metalFXBridgeUnixLink(inLibraryFolder: runtime)
        try FileManager.default.createDirectory(
            at: link.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let foreign = Data("someone else's unix half".utf8)
        try foreign.write(to: link)

        try GPTKImporter.installMetalFXBridge(intoLibraryFolder: runtime, usingStore: store)

        #expect(try Data(contentsOf: link) == foreign)
        #expect(!FileManager.default.fileExists(
            atPath: GPTKImporter.metalFXBridgePE(inLibraryFolder: runtime).path(percentEncoded: false)
        ))
    }

    // MARK: - Remove

    @Test("Remove takes the bridge and its unix half back out")
    func removeClearsBridge() throws {
        let (store, runtime) = try makeBridgeableRuntime()
        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)

        try GPTKImporter.remove(fromLibraryFolder: runtime, usingStore: store)

        let fileManager = FileManager.default
        let bridge = GPTKImporter.metalFXBridgePE(inLibraryFolder: runtime)
        #expect(!fileManager.fileExists(atPath: bridge.path(percentEncoded: false)))
        // the link is dangling by now, so ask about the link itself
        let link = GPTKImporter.metalFXBridgeUnixLink(inLibraryFolder: runtime)
        #expect((try? fileManager.destinationOfSymbolicLink(atPath: link.path(percentEncoded: false))) == nil)
    }

    @Test("A bridge this store did not install is left alone")
    func removeLeavesForeignBridge() throws {
        let (store, runtime) = try makeBridgeableRuntime()
        let bridge = GPTKImporter.metalFXBridgePE(inLibraryFolder: runtime)
        try FileManager.default.createDirectory(
            at: bridge.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("someone else's nvngx".utf8).write(to: bridge)
        let link = GPTKImporter.metalFXBridgeUnixLink(inLibraryFolder: runtime)
        try FileManager.default.createDirectory(
            at: link.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            atPath: link.path(percentEncoded: false),
            withDestinationPath: GPTKImporter.unixLinkDestination
        )

        GPTKImporter.removeMetalFXBridge(fromLibraryFolder: runtime, usingStore: store)

        #expect(FileManager.default.fileExists(atPath: bridge.path(percentEncoded: false)))
        #expect((try? FileManager.default.destinationOfSymbolicLink(
            atPath: link.path(percentEncoded: false)
        )) == GPTKImporter.unixLinkDestination)
    }

    @Test("Remove clears its unix half after an interrupted install")
    func removeClearsInterruptedUnixHalf() throws {
        let (store, runtime) = try makeBridgeableRuntime()
        let link = GPTKImporter.metalFXBridgeUnixLink(inLibraryFolder: runtime)
        try FileManager.default.createDirectory(
            at: link.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            atPath: link.path(percentEncoded: false),
            withDestinationPath: GPTKImporter.unixLinkDestination
        )

        GPTKImporter.removeMetalFXBridge(fromLibraryFolder: runtime, usingStore: store)

        #expect((try? FileManager.default.destinationOfSymbolicLink(
            atPath: link.path(percentEncoded: false)
        )) == nil)
    }

    // MARK: - Prefixes

    @Test("Seeding puts a placeholder in the prefix, without which nothing loads")
    func seedWritesPlaceholder() throws {
        let (store, runtime) = try makeBridgeableRuntime()
        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)
        let bottle = try makeBottle()

        GPTKImporter.seedMetalFXBridgePlaceholder(inBottle: bottle, fromLibraryFolder: runtime)

        let placeholder = bottle.appending(path: "drive_c").appending(path: "windows")
            .appending(path: "system32").appending(path: GPTKImporter.metalFXBridgeName)
        #expect(FileManager.default.fileExists(atPath: placeholder.path(percentEncoded: false)))
    }

    @Test("Seeding never overwrites a placeholder that is already there")
    func seedKeepsExistingPlaceholder() throws {
        let (store, runtime) = try makeBridgeableRuntime()
        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)
        let bottle = try makeBottle()
        let placeholder = bottle.appending(path: "drive_c").appending(path: "windows")
            .appending(path: "system32").appending(path: GPTKImporter.metalFXBridgeName)
        try Data("wineboot's own".utf8).write(to: placeholder)

        GPTKImporter.seedMetalFXBridgePlaceholder(inBottle: bottle, fromLibraryFolder: runtime)

        #expect(try Data(contentsOf: placeholder) == Data("wineboot's own".utf8))
    }

    @Test("A runtime with no bridge seeds nothing")
    func seedSkipsRuntimeWithoutBridge() throws {
        let runtime = tempDir.appending(path: "Libraries")
        try makeRuntime(at: runtime)
        let bottle = try makeBottle()

        GPTKImporter.seedMetalFXBridgePlaceholder(inBottle: bottle, fromLibraryFolder: runtime)

        let placeholder = bottle.appending(path: "drive_c").appending(path: "windows")
            .appending(path: "system32").appending(path: GPTKImporter.metalFXBridgeName)
        #expect(!FileManager.default.fileExists(atPath: placeholder.path(percentEncoded: false)))
    }

    // MARK: - Opting out

    @Test("Clearing removes the placeholder, which is what makes the bridge unreachable")
    func clearRemovesPlaceholder() throws {
        let (store, runtime) = try makeBridgeableRuntime()
        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)
        let bottle = try makeBottle()
        GPTKImporter.seedMetalFXBridgePlaceholder(inBottle: bottle, fromLibraryFolder: runtime)

        GPTKImporter.clearMetalFXBridgePlaceholder(inBottle: bottle)

        let placeholder = bottle.appending(path: "drive_c").appending(path: "windows")
            .appending(path: "system32").appending(path: GPTKImporter.metalFXBridgeName)
        #expect(!FileManager.default.fileExists(atPath: placeholder.path(percentEncoded: false)))
    }

    @Test("Clearing removes a stub wineboot wrote, or opting out would not stick")
    func clearRemovesWinebootStub() throws {
        let (store, runtime) = try makeBridgeableRuntime()
        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)
        let bottle = try makeBottle()
        let placeholder = bottle.appending(path: "drive_c").appending(path: "windows")
            .appending(path: "system32").appending(path: GPTKImporter.metalFXBridgeName)
        // wineboot's own stub: builtin-marked, but not a copy of ours
        try fakePE(builtin: true).write(to: placeholder)

        GPTKImporter.clearMetalFXBridgePlaceholder(inBottle: bottle)

        #expect(!FileManager.default.fileExists(atPath: placeholder.path(percentEncoded: false)))
    }

    @Test("Clearing leaves a native nvngx someone installed themselves")
    func clearLeavesNativeDLL() throws {
        let (store, runtime) = try makeBridgeableRuntime()
        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)
        let bottle = try makeBottle()
        let placeholder = bottle.appending(path: "drive_c").appending(path: "windows")
            .appending(path: "system32").appending(path: GPTKImporter.metalFXBridgeName)
        try fakePE(builtin: false).write(to: placeholder)

        GPTKImporter.clearMetalFXBridgePlaceholder(inBottle: bottle)

        #expect(FileManager.default.fileExists(atPath: placeholder.path(percentEncoded: false)))
    }
}

@Suite("MetalFX Setting Tests")
struct MetalFXSettingTests {
    @Test("The setting is on by default and survives a round trip")
    func settingRoundTrips() throws {
        var settings = BottleSettings()
        #expect(settings.metalFX)

        settings.metalFX = false
        let decoded = try PropertyListDecoder().decode(
            BottleSettings.self, from: PropertyListEncoder().encode(settings)
        )

        #expect(!decoded.metalFX)
    }

    @Test("A bottle written before the key existed picks up the new default")
    func absentKeyDefaultsOn() throws {
        // The graphics config is nested, so an older bottle's plist has the
        // dictionary without the key rather than no dictionary at all.
        let plist: [String: Any] = ["graphicsConfig": ["backend": "recommended"]]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0
        )

        let decoded = try PropertyListDecoder().decode(BottleSettings.self, from: data)

        #expect(decoded.metalFX)
    }

    @Test("The env var follows the setting, and is only set under D3DMetal")
    func environmentFollowsTheSetting() throws {
        var builder = EnvironmentBuilder()
        var settings = BottleSettings()
        settings.graphicsBackend = .d3dMetal
        _ = settings.populateBottleManagedLayer(builder: &builder, resolvedBackend: .d3dMetal)
        #expect(builder.resolve().environment["D3DM_ENABLE_METALFX"] == "1")

        settings.metalFX = false
        var offBuilder = EnvironmentBuilder()
        _ = settings.populateBottleManagedLayer(builder: &offBuilder, resolvedBackend: .d3dMetal)
        #expect(offBuilder.resolve().environment["D3DM_ENABLE_METALFX"] == nil)

        // DXVK never reaches D3DMetal's bridge, so the knob would be a lie
        settings.metalFX = true
        settings.graphicsBackend = .dxvk
        var dxvkBuilder = EnvironmentBuilder()
        _ = settings.populateBottleManagedLayer(builder: &dxvkBuilder, resolvedBackend: .dxvk)
        #expect(dxvkBuilder.resolve().environment["D3DM_ENABLE_METALFX"] == nil)
    }
}
