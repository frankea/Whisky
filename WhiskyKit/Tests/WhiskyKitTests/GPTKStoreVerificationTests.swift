//
//  GPTKStoreVerificationTests.swift
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

/// A store imported before imports checked Apple's signature is checked once
/// before it is deployed, and only deployed when it passes.
@Suite("GPTK Store Verification Tests")
struct GPTKStoreVerificationTests {
    private let tempDir: URL

    init() throws {
        tempDir = try makeGPTKTempDir()
    }

    /// A store imported without the checks, the way every store from before
    /// them was, and an empty runtime to deploy into.
    private func makeUncheckedStoreAndRuntime() throws -> (store: URL, runtime: URL) {
        let store = try makeImportedStore(in: tempDir)
        let runtime = tempDir.appending(path: "Libraries")
        try makeRuntime(at: runtime)
        return (store, runtime)
    }

    private func storeForwarder(_ store: URL, _ name: String = "d3d11.dll") -> URL {
        store.appending(path: "lib").appending(path: "wine").appending(path: "x86_64-windows").appending(path: name)
    }

    @Test("An unchecked store that passes is deployed and stamped")
    func uncheckedGoodStoreDeploysAndIsStamped() throws {
        let (store, runtime) = try makeUncheckedStoreAndRuntime()
        #expect(GPTKImporter.storeStamp(inStore: store) == nil)
        var checked: [String] = []

        let deployed = GPTKImporter.deployStoredPayloadIfPresent(
            fromStore: store, intoLibraryFolder: runtime, isAppleSigned: { code, _ in
                checked.append(code.lastPathComponent)
                return true
            }
        )

        #expect(deployed)
        #expect(GPTKImporter.isStorePayloadDeployed(inLibraryFolder: runtime, usingStore: store))
        #expect(checked == ["libd3dshared.dylib", "D3DMetal.framework"])
        let stamp = try #require(GPTKImporter.storeStamp(inStore: store))
        #expect(stamp.failure == nil)
        #expect(stamp.fingerprint == GPTKImporter.storeFingerprint(inStore: store))
        #expect(GPTKImporter.storeVerificationFailure(inStore: store) == nil)
    }

    @Test("A store that fails is not deployed and reports why")
    func failingStoreIsNotDeployed() throws {
        let (store, runtime) = try makeUncheckedStoreAndRuntime()

        let deployed = GPTKImporter.deployStoredPayloadIfPresent(
            fromStore: store, intoLibraryFolder: runtime, isAppleSigned: { _, _ in false }
        )

        #expect(!deployed)
        #expect(!GPTKImporter.isDeployed(inLibraryFolder: runtime))
        let expected = GPTKImportError.notAppleSigned("external/libd3dshared.dylib").localizedDescription
        #expect(GPTKImporter.storeVerificationFailure(inStore: store) == expected)
        let verdict = GPTKImporter.storeVerdict(inStore: store, isAppleSigned: { _, _ in true })
        #expect(verdict == .failed(reason: expected))
    }

    @Test("A failing store's earlier deployment is taken back out")
    func failingStoreDeploymentIsWithdrawn() throws {
        let (store, runtime) = try makeUncheckedStoreAndRuntime()
        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)
        let peDir = runtime.appending(path: "Wine").appending(path: "lib").appending(path: "wine")
            .appending(path: "x86_64-windows")

        let verdict = GPTKImporter.verifyStoredPayload(
            inStore: store, libraryFolder: runtime, isAppleSigned: { _, _ in false }
        )

