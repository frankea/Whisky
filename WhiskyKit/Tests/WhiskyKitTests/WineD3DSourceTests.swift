//
//  WineD3DSourceTests.swift
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

@Suite("Wine D3D source resolution")
struct WineD3DSourceTests {
    private let tempDir: URL
    private let runtime: URL
    private let store: URL

    /// A runtime holding Wine's own d3d builtins, stamped 11.19.0, and a store
    /// holding an imported payload that has not been deployed yet.
    init() throws {
        tempDir = try makeGPTKTempDir()
        runtime = tempDir.appending(path: "Libraries")
        try makeRuntime(at: runtime)
        try writeRuntimeVersion(at: runtime, 11, 19, 0)
        store = try makeImportedStore(in: tempDir)
        var d3d10core = fakePE(builtin: true)
        d3d10core.append(Data("wine d3d10core".utf8))
        try d3d10core.write(to: peDir.appending(path: "d3d10core.dll"))
    }

    private var peDir: URL {
        runtime.appending(path: "Wine").appending(path: "lib").appending(path: "wine")
            .appending(path: "x86_64-windows")
    }

    private func original(_ name: String) -> URL {
        store.appending(path: "originals").appending(path: name)
    }

    private func resolve(_ name: String, store: URL? = nil) -> WineD3DSource {
        WineD3DSource.resolve(name, libraryFolder: runtime, store: store ?? self.store)
    }

