//
//  GPTKInterposerPolicyTests.swift
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

@Suite("GPTK Interposer Policy Tests")
struct GPTKInterposerPolicyTests {
    private let fixture: GPTKInterposerFixture

    init() throws {
        fixture = try GPTKInterposerFixture()
    }

    // MARK: - Payload version

    @Test(
        "Only a build the interposers were validated on qualifies",
        arguments: [
            ("4.0b2", true),
            ("4.0b1", false), ("4.0b3", false), ("4.0", false), ("4.1b1", false),
            ("3.0", false), ("2.1", false), ("5.0", false), ("", false), ("beta", false)
        ]
    )
    func payloadVersionGate(version: String, supported: Bool) {
        #expect(GPTKImporter.interposersSupport(payloadVersion: version) == supported)
    }

    @Test("An unreadable payload version fails closed")
    func unreadableVersionFailsClosed() {
        #expect(!GPTKImporter.interposersSupport(payloadVersion: nil))
    }

    // MARK: - Deploy

    @Test("Deploy leaves both interposers out of a build they were not validated on", arguments: ["3.0", "4.0"])
    func deploySkipsInterposersOnOtherBuilds(version: String) throws {
        let store = try fixture.makeStore(version: version)
        let runtime = try fixture.makeRuntimeTree()

        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)

        #expect(GPTKImporter.isDeployed(inLibraryFolder: runtime))
        for interposer in GPTKImporter.interposers {
            #expect(!GPTKImporter.isInstalled(interposer, inLibraryFolder: runtime))
            #expect(!fixture.exists(fixture.peDir(of: runtime).appending(path: interposer.renamedName)))
            // Apple's own DLL is what the game loads
            let slot = fixture.peDir(of: runtime).appending(path: interposer.slotName)
            #expect(GPTKImporter.isGPTKForwarder(slot, matching: store.appending(path: "lib")))
        }
    }

    @Test("Deploy still installs both interposers over the validated build")
    func deployInstallsInterposersOnValidatedBuild() throws {
        let store = try fixture.makeStore(version: GPTKInterposerFixture.validatedVersion)
        let runtime = try fixture.makeRuntimeTree()

        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)

        for interposer in GPTKImporter.interposers {
            #expect(GPTKImporter.isInstalled(interposer, inLibraryFolder: runtime))
        }
    }

    // MARK: - Launch

    @Test("A deploy from before the interposer existed still gets it at launch")
    func launchInstallsOverStoreDeploy() throws {
        let store = try fixture.makeStore(version: GPTKInterposerFixture.validatedVersion)
        let runtime = try fixture.makeRuntimeTree(shippingInterposers: false)
        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)
        try fixture.makeShims(in: runtime)
        let bottle = try fixture.makeBottle()

        GPTKImporter.ensureVideoProcessorInstalled(bottles: [bottle], inLibraryFolder: runtime, usingStore: store)

        #expect(GPTKImporter.isVideoProcessorInstalled(inLibraryFolder: runtime))
        #expect(fixture.exists(fixture.placeholder(in: bottle)))
    }

    @Test("A GPTK 3 payload copied in by hand is left as it is at launch", arguments: [false, true])
    func launchLeavesHandPlacedPayloadAlone(storeHoldsAnotherPayload: Bool) throws {
        let store = storeHoldsAnotherPayload
            ? try fixture.makeStore(version: GPTKInterposerFixture.validatedVersion)
            : fixture.tempDir.appending(path: "empty-store")
        let runtime = try fixture.makeRuntimeTree()
        try fixture.overlayPayloadByHand(version: "3.0", into: runtime)
        let slot = fixture.peDir(of: runtime).appending(path: GPTKImporter.videoProcessorInterposer.slotName)
        let before = try Data(contentsOf: slot)
        let bottle = try fixture.makeBottle()

        GPTKImporter.ensureVideoProcessorInstalled(bottles: [bottle], inLibraryFolder: runtime, usingStore: store)

        #expect(try Data(contentsOf: slot) == before)
        let renamed = fixture.peDir(of: runtime).appending(path: GPTKImporter.videoProcessorInterposer.renamedName)
        #expect(!fixture.exists(renamed))
        #expect(!fixture.exists(fixture.placeholder(in: bottle)))
    }

    @Test("The validated build copied in by hand is not the importer's to change either")
    func launchLeavesHandPlacedValidatedBuildAlone() throws {
        let store = try fixture.makeStore(version: GPTKInterposerFixture.validatedVersion)
        let runtime = try fixture.makeRuntimeTree()
        try fixture.overlayPayloadByHand(version: GPTKInterposerFixture.validatedVersion, into: runtime)
        let slot = fixture.peDir(of: runtime).appending(path: GPTKImporter.videoProcessorInterposer.slotName)
        let before = try Data(contentsOf: slot)

        GPTKImporter.ensureVideoProcessorInstalled(bottles: [], inLibraryFolder: runtime, usingStore: store)

        #expect(try Data(contentsOf: slot) == before)
        #expect(!GPTKImporter.isVideoProcessorInstalled(inLibraryFolder: runtime))
    }

    @Test("A d3d12 slot someone replaced by hand is not swapped at launch")
    func launchLeavesReplacedSlotAlone() throws {
        let store = try fixture.makeStore(version: GPTKInterposerFixture.validatedVersion)
        let runtime = try fixture.makeRuntimeTree(shippingInterposers: false)
        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)
        try fixture.makeShims(in: runtime)
        let slot = fixture.peDir(of: runtime).appending(path: GPTKImporter.videoProcessorInterposer.slotName)
        var replacement = fakePEWithExportName("d3d12.dll")
        replacement.append(Data("someone's own build".utf8))
        try replacement.write(to: slot)

        GPTKImporter.ensureVideoProcessorInstalled(bottles: [], inLibraryFolder: runtime, usingStore: store)

        #expect(try Data(contentsOf: slot) == replacement)
        let renamed = fixture.peDir(of: runtime).appending(path: GPTKImporter.videoProcessorInterposer.renamedName)
        #expect(!fixture.exists(renamed))
    }

    @Test("Interposers an older deploy put in front of a GPTK 3 payload come back out at launch")
    func launchRemovesInterposersFromGPTK3() throws {
        let (store, runtime) = try fixture.makePreGateDeploy(version: "3.0")

        GPTKImporter.ensureVideoProcessorInstalled(bottles: [], inLibraryFolder: runtime, usingStore: store)

        for interposer in GPTKImporter.interposers {
            let slot = fixture.peDir(of: runtime).appending(path: interposer.slotName)
            #expect(GPTKImporter.isGPTKForwarder(slot, matching: store.appending(path: "lib")))
            #expect(!fixture.exists(fixture.peDir(of: runtime).appending(path: interposer.renamedName)))
            #expect(!fixture.isLink(fixture.unixDir(of: runtime).appending(path: interposer.renamedUnixName)))
        }
        #expect(GPTKImporter.isDeployed(inLibraryFolder: runtime))
    }
}
