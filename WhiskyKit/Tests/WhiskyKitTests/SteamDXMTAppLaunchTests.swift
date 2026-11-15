//
//  SteamDXMTAppLaunchTests.swift
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

/// Reproduction: what a `steam.exe -applaunch` launch leaves in `system32` when
/// the game's plan resolves to DXMT, and what the game's `AppDefaults` entry
/// says. The assertions pin the CURRENT behavior: DXMT's trio is deployed, then
/// the launcher's DXVK copy overwrites `d3d11`/`d3d10core` and the DXVK dxgi
/// reconcile removes DXMT's native `dxgi`, while the game's entry still says
/// `n,b` for all three. The game therefore loads DXVK's `d3d11` beside a
/// non-DXMT `dxgi`: it runs on DXVK, not DXMT.
@Suite("Steam -applaunch over a DXMT plan (reproduction)")
@MainActor
final class SteamDXMTAppLaunchTests {
    private let tempRoot: URL
    private let game = "Game.exe"
    private let trio = ["d3d11.dll", "d3d10core.dll", "dxgi.dll"]

    init() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "steam_dxmt_applaunch_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    /// A markerless (native) PE stub tagged with its origin after the 0x40 window.
    private func nativeFake(_ tag: String) -> Data {
        Data(count: 0x40) + Data(tag.utf8) + Data(count: 16)
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

    private func steam(in bottle: Bottle) throws -> URL {
        let url = bottle.url.appending(path: "drive_c/Program Files (x86)/Steam/steam.exe")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("MZ".utf8).write(to: url)
        return url
    }

    /// DXVK-macOS ships d3d10core and d3d11 (and d3d9), never dxgi.
    private func makeDXVKPayload() throws -> URL {
        let root = tempRoot.appending(path: "DXVK")
        for arch in ["x64", "x32"] {
            let folder = root.appending(path: arch)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for dll in ["d3d11.dll", "d3d10core.dll"] {
                try nativeFake("DXVK \(arch) \(dll)").write(to: folder.appending(path: dll))
            }
        }
        return root
    }

    private func makeDXMTPayload() throws -> URL {
        let root = tempRoot.appending(path: "DXMT")
        for arch in ["x64", "x32"] {
            let folder = root.appending(path: arch)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for dll in trio + ["winemetal.dll"] {
                try nativeFake("DXMT \(arch) \(dll)").write(to: folder.appending(path: dll))
            }
        }
        return root
    }

    private func system32(_ bottle: Bottle, _ dll: String) -> URL {
        bottle.url.appending(path: "drive_c/windows/system32").appending(path: dll)
    }

    private func contents(_ url: URL) -> Data? {
        try? Data(contentsOf: url)
    }

    private func prepareAppLaunch(
        _ bottle: Bottle, plan: ProgramOverrides? = nil, recommendedBackend: GraphicsBackend,
        builtinD3D12IsD3DMetal: Bool, recorder: ScopeRecorder
    ) async throws {
        _ = try await Wine.prepareProgramLaunch(
            at: steam(in: bottle), args: ["-applaunch", "480"], bottle: bottle,
            programOverrides: plan, overridesApplyToDescendants: true, descendantExecutables: [game],
            recommendedBackend: recommendedBackend, builtinD3D12IsD3DMetal: builtinD3D12IsD3DMetal,
            overrideWriter: recorder.writer, importer: recorder.importer,
            dxvkFolder: makeDXVKPayload(), dxmtFolder: makeDXMTPayload()
        )
    }

    /// The DXMT plan's prefix state after the launch: DXVK's d3d11/d3d10core and no DXMT dxgi.
    private func expectDXVKReplacedDXMT(_ bottle: Bottle) {
        for dll in ["d3d11.dll", "d3d10core.dll"] {
            #expect(contents(system32(bottle, dll)) == nativeFake("DXVK x64 \(dll)"), "system32 \(dll) is DXVK's")
        }
        // Removed (or replaced by a builtin placeholder / clean Wine copy): never DXMT's.
        #expect(contents(system32(bottle, "dxgi.dll")) != nativeFake("DXMT x64 dxgi.dll"), "DXMT's dxgi is gone")
        // DXMT's winemetal stays, but nothing that loads it is left.
        #expect(contents(system32(bottle, "winemetal.dll")) == nativeFake("DXMT x64 winemetal.dll"))
    }

    /// The game's entry still prefers the native trio, which is now DXVK's d3d11.
    private func expectGameEntryPrefersNative(_ recorder: ScopeRecorder) {
        let entry = recorder.overrides(for: .program(game))
        #expect(entry?["d3d11"] == "n,b", "game d3d11")
        #expect(entry?["d3d10core"] == "n,b", "game d3d10core")
        #expect(entry?["dxgi"] == "n,b", "game dxgi")
        print("[repro] \(game) AppDefaults entry: \(entry ?? [:])")
        print("[repro] steam.exe entry: \(recorder.overrides(for: .program("steam.exe")) ?? [:])")
        print("[repro] bottle scope: \(recorder.overrides(for: .bottle) ?? [:])")
    }

    private func describeDXGI(_ bottle: Bottle) -> String {
        let dxgi = system32(bottle, "dxgi.dll")
        guard let data = contents(dxgi) else { return "absent" }
        let native = (try? Wine.isNativePE(dxgi)) == true
        return "\(data.count) bytes, \(native ? "native" : "builtin-marked")"
    }

    @Test("Recommended without GPTK: the game's DXMT plan ends up loading DXVK's d3d11")
    func recommendedDXMTPlanRunsOnDXVK() async throws {
        let bottle = try makeBottle(.recommended)
        let recorder = ScopeRecorder()

        try await prepareAppLaunch(bottle, recommendedBackend: .dxmt, builtinD3D12IsD3DMetal: false, recorder: recorder)

        expectDXVKReplacedDXMT(bottle)
        expectGameEntryPrefersNative(recorder)
        print("[repro] system32 dxgi.dll: \(describeDXGI(bottle))")
    }

    @Test("An explicit DXMT bottle: the game's DXMT plan ends up loading DXVK's d3d11")
    func explicitDXMTBottleRunsOnDXVK() async throws {
        let bottle = try makeBottle(.dxmt)
        let recorder = ScopeRecorder()

        try await prepareAppLaunch(
            bottle,
            recommendedBackend: .d3dMetal,
            builtinD3D12IsD3DMetal: true,
            recorder: recorder
        )

        expectDXVKReplacedDXMT(bottle)
        expectGameEntryPrefersNative(recorder)
        print("[repro] system32 dxgi.dll: \(describeDXGI(bottle))")
    }

    @Test("A GameDB DXMT plan (Solarpunk, Trine 4) over a D3DMetal bottle ends up loading DXVK's d3d11")
    func gameDBDXMTPlanOverD3DMetalRunsOnDXVK() async throws {
        let bottle = try makeBottle(.recommended)
        let recorder = ScopeRecorder()
        var plan = ProgramOverrides()
        plan.graphicsBackend = .dxmt

        try await prepareAppLaunch(
            bottle, plan: plan, recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: true, recorder: recorder
        )

        expectDXVKReplacedDXMT(bottle)
        expectGameEntryPrefersNative(recorder)
        print("[repro] system32 dxgi.dll: \(describeDXGI(bottle))")
    }

    @Test("A direct DXMT launch of the game keeps DXMT's trio (control)")
    func directDXMTLaunchKeepsDXMT() async throws {
        let bottle = try makeBottle(.dxmt)
        let recorder = ScopeRecorder()
        let gameURL = bottle.url.appending(path: "drive_c/Games/\(game)")
        try FileManager.default.createDirectory(
            at: gameURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("MZ".utf8).write(to: gameURL)

        _ = try await Wine.prepareProgramLaunch(
            at: gameURL, bottle: bottle, recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: true,
            overrideWriter: recorder.writer, importer: recorder.importer,
            dxvkFolder: makeDXVKPayload(), dxmtFolder: makeDXMTPayload()
        )

        for dll in trio {
            #expect(contents(system32(bottle, dll)) == nativeFake("DXMT x64 \(dll)"), "system32 \(dll) is DXMT's")
        }
    }

    @Test("Contrast, D3DMetal plan: DXVK's files land too, but the game's entry names no translation DLL")
    func d3dMetalPlanIsUnaffected() async throws {
        let bottle = try makeBottle(.recommended)
        let recorder = ScopeRecorder()

        try await prepareAppLaunch(
            bottle, recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: true, recorder: recorder
        )

        let entry = recorder.overrides(for: .program(game))
        #expect(entry != nil, "the game gets an entry")
        for dll in ["dxgi", "d3d10core", "d3d11", "d3d12"] {
            #expect(entry?[dll] == nil, "game \(dll)")
        }
        let bottleScope = recorder.overrides(for: .bottle)
        for dll in ["dxgi", "d3d10core", "d3d11"] {
            #expect(bottleScope?[dll] == nil, "bottle \(dll)")
        }
        // No DXMT copy ran, and DXVK's copy only replaces files that already exist,
        // so a fresh prefix gets no d3d11 at all; Wine's default (builtin) order applies.
        #expect(contents(system32(bottle, "d3d11.dll")) == nil)
        print("[repro d3dmetal] \(game) entry: \(entry ?? [:])")
    }

    @Test("Characterization: a plain Steam client start in an explicit DXMT bottle deploys DXMT only")
    func explicitDXMTClientStartKeepsDXMT() async throws {
        let bottle = try makeBottle(.dxmt)
        let recorder = ScopeRecorder()

        _ = try await Wine.prepareProgramLaunch(
            at: steam(in: bottle), args: ["-silent"], bottle: bottle,
            recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: true,
            overrideWriter: recorder.writer, importer: recorder.importer,
            dxvkFolder: makeDXVKPayload(), dxmtFolder: makeDXMTPayload()
        )

        // An explicit backend is not steered, and no descendant plan forces DXVK,
        // so Steam's own n,b entry loads DXMT's trio here.
        for dll in trio {
            #expect(contents(system32(bottle, dll)) == nativeFake("DXMT x64 \(dll)"), "system32 \(dll) is DXMT's")
        }
        print("[repro client] steam.exe entry: \(recorder.overrides(for: .program("steam.exe")) ?? [:])")
    }
}
