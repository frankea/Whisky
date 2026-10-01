//
//  StaleD3D12OverrideTests.swift
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

/// A `d3d12` that 3.7.0 turned off in a game's own `AppDefaults` entry, which
/// outlived the fix for games Steam starts (#285).
@Suite("Stale d3d12 overrides")
@MainActor
final class StaleD3D12OverrideTests {
    private let tempRoot: URL

    init() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "stale_d3d12_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func makeBottle(_ backend: GraphicsBackend) throws -> Bottle {
        let bottleURL = tempRoot.appending(path: "Bottle")
        try FileManager.default.createDirectory(
            at: bottleURL.appending(path: "drive_c/windows/system32"), withIntermediateDirectories: true
        )
        let bottle = Bottle(bottleUrl: bottleURL)
        bottle.settings.graphicsBackend = backend
        return bottle
    }

    private func makeExecutable(_ relativePath: String, in bottle: Bottle) throws -> URL {
        let url = bottle.url.appending(path: "drive_c").appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("MZ".utf8).write(to: url)
        return url
    }

    private func steam(in bottle: Bottle) throws -> URL {
        try makeExecutable("Program Files (x86)/Steam/steam.exe", in: bottle)
    }

    /// Gives the bottle the user hive 3.7.0 leaves after starting RDR2.exe
    /// directly on DXVK: `d3d12` off in that executable's own entry.
    private func addStaleD3D12(to bottle: Bottle, rdr2Native: Bool = true) throws {
        let rdr2D3D11 = rdr2Native ? #""d3d11"="n,b""# : ""
        let userReg = #"""
        WINE REGISTRY Version 2

        [Software\\Wine\\AppDefaults\\RDR2.exe\\DllOverrides] 1788028200
        \#(rdr2D3D11)
        "d3d12"=""

        [Software\\Wine\\AppDefaults\\PlayRDR2.exe\\DllOverrides] 1788028200
        "d3d11"="n,b"

        """#
        try userReg.write(to: bottle.url.appending(path: "user.reg"), atomically: true, encoding: .utf8)
    }

    private func prepareGameLaunch(
        _ bottle: Bottle, plan: ProgramOverrides? = nil, payload: Bool = false, recorder: ScopeRecorder
    ) async throws {
        _ = try await Wine.prepareProgramLaunch(
            at: steam(in: bottle), args: ["-applaunch", "1174180"], bottle: bottle,
            programOverrides: plan, overridesApplyToDescendants: true,
            descendantExecutables: ["PlayRDR2.exe", "RDR2.exe"],
            recommendedBackend: payload ? .d3dMetal : .dxmt, builtinD3D12IsD3DMetal: payload,
            overrideWriter: recorder.writer, importer: recorder.importer
        )
    }

    @Test("A game launch through Steam takes a stale disabled d3d12 out of the game's own entry")
    func steamGameLaunchRemovesStaleD3D12() async throws {
        let bottle = try makeBottle(.recommended)
        try addStaleD3D12(to: bottle)
        let recorder = ScopeRecorder()

        try await prepareGameLaunch(bottle, recorder: recorder)

        #expect(recorder.imports.count == 1)
        let document = recorder.imports.first ?? ""
        #expect(document.contains(#"[HKCU\Software\Wine\AppDefaults\RDR2.exe\DllOverrides]"#))
        #expect(document.contains(#""d3d12"=-"#))
        // Only the value goes: no delete of the key, and nothing for the
        // executable that had no disabled d3d12.
        #expect(!document.contains("[-"))
        #expect(!document.contains("PlayRDR2.exe"))
    }

    @Test("With D3DMetal behind d3d12, an entry loading DXVK natively keeps d3d12 off")
    func steamGameLaunchKeepsD3D12BesideANativeLayerOverD3DMetal() async throws {
        let bottle = try makeBottle(.recommended)
        try addStaleD3D12(to: bottle)
        let recorder = ScopeRecorder()

        try await prepareGameLaunch(bottle, payload: true, recorder: recorder)

        // Taking it out would leave DXVK's dxgi in front of D3DMetal's d3d12.
        #expect(recorder.imports.isEmpty)
    }

    @Test("With D3DMetal behind d3d12, a bare disabled d3d12 still goes")
    func steamGameLaunchRemovesABareD3D12OverD3DMetal() async throws {
        let bottle = try makeBottle(.recommended)
        try addStaleD3D12(to: bottle, rdr2Native: false)
        let recorder = ScopeRecorder()

        try await prepareGameLaunch(bottle, payload: true, recorder: recorder)

        #expect(recorder.imports.count == 1)
        let document = recorder.imports.first ?? ""
        #expect(document.contains(#"[HKCU\Software\Wine\AppDefaults\RDR2.exe\DllOverrides]"#))
    }

    @Test("A game whose own plan still turns d3d12 off keeps the value")
    func steamGameLaunchKeepsD3D12TheGameStillDisables() async throws {
        let bottle = try makeBottle(.recommended)
        try addStaleD3D12(to: bottle, rdr2Native: false)
        let recorder = ScopeRecorder()
        var plan = ProgramOverrides()
        plan.graphicsBackend = .dxvk

        try await prepareGameLaunch(bottle, plan: plan, payload: true, recorder: recorder)

        #expect(recorder.imports.isEmpty)
    }

    @Test("Nothing is imported when no entry has a disabled d3d12")
    func steamGameLaunchWithoutStaleD3D12ImportsNothing() async throws {
        let bottle = try makeBottle(.recommended)
        let recorder = ScopeRecorder()

        try await prepareGameLaunch(bottle, recorder: recorder)

        #expect(recorder.imports.isEmpty)
    }

    @Test("A direct launch replaces the game's own entry, which drops a stale d3d12")
    func directLaunchReplacesTheGamesEntry() async throws {
        let bottle = try makeBottle(.recommended)
        try addStaleD3D12(to: bottle)
        let game = try makeExecutable("Games/RDR2/RDR2.exe", in: bottle)
        let recorder = ScopeRecorder()

        _ = try await Wine.prepareProgramLaunch(
            at: game, bottle: bottle, recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: true,
            overrideWriter: recorder.writer, importer: recorder.importer
        )

        // Written as a scope, so the document deletes the key before writing it.
        #expect(recorder.programScopes == ["RDR2.exe"])
        #expect(recorder.overrides(for: .program("RDR2.exe"))?["d3d12"] == nil)
        let document = Wine.registryDocument(for: [
            (key: Wine.DLLOverrideScope.program("RDR2.exe").registryKey, overrides: [:])
        ])
        #expect(document.contains(#"[-HKCU\Software\Wine\AppDefaults\RDR2.exe\DllOverrides]"#))
    }
}