        #expect(verdict != .verified)
        #expect(!GPTKImporter.isDeployed(inLibraryFolder: runtime))
        let restored = try Data(contentsOf: peDir.appending(path: "d3d11.dll"))
        #expect(restored.suffix(13) == Data("wine original".utf8))
    }

    @Test("A payload copied in by hand stays when the store fails")
    func failingStoreLeavesHandPlacedPayload() throws {
        let fixture = try GPTKInterposerFixture()
        let store = try fixture.makeStore(version: GPTKInterposerFixture.validatedVersion)
        let runtime = try fixture.makeRuntimeTree()
        try fixture.overlayPayloadByHand(version: "3.0", into: runtime)

        let deployed = GPTKImporter.deployStoredPayloadIfPresent(
            fromStore: store, intoLibraryFolder: runtime, isAppleSigned: { _, _ in false }
        )

        #expect(!deployed)
        #expect(GPTKImporter.deployedPayloadVersion(inLibraryFolder: runtime) == "3.0")
        #expect(GPTKImporter.isDeployed(inLibraryFolder: runtime))
    }

    @Test("A stamped store is not checked again")
    func stampedStoreSkipsChecks() throws {
        let (store, runtime) = try makeUncheckedStoreAndRuntime()
        #expect(GPTKImporter.deployStoredPayloadIfPresent(
            fromStore: store, intoLibraryFolder: runtime, isAppleSigned: { _, _ in true }
        ))
        var checks = 0

        let redeployed = GPTKImporter.deployStoredPayloadIfPresent(
            fromStore: store, intoLibraryFolder: runtime, isAppleSigned: { _, _ in
                checks += 1
                return false
            }
        )

        #expect(redeployed)
        #expect(checks == 0)
    }

    @Test("A failure is remembered too, until the store changes")
    func stampedFailureSkipsChecks() throws {
        let (store, runtime) = try makeUncheckedStoreAndRuntime()
        GPTKImporter.verifyStoredPayload(inStore: store, libraryFolder: runtime, isAppleSigned: { _, _ in false })
        var checks = 0

        let deployed = GPTKImporter.deployStoredPayloadIfPresent(
            fromStore: store, intoLibraryFolder: runtime, isAppleSigned: { _, _ in
                checks += 1
                return true
            }
        )

        #expect(!deployed)
        #expect(checks == 0)
    }

    @Test("A store that changed after its stamp is checked again")
    func changedStoreIsCheckedAgain() throws {
        let (store, runtime) = try makeUncheckedStoreAndRuntime()
        #expect(GPTKImporter.storeVerdict(inStore: store, isAppleSigned: { _, _ in true }) == .verified)
        var dll = try Data(contentsOf: storeForwarder(store))
        dll.append(Data("changed".utf8))
        try dll.write(to: storeForwarder(store))
        #expect(GPTKImporter.storeVerificationFailure(inStore: store) == nil)
        var checks = 0

        let deployed = GPTKImporter.deployStoredPayloadIfPresent(
            fromStore: store, intoLibraryFolder: runtime, isAppleSigned: { _, _ in
                checks += 1
                return false
            }
        )

        #expect(!deployed)
        #expect(checks == 1)
        #expect(GPTKImporter.storeVerificationFailure(inStore: store) != nil)
    }

    @Test("Reimporting replaces a failing stamp")
    func reimportClearsFailure() throws {
        let (store, runtime) = try makeUncheckedStoreAndRuntime()
        GPTKImporter.verifyStoredPayload(inStore: store, libraryFolder: runtime, isAppleSigned: { _, _ in false })
        #expect(GPTKImporter.storeVerificationFailure(inStore: store) != nil)
        let lib = tempDir.appending(path: "payload")
        let payload = try GPTKImporter.validatePayload(at: lib, isAppleSigned: { _, _ in true })
        var checks = 0

        try GPTKImporter.importPayload(payload, intoStore: store, revalidatingWith: { _, _ in true })
        let verdict = GPTKImporter.storeVerdict(inStore: store, isAppleSigned: { _, _ in
            checks += 1
            return false
        })

        #expect(verdict == .verified)
        #expect(checks == 0)
        #expect(GPTKImporter.storeVerificationFailure(inStore: store) == nil)
    }

    @Test("Deploying leaves the fingerprint as it was")
    func deployKeepsFingerprint() throws {
        let (store, runtime) = try makeUncheckedStoreAndRuntime()
        try makeStoreMetalFXBridge(inStore: store)
        let before = try #require(GPTKImporter.storeFingerprint(inStore: store))

        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)
        try GPTKImporter.remove(fromLibraryFolder: runtime, usingStore: store)

        #expect(GPTKImporter.storeFingerprint(inStore: store) == before)
    }

    @Test("Without a stored payload there is no verdict")
    func emptyStoreHasNoVerdict() {
        let store = tempDir.appending(path: "empty-store")

        #expect(GPTKImporter.storeVerdict(inStore: store, isAppleSigned: { _, _ in true }) == nil)
        #expect(GPTKImporter.storeVerificationFailure(inStore: store) == nil)
    }
}
