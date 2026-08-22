//
//  GPTKVideoProcessorTests.swift
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

@Suite("GPTK Video Processor Tests")
struct GPTKVideoProcessorTests {
    private let tempDir: URL

    init() throws {
        tempDir = try makeGPTKTempDir()
    }

    private func peDir(of runtime: URL) -> URL {
        runtime.appending(path: "Wine").appending(path: "lib").appending(path: "wine")
            .appending(path: "x86_64-windows")
    }

    private func exportName(of url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return String(bytes: data[0x250 ..< 0x259], encoding: .utf8) ?? "unreadable"
    }

    /// A runtime holding the payload with an interposer available to install.
    private func makeDeployableRuntime() throws -> (store: URL, runtime: URL) {
        let store = try makeImportedStore(in: tempDir)
        try makeStoreD3D12Renameable(inStore: store)
        let runtime = tempDir.appending(path: "Libraries")
        try makeRuntime(at: runtime)
        try makeVideoProcessorShim(at: runtime)
        return (store, runtime)
    }

    // MARK: - The rename

    @Test("The export name is rewritten in place")
    func rewriteExportName() throws {
        let dll = tempDir.appending(path: "apple.dll")
        try fakePEWithExportName("d3d12.dll").write(to: dll)

        try GPTKImporter.rewriteExportName(at: dll, from: "d3d12.dll", to: "d3dmt.dll")

        #expect(try exportName(of: dll) == "d3dmt.dll")
    }

