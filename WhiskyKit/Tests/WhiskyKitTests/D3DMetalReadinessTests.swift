//
//  D3DMetalReadinessTests.swift
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

/// D3DMetal needs both an imported payload and a GPTK-capable engine; the app
/// must say which one is missing (#358).
@Suite("D3DMetal readiness")
struct D3DMetalReadinessTests {
    // MARK: - The four cases

    @Test("Payload not imported on a capable engine needs the payload")
    func capableEngineWithoutPayload() {
        let readiness = D3DMetalReadiness(payloadImported: false, engineCapable: true, payloadInRuntime: false)
        #expect(readiness == .payloadMissing)
        #expect(readiness.needsPayload)
        #expect(!readiness.needsCapableEngine)
        #expect(!readiness.isAvailable)
    }

    @Test("Payload imported on an incapable engine blames the engine, not the payload")
    func importedPayloadOnIncapableEngine() {
        let readiness = D3DMetalReadiness(payloadImported: true, engineCapable: false, payloadInRuntime: false)
        #expect(readiness == .engineNotCapable)
        #expect(readiness.needsCapableEngine)
        #expect(!readiness.needsPayload)
        #expect(!readiness.isAvailable)
    }

    @Test("Neither payload nor capable engine needs both")
    func neither() {
        let readiness = D3DMetalReadiness(payloadImported: false, engineCapable: false, payloadInRuntime: false)
        #expect(readiness == .payloadAndEngineMissing)
        #expect(readiness.needsCapableEngine)
        #expect(readiness.needsPayload)
        #expect(!readiness.isAvailable)
    }

    @Test("Imported payload deployed into a capable engine is available")
    func both() {
        let readiness = D3DMetalReadiness(payloadImported: true, engineCapable: true, payloadInRuntime: true)
        #expect(readiness == .available)
        #expect(readiness.isAvailable)
        #expect(!readiness.needsCapableEngine)
        #expect(!readiness.needsPayload)
    }

    // MARK: - Edges

    @Test("A payload in the runtime is available whatever the store and engine say")
    func payloadInRuntimeWins() {
        for imported in [false, true] {
            for capable in [false, true] {
                let readiness = D3DMetalReadiness(
                    payloadImported: imported, engineCapable: capable, payloadInRuntime: true
                )
                #expect(readiness == .available)
            }
        }
    }

    @Test("An imported payload not yet in a capable engine is not reported as missing")
    func undeployedPayloadOnCapableEngine() {
        let readiness = D3DMetalReadiness(payloadImported: true, engineCapable: true, payloadInRuntime: false)
        #expect(readiness == .payloadNotDeployed)
        #expect(!readiness.needsPayload)
        #expect(!readiness.needsCapableEngine)
        #expect(!readiness.isAvailable)
    }

    @Test("Available exactly when the backend picker offers D3DMetal")
    func agreesWithBackendAvailability() {
        for imported in [false, true] {
            for capable in [false, true] {
                for inRuntime in [false, true] {
                    let readiness = D3DMetalReadiness(
                        payloadImported: imported, engineCapable: capable, payloadInRuntime: inRuntime
                    )
                    let offered = WhiskyWineInstaller.backendAvailability(
                        .d3dMetal,
                        runtimeInfo: WhiskyWineVersion(version: .init(3, 1, 1), gptkCapable: capable),
                        d3dMetalInstalled: inRuntime,
                        dxmtRuntimeNative: true
                    )
                    #expect(readiness.isAvailable == offered)
                }
            }
        }
    }

    @Test("The engine releases link points at this project's releases page")
    func engineReleasesURL() {
        #expect(D3DMetalReadiness.engineReleasesURL?.absoluteString == "https://github.com/frankea/Whisky/releases")
    }

    // MARK: - Reading the disk

    @Test("The #358 setup: payload imported into the stock engine")
    func importedIntoStockEngineOnDisk() throws {
        let tempDir = try makeGPTKTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let store = try makeImportedStore(in: tempDir)
        let runtime = tempDir.appending(path: "Libraries")
        try makeRuntime(at: runtime)
        // The stock engine's plist carries no gptkCapable key.
        try writeRuntimeVersion(at: runtime, 3, 1, 1)

        #expect(D3DMetalReadiness.current(store: store, libraryFolder: runtime) == .engineNotCapable)
    }

    @Test("A capable engine without an import needs the payload")
    func capableEngineWithoutImportOnDisk() throws {
        let tempDir = try makeGPTKTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let runtime = tempDir.appending(path: "Libraries")
        try makeRuntime(at: runtime)
        try writeCapableRuntimeVersion(at: runtime)

        let emptyStore = tempDir.appending(path: "store")
        #expect(D3DMetalReadiness.current(store: emptyStore, libraryFolder: runtime) == .payloadMissing)
    }

    @Test("No runtime and no import needs both")
    func nothingOnDisk() throws {
        let tempDir = try makeGPTKTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let readiness = D3DMetalReadiness.current(
            store: tempDir.appending(path: "store"), libraryFolder: tempDir.appending(path: "Libraries")
        )
        #expect(readiness == .payloadAndEngineMissing)
    }

    @Test("A deployed payload on a capable engine is available")
    func deployedOnDisk() throws {
        let tempDir = try makeGPTKTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let store = try makeImportedStore(in: tempDir)
        let runtime = tempDir.appending(path: "Libraries")
        try makeRuntime(at: runtime)
        try writeCapableRuntimeVersion(at: runtime)
        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)

        #expect(D3DMetalReadiness.current(store: store, libraryFolder: runtime) == .available)
    }

    @Test("A capable engine installed by hand after the import gets the payload at launch")
    func capableEngineInstalledAfterImportOnDisk() throws {
        let tempDir = try makeGPTKTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let store = try makeImportedStore(in: tempDir)
        let runtime = tempDir.appending(path: "Libraries")
        try makeRuntime(at: runtime)
        try writeCapableRuntimeVersion(at: runtime)

        #expect(D3DMetalReadiness.current(store: store, libraryFolder: runtime) == .payloadNotDeployed)

        #expect(GPTKImporter.deployStoredPayloadIfMissing(
            fromStore: store, intoLibraryFolder: runtime, isAppleSigned: { _, _ in true }
        ))
        #expect(D3DMetalReadiness.current(store: store, libraryFolder: runtime) == .available)
        // Already there: launch leaves it alone instead of copying it again.
        #expect(!GPTKImporter.deployStoredPayloadIfMissing(
            fromStore: store, intoLibraryFolder: runtime, isAppleSigned: { _, _ in true }
        ))
    }

    @Test("Launch never deploys the stored payload into an engine that can't run it")
    func launchLeavesStockEngineAlone() throws {
        let tempDir = try makeGPTKTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let store = try makeImportedStore(in: tempDir)
        let runtime = tempDir.appending(path: "Libraries")
        try makeRuntime(at: runtime)
        try writeRuntimeVersion(at: runtime, 3, 1, 1)

        #expect(!GPTKImporter.deployStoredPayloadIfMissing(
            fromStore: store, intoLibraryFolder: runtime, isAppleSigned: { _, _ in true }
        ))
        #expect(!GPTKImporter.isDeployed(inLibraryFolder: runtime))
        #expect(D3DMetalReadiness.current(store: store, libraryFolder: runtime) == .engineNotCapable)
    }

    private func writeCapableRuntimeVersion(at libraryFolder: URL) throws {
        let plist: [String: Any] = [
            "version": ["major": 4, "minor": 6, "patch": 4],
            "gptkCapable": true
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: libraryFolder.appending(path: "WhiskyWineVersion").appendingPathExtension("plist"))
    }
}
