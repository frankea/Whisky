//
//  GPTKInterposerTakeBackTests.swift
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

/// Launch taking the interposers back out of payloads they were not validated
/// on, including trees an earlier release swapped although it did not own them.
@Suite("GPTK Interposer Take-Back Tests")
struct GPTKInterposerTakeBackTests {
    private let fixture: GPTKInterposerFixture
    private let videoProcessor = GPTKImporter.videoProcessorInterposer

    init() throws {
        fixture = try GPTKInterposerFixture()
    }

    private func slot(_ interposer: GPTKInterposer, in runtime: URL) -> URL {
        fixture.peDir(of: runtime).appending(path: interposer.slotName)
    }

    private func renamed(_ interposer: GPTKInterposer, in runtime: URL) -> URL {
        fixture.peDir(of: runtime).appending(path: interposer.renamedName)
    }

    private func renamedUnix(_ interposer: GPTKInterposer, in runtime: URL) -> URL {
        fixture.unixDir(of: runtime).appending(path: interposer.renamedUnixName)
    }

    /// A GPTK 3.0 payload copied in by hand, and what each interposed slot held
    /// before anything was swapped.
    private func makeHandPlacedGPTK3() throws -> (runtime: URL, originals: [String: Data]) {
        let runtime = try fixture.makeRuntimeTree()
        try fixture.overlayPayloadByHand(version: "3.0", into: runtime)
        var originals: [String: Data] = [:]
        for interposer in GPTKImporter.interposers {
            originals[interposer.slotName] = try Data(contentsOf: slot(interposer, in: runtime))
        }
        return (runtime, originals)
    }

    // MARK: - Payloads copied in by hand

    @Test("A hand-placed GPTK 3 payload an earlier release swapped gets its d3d12.dll back", arguments: [false, true])
    func restoresHandPlacedSlot(storeHoldsAnotherPayload: Bool) throws {
        let store = storeHoldsAnotherPayload
            ? try fixture.makeStore(version: GPTKInterposerFixture.validatedVersion)
            : fixture.tempDir.appending(path: "empty-store")
        let (runtime, originals) = try makeHandPlacedGPTK3()
        try fixture.installIgnoringVersion(videoProcessor, into: runtime)
        #expect(GPTKImporter.isInstalled(videoProcessor, inLibraryFolder: runtime))

        GPTKImporter.ensureVideoProcessorInstalled(bottles: [], inLibraryFolder: runtime, usingStore: store)

        // byte for byte what the owner put there, from the renamed copy alone
        #expect(try Data(contentsOf: slot(videoProcessor, in: runtime)) == originals[videoProcessor.slotName])
        #expect(!fixture.exists(renamed(videoProcessor, in: runtime)))
        #expect(!fixture.isLink(renamedUnix(videoProcessor, in: runtime)))
        let dxgi = GPTKImporter.dxgiVersionInterposer
        #expect(try Data(contentsOf: slot(dxgi, in: runtime)) == originals[dxgi.slotName])
    }

    @Test("Both interposers come back out of a hand-placed payload")
    func restoresBothHandPlacedSlots() throws {
        let (runtime, originals) = try makeHandPlacedGPTK3()
        for interposer in GPTKImporter.interposers {
            try fixture.installIgnoringVersion(interposer, into: runtime)
        }

        GPTKImporter.ensureVideoProcessorInstalled(
            bottles: [], inLibraryFolder: runtime, usingStore: fixture.tempDir.appending(path: "empty-store")
        )

        for interposer in GPTKImporter.interposers {
            #expect(try Data(contentsOf: slot(interposer, in: runtime)) == originals[interposer.slotName])
            #expect(!fixture.exists(renamed(interposer, in: runtime)))
            #expect(!fixture.isLink(renamedUnix(interposer, in: runtime)))
        }
    }

    @Test("The validated build copied in by hand keeps a swap it already has")
    func keepsSwapOnHandPlacedValidatedBuild() throws {
        let runtime = try fixture.makeRuntimeTree()
        try fixture.overlayPayloadByHand(version: GPTKInterposerFixture.validatedVersion, into: runtime)
        try GPTKImporter.install(videoProcessor, intoLibraryFolder: runtime)

        GPTKImporter.ensureVideoProcessorInstalled(
            bottles: [], inLibraryFolder: runtime, usingStore: fixture.tempDir.appending(path: "empty-store")
        )

        #expect(GPTKImporter.isInstalled(videoProcessor, inLibraryFolder: runtime))
        #expect(fixture.exists(renamed(videoProcessor, in: runtime)))
    }

