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
    private let tempDir: URL

    init() throws {
        tempDir = try makeGPTKTempDir()
    }

    // MARK: - Fixtures

    private func peDir(of runtime: URL) -> URL {
        runtime.appending(path: "Wine").appending(path: "lib").appending(path: "wine")
            .appending(path: "x86_64-windows")
    }

    private func unixDir(of runtime: URL) -> URL {
        runtime.appending(path: "Wine").appending(path: "lib").appending(path: "wine")
            .appending(path: "x86_64-unix")
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// A store holding a payload of `version`, with both interposed slots
    /// shaped so the export rename can walk them.
    ///
    /// Imported without validation: that is not what is under test, and it
    /// checks things these fixtures cannot provide.
    private func makeStore(version: String) throws -> URL {
        let lib = tempDir.appending(path: "payload")
        let store = tempDir.appending(path: "store")
        try makePayload(at: lib, version: version)
        try GPTKImporter.importPayload(GPTKPayload(libRoot: lib, version: version), intoStore: store)
        for interposer in GPTKImporter.interposers {
            try makeStoreSlotRenameable(inStore: store, slotName: interposer.slotName)
        }
        return store
    }

    /// A runtime tree, carrying both interposers unless told otherwise.
    private func makeRuntimeTree(shippingInterposers: Bool = true) throws -> URL {
        let runtime = tempDir.appending(path: "Libraries")
        try makeRuntime(at: runtime)
        if shippingInterposers {
            try makeShims(in: runtime)
        }
        return runtime
    }

    private func makeShims(in runtime: URL) throws {
        for interposer in GPTKImporter.interposers {
            try makeInterposerShim(interposer, at: runtime, marker: "\(interposer.label) shim")
        }
    }

    /// Copies Apple's files into the tree by hand, the way the GPTK readme
    /// describes and the importer never sees: forwarders over the builtins,
    /// the unix bridges beside them, and `external/`.
    private func overlayPayloadByHand(version: String, into runtime: URL) throws {
        let fileManager = FileManager.default
        for name in GPTKImporter.forwarderDLLNames {
            let target = peDir(of: runtime).appending(path: name)
            try? fileManager.removeItem(at: target)
            var dll = fakePEWithExportName(name)
            dll.append(Data("placed by hand".utf8))
            try dll.write(to: target)
        }
        for name in GPTKImporter.unixLibraryNames {
            try fileManager.createSymbolicLink(
                atPath: unixDir(of: runtime).appending(path: name).path(percentEncoded: false),
                withDestinationPath: GPTKImporter.unixLinkDestination
            )
        }
        let payload = tempDir.appending(path: "by-hand")
        try makePayload(at: payload, version: version)
        try fileManager.copyItem(
            at: payload.appending(path: "external"),
            to: runtime.appending(path: "Wine").appending(path: "lib").appending(path: "external")
        )
    }

    private func setFrameworkVersion(_ version: String, inExternal external: URL) throws {
        let plist: [String: Any] = ["CFBundleShortVersionString": version]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(
            to: external.appending(path: "D3DMetal.framework").appending(path: "Versions")
                .appending(path: "A").appending(path: "Resources").appending(path: "Info.plist")
        )
    }

    private func makeBottle() throws -> URL {
        let bottle = tempDir.appending(path: "bottle")
        try FileManager.default.createDirectory(
            at: bottle.appending(path: "drive_c").appending(path: "windows").appending(path: "system32"),
            withIntermediateDirectories: true
        )
        return bottle
    }

    private func placeholder(in bottle: URL) -> URL {
        bottle.appending(path: "drive_c").appending(path: "windows").appending(path: "system32")
            .appending(path: GPTKImporter.videoProcessorInterposer.renamedName)
    }

    // MARK: - Payload version

    @Test(
        "Only the GPTK line the interposers were validated on qualifies",
        arguments: [
            ("4.0b2", true), ("4.0", true), ("4.1b1", true),
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

    @Test("Deploy leaves both interposers out of a GPTK 3 payload")
    func deploySkipsInterposersOnGPTK3() throws {
        let store = try makeStore(version: "3.0")
        let runtime = try makeRuntimeTree()

        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)

        #expect(GPTKImporter.isDeployed(inLibraryFolder: runtime))
        for interposer in GPTKImporter.interposers {
            #expect(!GPTKImporter.isInstalled(interposer, inLibraryFolder: runtime))
            #expect(!exists(peDir(of: runtime).appending(path: interposer.renamedName)))
            // Apple's own DLL is what the game loads
            let slot = peDir(of: runtime).appending(path: interposer.slotName)
            #expect(GPTKImporter.isGPTKForwarder(slot, matching: store.appending(path: "lib")))
        }
    }

    @Test("Deploy still installs both interposers over a GPTK 4 payload")
    func deployInstallsInterposersOnGPTK4() throws {
        let store = try makeStore(version: "4.0b2")
        let runtime = try makeRuntimeTree()

        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)

        for interposer in GPTKImporter.interposers {
            #expect(GPTKImporter.isInstalled(interposer, inLibraryFolder: runtime))
        }
    }

    // MARK: - Launch

    @Test("A deploy from before the interposer existed still gets it at launch")
    func launchInstallsOverStoreDeploy() throws {
        let store = try makeStore(version: "4.0b2")
        let runtime = try makeRuntimeTree(shippingInterposers: false)
        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)
        try makeShims(in: runtime)
        let bottle = try makeBottle()

        GPTKImporter.ensureVideoProcessorInstalled(bottles: [bottle], inLibraryFolder: runtime, usingStore: store)

        #expect(GPTKImporter.isVideoProcessorInstalled(inLibraryFolder: runtime))
        #expect(exists(placeholder(in: bottle)))
    }

    @Test("A GPTK 3 payload copied in by hand is left as it is at launch", arguments: [false, true])
    func launchLeavesHandPlacedPayloadAlone(storeHoldsAnotherPayload: Bool) throws {
        let store = storeHoldsAnotherPayload
            ? try makeStore(version: "4.0b2")
            : tempDir.appending(path: "empty-store")
        let runtime = try makeRuntimeTree()
        try overlayPayloadByHand(version: "3.0", into: runtime)
        let slot = peDir(of: runtime).appending(path: GPTKImporter.videoProcessorInterposer.slotName)
        let before = try Data(contentsOf: slot)
        let bottle = try makeBottle()

        GPTKImporter.ensureVideoProcessorInstalled(bottles: [bottle], inLibraryFolder: runtime, usingStore: store)

        #expect(try Data(contentsOf: slot) == before)
        #expect(!exists(peDir(of: runtime).appending(path: GPTKImporter.videoProcessorInterposer.renamedName)))
        #expect(!exists(placeholder(in: bottle)))
    }

    @Test("A GPTK 4 payload copied in by hand is not the importer's to change either")
    func launchLeavesHandPlacedGPTK4Alone() throws {
        let store = try makeStore(version: "4.0b2")
        let runtime = try makeRuntimeTree()
        try overlayPayloadByHand(version: "4.0b2", into: runtime)
        let slot = peDir(of: runtime).appending(path: GPTKImporter.videoProcessorInterposer.slotName)
        let before = try Data(contentsOf: slot)

        GPTKImporter.ensureVideoProcessorInstalled(bottles: [], inLibraryFolder: runtime, usingStore: store)

        #expect(try Data(contentsOf: slot) == before)
        #expect(!GPTKImporter.isVideoProcessorInstalled(inLibraryFolder: runtime))
    }

    @Test("A d3d12 slot someone replaced by hand is not swapped at launch")
    func launchLeavesReplacedSlotAlone() throws {
        let store = try makeStore(version: "4.0b2")
        let runtime = try makeRuntimeTree(shippingInterposers: false)
        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)
        try makeShims(in: runtime)
        let slot = peDir(of: runtime).appending(path: GPTKImporter.videoProcessorInterposer.slotName)
        var replacement = fakePEWithExportName("d3d12.dll")
        replacement.append(Data("someone's own build".utf8))
        try replacement.write(to: slot)

        GPTKImporter.ensureVideoProcessorInstalled(bottles: [], inLibraryFolder: runtime, usingStore: store)

        #expect(try Data(contentsOf: slot) == replacement)
        #expect(!exists(peDir(of: runtime).appending(path: GPTKImporter.videoProcessorInterposer.renamedName)))
    }

    @Test("Interposers an older deploy put in front of a GPTK 3 payload come back out at launch")
    func launchRemovesInterposersFromGPTK3() throws {
        // What a deploy before the version check left behind: both swaps made
        // over a payload they were never validated on.
        let store = try makeStore(version: "4.0b2")
        let runtime = try makeRuntimeTree()
        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)
        try setFrameworkVersion("3.0", inExternal: store.appending(path: "lib").appending(path: "external"))
        try setFrameworkVersion(
            "3.0", inExternal: runtime.appending(path: "Wine").appending(path: "lib").appending(path: "external")
        )

        GPTKImporter.ensureVideoProcessorInstalled(bottles: [], inLibraryFolder: runtime, usingStore: store)

        for interposer in GPTKImporter.interposers {
            let slot = peDir(of: runtime).appending(path: interposer.slotName)
            #expect(GPTKImporter.isGPTKForwarder(slot, matching: store.appending(path: "lib")))
            #expect(!exists(peDir(of: runtime).appending(path: interposer.renamedName)))
            let link = unixDir(of: runtime).appending(path: interposer.renamedUnixName).path(percentEncoded: false)
            #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link)) == nil)
        }
        #expect(GPTKImporter.isDeployed(inLibraryFolder: runtime))
    }
}