    @Test("A replacement of a different length is refused")
    func rewriteRejectsDifferentLength() throws {
        let dll = tempDir.appending(path: "apple.dll")
        try fakePEWithExportName("d3d12.dll").write(to: dll)

        #expect(throws: GPTKVideoProcessorError.self) {
            try GPTKImporter.rewriteExportName(at: dll, from: "d3d12.dll", to: "d3d12metal.dll")
        }
    }

    @Test("A DLL that does not declare the expected name is refused")
    func rewriteRejectsUnexpectedName() throws {
        let dll = tempDir.appending(path: "other.dll")
        try fakePEWithExportName("dxgi.dll!").write(to: dll)

        #expect(throws: GPTKVideoProcessorError.unexpectedExportName("dxgi.dll!")) {
            try GPTKImporter.rewriteExportName(at: dll, from: "d3d12.dll", to: "d3dmt.dll")
        }
    }

    @Test("A DLL with no PE header is refused rather than corrupted")
    func rewriteRejectsNonPE() throws {
        let dll = tempDir.appending(path: "stub.dll")
        try fakePE(builtin: true).write(to: dll)

        #expect(throws: GPTKVideoProcessorError.self) {
            try GPTKImporter.rewriteExportName(at: dll, from: "d3d12.dll", to: "d3dmt.dll")
        }
    }

    // MARK: - Install

    @Test("Deploy leaves the interposer in the d3d12 slot with Apple's DLL beside it")
    func deployInstallsVideoProcessor() throws {
        let (store, runtime) = try makeDeployableRuntime()

        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)

        #expect(GPTKImporter.isVideoProcessorInstalled(inLibraryFolder: runtime))
        let renamed = peDir(of: runtime).appending(path: "d3dmt.dll")
        #expect(FileManager.default.fileExists(atPath: renamed.path(percentEncoded: false)))
        #expect(try exportName(of: renamed) == "d3dmt.dll")

        // the unix half has to follow the renamed PE or D3DMetal never binds
        let link = runtime.appending(path: "Wine").appending(path: "lib").appending(path: "wine")
            .appending(path: "x86_64-unix").appending(path: "d3dmt.so")
        let destination = try FileManager.default.destinationOfSymbolicLink(
            atPath: link.path(percentEncoded: false)
        )
        #expect(destination == GPTKImporter.unixLinkDestination)
    }

    @Test("Installing twice changes nothing")
    func installIsIdempotent() throws {
        let (store, runtime) = try makeDeployableRuntime()
        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)

        try GPTKImporter.installVideoProcessor(intoLibraryFolder: runtime)

        #expect(GPTKImporter.isVideoProcessorInstalled(inLibraryFolder: runtime))
        // the second pass must not rename the interposer into d3dmt.dll
        let renamed = peDir(of: runtime).appending(path: "d3dmt.dll")
        #expect(try exportName(of: renamed) == "d3dmt.dll")
    }

    @Test("A staging file left by an interrupted install is replaced, not tripped over")
    func installReplacesStaleStagingFile() throws {
        let (store, runtime) = try makeDeployableRuntime()
        let staging = peDir(of: runtime).appending(path: "d3d12.dll.staging")
        try Data("half-written".utf8).write(to: staging)

        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)

        #expect(GPTKImporter.isVideoProcessorInstalled(inLibraryFolder: runtime))
        // the swap consumes the staged copy; nothing is left behind
        #expect(!FileManager.default.fileExists(atPath: staging.path(percentEncoded: false)))
    }

    @Test("A runtime that ships no interposer is left alone")
    func installSkipsRuntimeWithoutShim() throws {
        let store = try makeImportedStore(in: tempDir)
        try makeStoreD3D12Renameable(inStore: store)
        let runtime = tempDir.appending(path: "Libraries")
        try makeRuntime(at: runtime)

        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)

        #expect(!GPTKImporter.isVideoProcessorInstalled(inLibraryFolder: runtime))
        let renamed = peDir(of: runtime).appending(path: "d3dmt.dll")
        #expect(!FileManager.default.fileExists(atPath: renamed.path(percentEncoded: false)))
        // and the payload itself still landed
        #expect(GPTKImporter.isDeployed(inLibraryFolder: runtime))
    }

    @Test("Redeploying does not file the interposer away as Wine's own DLL")
    func redeployKeepsOriginals() throws {
        let (store, runtime) = try makeDeployableRuntime()
        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)

        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)

        let backup = store.appending(path: "originals").appending(path: "d3d12.dll")
        let backupData = try Data(contentsOf: backup)
        #expect(backupData.suffix(13) == Data("wine original".utf8))
        #expect(GPTKImporter.isVideoProcessorInstalled(inLibraryFolder: runtime))
    }

    // MARK: - Remove

    @Test("Removing the payload restores Wine's own d3d12 and clears the rename")
    func removeRestoresWine() throws {
        let (store, runtime) = try makeDeployableRuntime()
        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)

        try GPTKImporter.remove(fromLibraryFolder: runtime, usingStore: store)

        let slot = peDir(of: runtime).appending(path: "d3d12.dll")
        let restored = try Data(contentsOf: slot)
        #expect(restored.suffix(13) == Data("wine original".utf8))

        let fileManager = FileManager.default
        #expect(!fileManager.fileExists(atPath: peDir(of: runtime)
                .appending(path: "d3dmt.dll").path(percentEncoded: false)))
        let link = runtime.appending(path: "Wine").appending(path: "lib").appending(path: "wine")
            .appending(path: "x86_64-unix").appending(path: "d3dmt.so")
        #expect((try? fileManager.destinationOfSymbolicLink(atPath: link.path(percentEncoded: false))) == nil)
    }

    // MARK: - Prefixes

    @Test("A bottle gets a placeholder for the renamed DLL")
    func seedsPlaceholder() throws {
        let (store, runtime) = try makeDeployableRuntime()
        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)
        let bottle = tempDir.appending(path: "bottle")
        let system32 = bottle.appending(path: "drive_c").appending(path: "windows")
            .appending(path: "system32")
        try FileManager.default.createDirectory(at: system32, withIntermediateDirectories: true)

        GPTKImporter.seedVideoDevicePlaceholder(inBottle: bottle, fromLibraryFolder: runtime)

        #expect(FileManager.default.fileExists(
            atPath: system32.appending(path: "d3dmt.dll").path(percentEncoded: false)
        ))
    }

    @Test("A placeholder already in the prefix is left as it is")
    func keepsExistingPlaceholder() throws {
        let (store, runtime) = try makeDeployableRuntime()
        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)
        let bottle = tempDir.appending(path: "bottle")
        let system32 = bottle.appending(path: "drive_c").appending(path: "windows")
            .appending(path: "system32")
        try FileManager.default.createDirectory(at: system32, withIntermediateDirectories: true)
        let placeholder = system32.appending(path: "d3dmt.dll")
        try Data("wineboot wrote this".utf8).write(to: placeholder)

        GPTKImporter.seedVideoDevicePlaceholder(inBottle: bottle, fromLibraryFolder: runtime)

        #expect(try Data(contentsOf: placeholder) == Data("wineboot wrote this".utf8))
    }

    @Test("A directory that is not a prefix is ignored")
    func ignoresNonPrefix() throws {
        let (store, runtime) = try makeDeployableRuntime()
        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)
        let bottle = tempDir.appending(path: "not-a-bottle")
        try FileManager.default.createDirectory(at: bottle, withIntermediateDirectories: true)

        GPTKImporter.seedVideoDevicePlaceholder(inBottle: bottle, fromLibraryFolder: runtime)

        #expect(!FileManager.default.fileExists(atPath: bottle.appending(path: "drive_c")
                .path(percentEncoded: false)))
    }

    // MARK: - Every interposed slot

    @Test("A renamed DLL never outgrows the slot it came from")
    func renamedNamesFitInPlace() {
        // The export name is patched in place, so a longer replacement would
        // run off the end of the string and corrupt whatever follows it.
        for interposer in GPTKImporter.interposers {
            #expect(
                interposer.renamedName.utf8.count <= interposer.slotName.utf8.count,
                "\(interposer.renamedName) cannot replace \(interposer.slotName) in place"
            )
        }
    }

    @Test("No two interposers claim the same slot or the same renamed DLL")
    func interposersDoNotCollide() {
        let slots = GPTKImporter.interposers.map(\.slotName)
        let renamed = GPTKImporter.interposers.map(\.renamedName)
        #expect(Set(slots).count == slots.count)
        #expect(Set(renamed).count == renamed.count)
        #expect(Set(slots).isDisjoint(with: renamed))
    }

    @Test("Deploy installs the DXGI interposer with Apple's DXGI renamed beside it")
    func deployInstallsDXGIInterposer() throws {
        let interposer = GPTKImporter.dxgiVersionInterposer
        let store = try makeImportedStore(in: tempDir)
        try makeStoreD3D12Renameable(inStore: store)
        try makeStoreSlotRenameable(inStore: store, slotName: interposer.slotName)
        let runtime = tempDir.appending(path: "Libraries")
        try makeRuntime(at: runtime)
        try makeVideoProcessorShim(at: runtime)
        try makeInterposerShim(interposer, at: runtime, marker: "dxgi interposer")

        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)

        #expect(GPTKImporter.isInstalled(interposer, inLibraryFolder: runtime))
        // The fixture's name slot is sized for the longest slot name, so a
        // shorter replacement leaves the old terminator behind it.
        let renamed = peDir(of: runtime).appending(path: interposer.renamedName)
        let actual = try exportName(of: renamed).trimmingCharacters(in: ["\0"])
        #expect(actual == interposer.renamedName, "export name is \(actual)")

        let link = runtime.appending(path: "Wine").appending(path: "lib").appending(path: "wine")
            .appending(path: "x86_64-unix").appending(path: interposer.renamedUnixName)
        let destination = try FileManager.default.destinationOfSymbolicLink(
            atPath: link.path(percentEncoded: false)
        )
        #expect(destination == GPTKImporter.unixLinkDestination)
    }

    @Test("Removing takes every interposer back out, not just the first")
    func removeClearsEverySlot() throws {
        let interposer = GPTKImporter.dxgiVersionInterposer
        let store = try makeImportedStore(in: tempDir)
        try makeStoreD3D12Renameable(inStore: store)
        try makeStoreSlotRenameable(inStore: store, slotName: interposer.slotName)
        let runtime = tempDir.appending(path: "Libraries")
        try makeRuntime(at: runtime)
        try makeVideoProcessorShim(at: runtime)
        try makeInterposerShim(interposer, at: runtime, marker: "dxgi interposer")
        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)

        GPTKImporter.removeVideoProcessor(fromLibraryFolder: runtime, usingStore: store)

        for each in GPTKImporter.interposers {
            #expect(!GPTKImporter.isInstalled(each, inLibraryFolder: runtime))
            let renamed = peDir(of: runtime).appending(path: each.renamedName)
            #expect(!FileManager.default.fileExists(atPath: renamed.path(percentEncoded: false)))
        }
    }
}