    @Test("A renamed copy left beside a slot that holds Apple's DLL again is cleared")
    func clearsLeftoversBesideRestoredSlot() throws {
        let (runtime, originals) = try makeHandPlacedGPTK3()
        let dxgi = GPTKImporter.dxgiVersionInterposer
        try fixture.installIgnoringVersion(dxgi, into: runtime)
        // put back by hand, the renamed files left where they were
        try originals[dxgi.slotName]?.write(to: slot(dxgi, in: runtime))

        GPTKImporter.ensureVideoProcessorInstalled(
            bottles: [], inLibraryFolder: runtime, usingStore: fixture.tempDir.appending(path: "empty-store")
        )

        #expect(try Data(contentsOf: slot(dxgi, in: runtime)) == originals[dxgi.slotName])
        #expect(!fixture.exists(renamed(dxgi, in: runtime)))
        #expect(!fixture.isLink(renamedUnix(dxgi, in: runtime)))
    }

    @Test("A slot holding the interposer with nothing to restore from keeps it")
    func keepsShimWithNoCopyToRestore() throws {
        let (runtime, _) = try makeHandPlacedGPTK3()
        try fixture.installIgnoringVersion(videoProcessor, into: runtime)
        try FileManager.default.removeItem(at: renamed(videoProcessor, in: runtime))

        GPTKImporter.ensureVideoProcessorInstalled(
            bottles: [], inLibraryFolder: runtime, usingStore: fixture.tempDir.appending(path: "empty-store")
        )

        // better a slot that forwards nowhere than no d3d12.dll at all
        #expect(GPTKImporter.isInstalled(videoProcessor, inLibraryFolder: runtime))
    }

    // MARK: - Either kind of payload

    @Test("A slot someone replaced keeps the renamed DLL it may forward to", arguments: [false, true])
    func keepsRenamedBesideReplacedSlot(storeDeployed: Bool) throws {
        let store: URL
        let runtime: URL
        if storeDeployed {
            (store, runtime) = try fixture.makePreGateDeploy(version: "3.0")
        } else {
            store = fixture.tempDir.appending(path: "empty-store")
            (runtime, _) = try makeHandPlacedGPTK3()
            try fixture.installIgnoringVersion(videoProcessor, into: runtime)
        }
        var replacement = fakePEWithExportName("d3d12.dll")
        replacement.append(Data("someone's own build".utf8))
        try replacement.write(to: slot(videoProcessor, in: runtime))

        GPTKImporter.ensureVideoProcessorInstalled(bottles: [], inLibraryFolder: runtime, usingStore: store)

        #expect(try Data(contentsOf: slot(videoProcessor, in: runtime)) == replacement)
        #expect(fixture.exists(renamed(videoProcessor, in: runtime)))
        #expect(fixture.isLink(renamedUnix(videoProcessor, in: runtime)))
    }

    @Test("A d3d12 slot that went missing is put back at launch", arguments: [false, true])
    func restoresMissingSlot(storeDeployed: Bool) throws {
        let store: URL
        let runtime: URL
        let expected: Data?
        if storeDeployed {
            (store, runtime) = try fixture.makePreGateDeploy(version: "3.0")
            expected = try Data(contentsOf: store.appending(path: "lib").appending(path: "wine")
                .appending(path: "x86_64-windows").appending(path: videoProcessor.slotName))
        } else {
            store = fixture.tempDir.appending(path: "empty-store")
            let placed = try makeHandPlacedGPTK3()
            runtime = placed.runtime
            expected = placed.originals[videoProcessor.slotName]
            try fixture.installIgnoringVersion(videoProcessor, into: runtime)
        }
        try FileManager.default.removeItem(at: slot(videoProcessor, in: runtime))

        GPTKImporter.ensureVideoProcessorInstalled(bottles: [], inLibraryFolder: runtime, usingStore: store)

        #expect(try Data(contentsOf: slot(videoProcessor, in: runtime)) == expected)
        #expect(!fixture.exists(renamed(videoProcessor, in: runtime)))
    }

    @Test("A staging file left by an interrupted take-back is replaced, not tripped over")
    func replacesStaleStagingFile() throws {
        let (runtime, originals) = try makeHandPlacedGPTK3()
        try fixture.installIgnoringVersion(videoProcessor, into: runtime)
        let staging = fixture.peDir(of: runtime).appending(path: videoProcessor.slotName + ".staging")
        try Data("half-written".utf8).write(to: staging)

        GPTKImporter.ensureVideoProcessorInstalled(
            bottles: [], inLibraryFolder: runtime, usingStore: fixture.tempDir.appending(path: "empty-store")
        )

        #expect(try Data(contentsOf: slot(videoProcessor, in: runtime)) == originals[videoProcessor.slotName])
        #expect(!fixture.exists(staging))
    }
}
