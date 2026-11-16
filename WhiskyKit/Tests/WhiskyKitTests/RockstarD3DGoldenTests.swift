//
//  RockstarD3DGoldenTests.swift
//  WhiskyKit
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

/// A bottle the Rockstar swap is not for ends up exactly as it did before the
/// swap existed: the same files, byte for byte, and the same registry
/// entries (#382).
@Suite("Rockstar Direct3D swap golden")
@MainActor
final class RockstarD3DGoldenTests {
    private let wired: RockstarD3DFixture
    private let legacy: RockstarD3DFixture
    private let roots: [URL]

    init() throws {
        wired = try RockstarD3DFixture(prefix: "rockstar_golden_wired")
        legacy = try RockstarD3DFixture(prefix: "rockstar_golden_legacy")
        roots = [wired.root, legacy.root]
    }

    deinit {
        for root in roots {
            try? FileManager.default.removeItem(at: root)
        }
    }

    /// Every file and folder under the bottle, by path relative to it, to its
    /// SHA-256 (`dir` for a folder).
    private static func snapshot(_ bottle: Bottle) -> [String: String] {
        let base = bottle.url.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
        var tree: [String: String] = [:]
        let enumerator = FileManager.default.enumerator(
            at: bottle.url, includingPropertiesForKeys: [.isDirectoryKey]
        )
        while let url = enumerator?.nextObject() as? URL {
            let path = url.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
            let relative = String(path.dropFirst(base.count))
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            tree[relative] = isDirectory ? "dir" : RockstarD3DLayoutRecord.sha256(of: url) ?? "unreadable"
        }
        return tree
    }

    /// Deploys DXVK for a Steam start in both bottles: through the swap's
    /// launch in one, the way it was before the swap in the other.
    private func deployBoth(payloadDeployed: Bool) throws -> RockstarD3DLayout? {
        for fixture in [wired, legacy] {
            try FileManager.default.createDirectory(
                at: fixture.root.appending(path: "DXMT"), withIntermediateDirectories: true
            )
        }
        try Wine.deployLauncherAndGameLayers(
            bottle: legacy.bottle, effectiveBackend: .dxvk, programOverrides: nil,
            launcherCarriesDescendantPlan: false, gameExecutables: [legacy.steamExe],
            steamGamesBackend: .d3dMetal, dxvkFolder: legacy.dxvk, dxmtFolder: legacy.root.appending(path: "DXMT")
        )
        return try Wine.deployLauncherAndGameLayers(
            bottle: wired.bottle, effectiveBackend: .dxvk, programOverrides: nil,
            launcherCarriesDescendantPlan: false, gameExecutables: [wired.steamExe],
            steamGamesBackend: .d3dMetal, dxvkFolder: wired.dxvk, dxmtFolder: wired.root.appending(path: "DXMT"),
            rockstar: wired.launch(wired.steamExe, payloadDeployed: payloadDeployed)
        )
    }

    private func expectIdentical(sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(Self.snapshot(wired.bottle) == Self.snapshot(legacy.bottle), sourceLocation: sourceLocation)
        #expect(!RockstarD3DLayoutRecord.exists(in: wired.bottle.url), sourceLocation: sourceLocation)
    }

    @Test("A Steam bottle without Rockstar, with GPTK deployed, gets the files it got before")
    func steamWithoutRockstar() throws {
        #expect(try deployBoth(payloadDeployed: true) == nil)
        expectIdentical()
    }

    @Test("A Rockstar bottle without GPTK gets the files it got before, on the builtin layout")
    func rockstarWithoutGPTK() throws {
        for fixture in [wired, legacy] {
            try fixture.installRockstar()
        }

        #expect(try deployBoth(payloadDeployed: false) == .builtin)
        expectIdentical()
    }

    @Test("A Rockstar bottle with GPTK and the setting off gets the files it got before")
    func rockstarWithTheSettingOff() throws {
        for fixture in [wired, legacy] {
            try fixture.installRockstar()
            fixture.bottle.settings.rockstarWineD3D = false
        }

        #expect(try deployBoth(payloadDeployed: true) == .degraded(.disabledByUser))
        expectIdentical()
    }

    @Test("A Steam start in a bottle without Rockstar writes the same entries, and no Direct3D key")
    func steamWithoutRockstarWritesTheSameEntries() async throws {
        let recorders = [ScopeRecorder(), ScopeRecorder()]
        for (fixture, recorder, runtime) in [
            (wired, recorders[0], wired.runtime), (
                legacy,
                recorders[1],
                RockstarD3DRuntime.unavailable(in: legacy.root)
            )
        ] {
            _ = try await Wine.prepareProgramLaunch(
                at: fixture.steamExe, bottle: fixture.bottle, recommendedBackend: .d3dMetal,
                builtinD3D12IsD3DMetal: true, overrideWriter: recorder.writer, importer: recorder.importer,
                dxvkFolder: fixture.dxvk, dxmtFolder: fixture.root.appending(path: "DXMT"), rockstarRuntime: runtime
            )
        }

        let wiredEntries = try #require(recorders[0].writes.first).map { "\($0.scope)=\($0.overrides)" }
        let legacyEntries = try #require(recorders[1].writes.first).map { "\($0.scope)=\($0.overrides)" }
        #expect(wiredEntries == legacyEntries)
        #expect(!(recorders[0].writes.first ?? []).contains { $0.scope.ownedValueNames != nil })
        #expect(!RockstarD3DLayoutRecord.exists(in: wired.bottle.url))
    }

    @Test("A Steam start in a Rockstar bottle without GPTK writes the builtin chain")
    func rockstarWithoutGPTKWritesTheBuiltinChain() async throws {
        try wired.installRockstar()
        let recorder = ScopeRecorder()

        _ = try await Wine.prepareProgramLaunch(
            at: wired.steamExe, bottle: wired.bottle, recommendedBackend: .d3dMetal,
            builtinD3D12IsD3DMetal: false, overrideWriter: recorder.writer, importer: recorder.importer,
            dxvkFolder: wired.dxvk, dxmtFolder: wired.root.appending(path: "DXMT"), rockstarRuntime: wired.runtime
        )

        recorder.expectRockstarChain(layout: .builtin)
        #expect(!RockstarD3DLayoutRecord.exists(in: wired.bottle.url))
    }

    @Test("Rockstar's Launcher.exe from the Programs tab with GPTK swaps and gets the swapped set")
    func directLaunchGetsTheSwappedSet() async throws {
        try wired.installRockstar()
        let recorder = ScopeRecorder()

        _ = try await Wine.prepareProgramLaunch(
            at: wired.rockstarLauncher, bottle: wired.bottle, recommendedBackend: .d3dMetal,
            builtinD3D12IsD3DMetal: true, overrideWriter: recorder.writer, importer: recorder.importer,
            dxvkFolder: wired.dxvk, dxmtFolder: wired.root.appending(path: "DXMT"), rockstarRuntime: wired.runtime
        )

        recorder.expectRockstarChain(layout: .swapped(source: wired.d3d11Source))
        #expect(Wine.isStrippedCopy(wired.system32("d3d11.dll"), of: wired.d3d11Source))
        #expect(wired.bottle.rockstarD3DLayout == .swapped(source: wired.d3d11Source))
    }
}
