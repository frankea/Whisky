//
//  GPTKDeploymentTests.swift
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

@Suite("GPTK Deployment Tests")
struct GPTKDeploymentTests {
    private let tempDir: URL

    init() throws {
        tempDir = try makeGPTKTempDir()
    }

    // MARK: - Deployment

    @Test("Deploy backs up Wine's originals and places the payload")
    func deploy() throws {
        let store = try makeImportedStore(in: tempDir)
        let runtime = tempDir.appending(path: "Libraries")
        try makeRuntime(at: runtime)

        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)

        let backup = store.appending(path: "originals").appending(path: "d3d11.dll")
        let backupData = try Data(contentsOf: backup)
        #expect(backupData.suffix(13) == Data("wine original".utf8))

        let wineLib = runtime.appending(path: "Wine").appending(path: "lib")
        let deployed = wineLib.appending(path: "wine").appending(path: "x86_64-windows")
            .appending(path: "dxgi.dll")
        #expect(FileManager.default.fileExists(atPath: deployed.path(percentEncoded: false)))
        #expect(GPTKImporter.isDeployed(inLibraryFolder: runtime))

        let link = wineLib.appending(path: "wine").appending(path: "x86_64-unix")
            .appending(path: "d3d12.so")
        let destination = try FileManager.default.destinationOfSymbolicLink(
            atPath: link.path(percentEncoded: false)
        )
        #expect(destination == GPTKImporter.unixLinkDestination)
    }

    @Test("Redeploying never overwrites the backed-up originals")
    func redeployKeepsOriginals() throws {
        let store = try makeImportedStore(in: tempDir)
        let runtime = tempDir.appending(path: "Libraries")
        try makeRuntime(at: runtime)

        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)
        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)

        let backup = store.appending(path: "originals").appending(path: "d3d11.dll")
        let backupData = try Data(contentsOf: backup)
        #expect(backupData.suffix(13) == Data("wine original".utf8))
    }

    @Test("Deploying from an empty store fails")
    func deployEmptyStore() throws {
        let runtime = tempDir.appending(path: "Libraries")
        try makeRuntime(at: runtime)

        #expect(throws: GPTKImportError.storeEmpty) {
            try GPTKImporter.deploy(
                fromStore: tempDir.appending(path: "missing"), intoLibraryFolder: runtime
            )
        }
    }

    @Test("Remove restores the originals and clears the payload")
    func removeRestores() throws {
        let store = try makeImportedStore(in: tempDir)
        let runtime = tempDir.appending(path: "Libraries")
        try makeRuntime(at: runtime)
        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)

        try GPTKImporter.remove(fromLibraryFolder: runtime, usingStore: store)

        let wineLib = runtime.appending(path: "Wine").appending(path: "lib")
        let restored = wineLib.appending(path: "wine").appending(path: "x86_64-windows")
            .appending(path: "d3d11.dll")
        let restoredData = try Data(contentsOf: restored)
        #expect(restoredData.suffix(13) == Data("wine original".utf8))
        #expect(!GPTKImporter.isDeployed(inLibraryFolder: runtime))

        let external = wineLib.appending(path: "external")
        #expect(!FileManager.default.fileExists(atPath: external.path(percentEncoded: false)))
    }

    // MARK: - Surviving a runtime install

    @Test("The store and its backups survive a runtime reinstall")
    func storeSurvivesRuntimeInstall() throws {
        let appSupport = tempDir.appending(path: "AppSupport")
        let store = GPTKImporter.storeFolder(inApplicationFolder: appSupport)
        let lib = tempDir.appending(path: "payload")
        try makePayload(at: lib)
        let payload = try GPTKImporter.validatePayload(at: lib, isAppleSigned: { _ in true })
        try GPTKImporter.importPayload(payload, intoStore: store)

        let runtime = appSupport.appending(path: "Libraries")
        try makeRuntime(at: runtime)
        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)

        let tarball = try makeLibrariesTarball(in: tempDir.appending(path: "archive"))
        try WhiskyWineInstaller.install(tarball: tarball, into: appSupport)

        #expect(GPTKImporter.storedRecord(inStore: store)?.gptkVersion == "4.0b2")
        let backup = store.appending(path: "originals").appending(path: "d3d11.dll")
        #expect(FileManager.default.fileExists(atPath: backup.path(percentEncoded: false)))
    }

    @Test("A new engine discards backups taken from the previous one")
    func redeployAfterEngineChangeRetakesOriginals() throws {
        let store = try makeImportedStore(in: tempDir)
        let runtime = tempDir.appending(path: "Libraries")
        try makeRuntime(at: runtime)
        try writeRuntimeVersion(at: runtime, 4, 0, 0)
        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)

        try makeRuntime(at: runtime, marker: "wine 11 original")
        try writeRuntimeVersion(at: runtime, 5, 0, 0)
        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)

        let backup = store.appending(path: "originals").appending(path: "d3d11.dll")
        let backupData = try Data(contentsOf: backup)
        #expect(backupData.suffix(16) == Data("wine 11 original".utf8))
    }

    @Test("Remove drops backups from a replaced engine instead of restoring them")
    func removeDiscardsStaleOriginals() throws {
        let store = try makeImportedStore(in: tempDir)
        let runtime = tempDir.appending(path: "Libraries")
        try makeRuntime(at: runtime)
        try writeRuntimeVersion(at: runtime, 4, 0, 0)
        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)

        // A runtime install replaced the tree without a redeploy in between.
        try makeRuntime(at: runtime, marker: "wine 11 original")
        try writeRuntimeVersion(at: runtime, 5, 0, 0)

        try GPTKImporter.remove(fromLibraryFolder: runtime, usingStore: store)

        let current = runtime.appending(path: "Wine").appending(path: "lib")
            .appending(path: "wine").appending(path: "x86_64-windows").appending(path: "d3d11.dll")
        let currentData = try Data(contentsOf: current)
        #expect(currentData.suffix(16) == Data("wine 11 original".utf8))

        let backup = store.appending(path: "originals").appending(path: "d3d11.dll")
        #expect(!FileManager.default.fileExists(atPath: backup.path(percentEncoded: false)))
    }

    @Test("Remove spares Wine builtins an interrupted deploy never swapped")
    func removeSparesUntouchedBuiltins() throws {
        let store = try makeImportedStore(in: tempDir)
        let runtime = tempDir.appending(path: "Libraries")
        try makeRuntime(at: runtime)
        try writeRuntimeVersion(at: runtime, 4, 0, 0)
        let peDir = try makePartialDeploy(store: store, runtime: runtime, runtimeVersion: "4.0.0")

        try GPTKImporter.remove(fromLibraryFolder: runtime, usingStore: store)

        // Swapped, backed up only, and never touched all end as Wine's own.
        for name in ["d3d10.dll", "d3d11.dll", "d3d12.dll"] {
            let data = try Data(contentsOf: peDir.appending(path: name))
            #expect(data.suffix(13) == Data("wine original".utf8))
        }
    }

    // MARK: - Runtime capability flag

    @Test("gptkCapable decodes when present and stays nil when absent")
    func gptkCapableDecoding() throws {
        let capable = WhiskyWineVersion(
            version: .init(4, 0, 0), gptkCapable: true
        )
        let encoder = PropertyListEncoder()
        let decoded = try PropertyListDecoder().decode(
            WhiskyWineVersion.self, from: encoder.encode(capable)
        )
        #expect(decoded.gptkCapable == true)

        let legacy = WhiskyWineVersion(version: .init(3, 1, 1))
        let decodedLegacy = try PropertyListDecoder().decode(
            WhiskyWineVersion.self, from: encoder.encode(legacy)
        )
        #expect(decodedLegacy.gptkCapable == nil)
    }
}