    private func deploy() throws {
        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)
    }

    // MARK: - lib/wine

    @Test("d3d10core always comes from lib/wine, GPTK deployed or not")
    func d3d10coreAlwaysLibWine() throws {
        let expected = WineD3DSource.libWine(peDir.appending(path: "d3d10core.dll"))
        #expect(resolve("d3d10core.dll") == expected)

        try deploy()

        #expect(resolve("d3d10core.dll") == expected)
    }

    @Test("Without GPTK, d3d11 and dxgi come straight from lib/wine")
    func nonForwarderUsesLibWine() {
        #expect(resolve("d3d11.dll") == .libWine(peDir.appending(path: "d3d11.dll")))
        #expect(resolve("dxgi.dll") == .libWine(peDir.appending(path: "dxgi.dll")))
    }

    @Test("The name is matched without case and with or without .dll")
    func nameIsNormalised() {
        #expect(resolve("DXGI") == resolve("dxgi.dll"))
        #expect(resolve("D3D10Core.DLL") == resolve("d3d10core.dll"))
    }

    @Test("A native file in lib/wine is not Wine's build")
    func unmarkedLibWineIsRefused() throws {
        try fakePE(builtin: false).write(to: peDir.appending(path: "dxgi.dll"))
        try Data("stub".utf8).write(to: peDir.appending(path: "d3d10core.dll"))

        #expect(resolve("dxgi.dll") == .unavailable(.notBuiltinMarked))
        #expect(resolve("d3d10core.dll") == .unavailable(.notBuiltinMarked))
    }

    @Test("A missing lib/wine file is reported, not guessed at")
    func missingLibWineFile() throws {
        try FileManager.default.removeItem(at: peDir.appending(path: "d3d10core.dll"))

        #expect(resolve("d3d10core.dll") == .unavailable(.missingFile))
    }

    @Test("A missing d3d11 or dxgi slot without GPTK is reported, not looked for in originals")
    func missingNonGPTKSlotIsNotTakenFromOriginals() throws {
        // Current backups in the store, but no payload in the tree.
        try deploy()
        try GPTKImporter.remove(fromLibraryFolder: runtime, usingStore: store)
        let originals = store.appending(path: "originals")
        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
        for name in ["d3d11.dll", "dxgi.dll"] {
            try FileManager.default.copyItem(at: peDir.appending(path: name), to: original(name))
            try FileManager.default.removeItem(at: peDir.appending(path: name))
        }
        #expect(!GPTKImporter.isDeployed(inLibraryFolder: runtime))

        #expect(resolve("d3d11.dll") == .unavailable(.missingFile))
        #expect(resolve("dxgi.dll") == .unavailable(.missingFile))
    }

    @Test("Wine's builtin is told from Apple's forwarder by its wined3d import")
    func wined3dImportTellsWineFromForwarder() throws {
        #expect(WineD3DSource.importsWined3d(peDir.appending(path: "d3d11.dll")))
        let forwarder = store.appending(path: "lib/wine/x86_64-windows/d3d11.dll")
        #expect(Wine.carriesBuiltinMarker(forwarder))
        #expect(!WineD3DSource.importsWined3d(forwarder))
    }

    @Test("A forwarder left behind with no bridges and no store match is never taken for Wine's")
    func strandedForwarderIsNotLibWine() throws {
        // A removal against originals stamped for an older engine drops the
        // backups and the bridges but leaves Apple's forwarders in the slots.
        try deploy()
        try writeRuntimeVersion(at: runtime, 11, 20, 0)
        try GPTKImporter.remove(fromLibraryFolder: runtime, usingStore: store)
        #expect(!GPTKImporter.isDeployed(inLibraryFolder: runtime))
        // Then another GPTK build is imported, so the slot no longer
        // byte-matches the store either.
        for name in ["d3d11.dll", "dxgi.dll"] {
            var other = fakePE(builtin: true)
            other.append(Data("another gptk build".utf8))
            try other.write(to: store.appending(path: "lib/wine/x86_64-windows").appending(path: name))
        }

        #expect(resolve("d3d11.dll") == .unavailable(.missingFile))
        #expect(resolve("dxgi.dll") == .unavailable(.missingFile))
    }

    @Test("A stranded forwarder with current backups resolves to those backups")
    func strandedForwarderWithCurrentOriginals() throws {
        try deploy()
        try FileManager.default.removeItem(at: runtime.appending(path: "Wine/lib/wine/x86_64-unix/dxgi.so"))
        var other = fakePE(builtin: true)
        other.append(Data("another gptk build".utf8))
        try other.write(to: store.appending(path: "lib/wine/x86_64-windows/d3d11.dll"))
        #expect(!GPTKImporter.isDeployed(inLibraryFolder: runtime))

        #expect(resolve("d3d11.dll") == .originals(original("d3d11.dll")))
    }

    @Test("DLLs GPTK and Wine do not share in this way are not resolved")
    func unsupportedDLL() {
        #expect(resolve("d3d12.dll") == .unavailable(.unsupportedDLL("d3d12.dll")))
    }

    // MARK: - originals

    @Test("Under a deployed payload with a current stamp, d3d11 and dxgi come from originals")
    func forwarderWithCurrentStampUsesOriginals() throws {
        try deploy()

        #expect(resolve("d3d11.dll") == .originals(original("d3d11.dll")))
        #expect(resolve("dxgi.dll") == .originals(original("dxgi.dll")))
    }

    @Test("A slot that byte-matches the store's forwarder counts as GPTK's before the deploy finishes")
    func forwarderSlotWithoutBridgeUsesOriginals() throws {
        try deploy()
        try FileManager.default.removeItem(
            at: runtime.appending(path: "Wine/lib/wine/x86_64-unix/dxgi.so")
        )
        #expect(!GPTKImporter.isDeployed(inLibraryFolder: runtime))

        #expect(resolve("dxgi.dll") == .originals(original("dxgi.dll")))
    }

    @Test("The dxgi interposer in the slot is not mistaken for Wine's dxgi")
    func interposedSlotUsesOriginals() throws {
        try makeInterposerShim(GPTKImporter.dxgiVersionInterposer, at: runtime)
        try makeStoreSlotRenameable(inStore: store, slotName: "dxgi.dll")
        try deploy()
        #expect(GPTKImporter.isInstalled(GPTKImporter.dxgiVersionInterposer, inLibraryFolder: runtime))

        #expect(resolve("dxgi.dll") == .originals(original("dxgi.dll")))
    }

    @Test("Originals stamped for another engine are refused")
    func staleStampIsRefused() throws {
        try deploy()
        try writeRuntimeVersion(at: runtime, 11, 20, 0)

        #expect(resolve("dxgi.dll") == .unavailable(.staleOriginals(found: "11.19.0", expected: "11.20.0")))
    }

    @Test("Originals without a stamp are refused")
    func missingStampIsRefused() throws {
        try deploy()
        try FileManager.default.removeItem(at: GPTKImporter.originalsRecordURL(inStore: store))

        #expect(resolve("d3d11.dll") == .unavailable(.staleOriginals(found: nil, expected: "11.19.0")))
    }

    @Test("A missing original is reported")
    func missingOriginal() throws {
        try deploy()
        try FileManager.default.removeItem(at: original("dxgi.dll"))

        #expect(resolve("dxgi.dll") == .unavailable(.missingFile))
    }

    @Test("An unmarked original is refused")
    func unmarkedOriginalIsRefused() throws {
        try deploy()
        try fakePE(builtin: false).write(to: original("dxgi.dll"))

        #expect(resolve("dxgi.dll") == .unavailable(.notBuiltinMarked))
    }

    @Test("A payload copied in by hand with no backups is reported as such")
    func handPlacedPayload() throws {
        try makePayload(at: runtime.appending(path: "Wine").appending(path: "lib"))
        let emptyStore = tempDir.appending(path: "empty-store")

        #expect(resolve("dxgi.dll", store: emptyStore) == .unavailable(.handPlacedPayload))
        #expect(resolve("d3d11.dll", store: emptyStore) == .unavailable(.handPlacedPayload))
        #expect(resolve("d3d10core.dll", store: emptyStore) == .libWine(peDir.appending(path: "d3d10core.dll")))
    }
}
