//
//  GPTKHandPlacedPayloadTests.swift
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

/// What runs without anyone asking, at launch and whenever Settings opens,
/// leaves a payload copied into the runtime by hand as its owner set it up.
@Suite("GPTK Hand-Placed Payload Tests")
struct GPTKHandPlacedPayloadTests {
    private let fixture: GPTKInterposerFixture

    init() throws {
        fixture = try GPTKInterposerFixture()
    }

    /// Puts Apple's two NVIDIA bridges in the store, the way the payload ships them.
    private func addBridges(toStore store: URL) throws {
        try makeStoreMetalFXBridge(inStore: store, marker: "store's nvngx")
        var nvapi = fakePE(builtin: true)
        nvapi.append(Data("store's nvapi".utf8))
        try nvapi.write(
            to: store.appending(path: "lib").appending(path: "wine").appending(path: "x86_64-windows")
                .appending(path: GPTKImporter.nvapiBridgeName)
        )
    }

    // MARK: - NVIDIA bridges at launch

    @Test("Launch leaves the NVIDIA bridges of a payload copied in by hand alone")
    func launchLeavesHandPlacedBridgesAlone() throws {
        let store = try fixture.makeStore(version: GPTKInterposerFixture.validatedVersion)
        try addBridges(toStore: store)
        let runtime = try fixture.makeRuntimeTree()
        try fixture.overlayPayloadByHand(version: "3.0", into: runtime)
        let nvapi = GPTKImporter.nvapiBridgePE(inLibraryFolder: runtime)
        let nvngx = GPTKImporter.metalFXBridgePE(inLibraryFolder: runtime)
        try Data("owner's nvapi".utf8).write(to: nvapi)
        try Data("owner's nvngx".utf8).write(to: nvngx)

        GPTKImporter.ensureMetalFXBridgeInstalled(inLibraryFolder: runtime, usingStore: store)
        GPTKImporter.ensureNVAPIBridgeInstalled(inLibraryFolder: runtime, usingStore: store)

        #expect(try Data(contentsOf: nvapi) == Data("owner's nvapi".utf8))
        #expect(try Data(contentsOf: nvngx) == Data("owner's nvngx".utf8))
        #expect(!fixture.exists(GPTKImporter.nvapiPlaceholderBackup(inLibraryFolder: runtime)))
    }

    @Test("A deploy from before the bridges existed still gets them at launch")
    func launchInstallsBridgesOverStoreDeploy() throws {
        let store = try fixture.makeStore(version: GPTKInterposerFixture.validatedVersion)
        let runtime = try fixture.makeRuntimeTree()
        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)
        try addBridges(toStore: store)

        GPTKImporter.ensureMetalFXBridgeInstalled(inLibraryFolder: runtime, usingStore: store)
        GPTKImporter.ensureNVAPIBridgeInstalled(inLibraryFolder: runtime, usingStore: store)

        #expect(GPTKImporter.isMetalFXBridgeInstalled(inLibraryFolder: runtime, usingStore: store))
        #expect(GPTKImporter.isNVAPIBridgeInstalled(inLibraryFolder: runtime, usingStore: store))
    }

    // MARK: - Deploy when Settings opens

    @Test("Opening Settings does not deploy the stored payload over one copied in by hand")
    func settingsLeavesHandPlacedPayloadAlone() throws {
        let store = try fixture.makeStore(version: GPTKInterposerFixture.validatedVersion)
        let runtime = try fixture.makeRuntimeTree()
        try fixture.overlayPayloadByHand(version: "3.0", into: runtime)
        var before: [String: Data] = [:]
        for name in GPTKImporter.forwarderDLLNames {
            before[name] = try Data(contentsOf: fixture.peDir(of: runtime).appending(path: name))
        }

        let deployed = GPTKImporter.deployStoredPayloadIfPresent(
            fromStore: store, intoLibraryFolder: runtime, isAppleSigned: { _, _ in true }
        )

        #expect(!deployed)
        for name in GPTKImporter.forwarderDLLNames {
            #expect(try Data(contentsOf: fixture.peDir(of: runtime).appending(path: name)) == before[name])
        }
        #expect(GPTKImporter.deployedPayloadVersion(inLibraryFolder: runtime) == "3.0")
        #expect(!fixture.exists(store.appending(path: "originals").appending(path: "d3d11.dll")))
    }

    @Test("Opening Settings still deploys into a runtime without a payload and refreshes its own")
    func settingsStillDeploysStoredPayload() throws {
        let store = try fixture.makeStore(version: GPTKInterposerFixture.validatedVersion)
        let runtime = try fixture.makeRuntimeTree()

        #expect(GPTKImporter.deployStoredPayloadIfPresent(
            fromStore: store, intoLibraryFolder: runtime, isAppleSigned: { _, _ in true }
        ))
        #expect(GPTKImporter.isStorePayloadDeployed(inLibraryFolder: runtime, usingStore: store))
        #expect(GPTKImporter.deployStoredPayloadIfPresent(
            fromStore: store, intoLibraryFolder: runtime, isAppleSigned: { _, _ in true }
        ))
        #expect(GPTKImporter.isDeployed(inLibraryFolder: runtime))
    }

    @Test("Without a stored payload there is nothing to deploy")
    func settingsWithoutStoreDeploysNothing() throws {
        let runtime = try fixture.makeRuntimeTree()

        let deployed = GPTKImporter.deployStoredPayloadIfPresent(
            fromStore: fixture.tempDir.appending(path: "empty-store"),
            intoLibraryFolder: runtime,
            isAppleSigned: { _, _ in true }
        )

        #expect(!deployed)
        #expect(!GPTKImporter.isDeployed(inLibraryFolder: runtime))
    }
}
