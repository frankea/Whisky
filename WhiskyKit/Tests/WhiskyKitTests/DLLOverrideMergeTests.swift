//
//  DLLOverrideMergeTests.swift
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

/// A program's own `WINEDLLOVERRIDES` used to be replaced by the composed
/// value whenever the bottle had any override (ellomehllo/Sangria).
@Suite("WINEDLLOVERRIDES merging")
@MainActor
struct DLLOverrideMergeTests {
    @Test("Wine's format parses, including several DLLs per mode and disabled ones")
    func parsesWineFormat() {
        let entries = DLLOverrideResolver.parse("d3d11,dxgi=n,b;xaudio2_7=b;winemenubuilder.exe=")
        #expect(entries == [
            DLLOverrideEntry(dllName: "d3d11", mode: .nativeThenBuiltin),
            DLLOverrideEntry(dllName: "dxgi", mode: .nativeThenBuiltin),
            DLLOverrideEntry(dllName: "xaudio2_7", mode: .builtin),
            DLLOverrideEntry(dllName: "winemenubuilder.exe", mode: .disabled)
        ])
    }

    @Test("Modes and names are matched without case, and spelled-out modes are read")
    func normalizesCase() {
        #expect(DLLOverrideResolver.parse("D3D11=N,B") == [DLLOverrideEntry(
            dllName: "d3d11",
            mode: .nativeThenBuiltin
        )])
        #expect(DLLOverrideResolver.parse("dinput8=native,builtin") == [
            DLLOverrideEntry(dllName: "dinput8", mode: .nativeThenBuiltin)
        ])
        #expect(DLLOverrideResolver.parse("dinput8=Builtin") == [DLLOverrideEntry(dllName: "dinput8", mode: .builtin)])
    }

    @Test("Whitespace is tolerated and entries without a DLL or an = are skipped, not fatal")
    func skipsMalformedEntries() {
        #expect(DLLOverrideResolver.parse(" d3d11 = b ") == [DLLOverrideEntry(dllName: "d3d11", mode: .builtin)])
        #expect(DLLOverrideResolver.parse("nonsense").isEmpty)
        #expect(DLLOverrideResolver.parse("=n").isEmpty)
        #expect(DLLOverrideResolver.parse("").isEmpty)
        #expect(DLLOverrideResolver.parse("bogus;d3d9=n") == [DLLOverrideEntry(dllName: "d3d9", mode: .native)])
    }

    @Test("A mode with no n or b disables the DLL, as in Wine", arguments: ["d", "disabled", "zzz", "", " "])
    func modeWithoutNativeOrBuiltinDisables(mode: String) {
        #expect(DLLOverrideResolver.parse("winemenubuilder.exe=\(mode)") == [
            DLLOverrideEntry(dllName: "winemenubuilder.exe", mode: .disabled)
        ])
    }

    @Test("Modes follow Wine's loader: unknown words are ignored and the first pair decides")
    func modesFollowWinesLoader() {
        #expect(DLLOverrideResolver.mode("n,b") == .nativeThenBuiltin)
        #expect(DLLOverrideResolver.mode("b,n") == .builtinThenNative)
        #expect(DLLOverrideResolver.mode("x,n") == .native)
        #expect(DLLOverrideResolver.mode("n,n") == .native)
        #expect(DLLOverrideResolver.mode("b,x,n,b") == .builtinThenNative)
        #expect(DLLOverrideResolver.mode("native builtin") == .nativeThenBuiltin)
    }

    @Test("A program's own disable reaches the composed value in a bottle with overrides")
    func programDisableSurvives() throws {
        let bottle = try makeBottle(.dxvk)
        let env = Wine.constructWineEnvironment(
            for: bottle, environment: ["WINEDLLOVERRIDES": "winemenubuilder.exe=d"], builtinD3D12IsD3DMetal: false
        )
        let overrides = Wine.parseDLLOverrides(env["WINEDLLOVERRIDES"] ?? "")
        #expect(overrides["winemenubuilder.exe"] == "")
        #expect(overrides["d3d11"] == "n,b")
    }

    @Test("A program's own WINEDLLOVERRIDES survives and beats the backend preset")
    func programValueBeatsPreset() throws {
        let bottle = try makeBottle(.dxmt)

        let preset = Wine.constructWineEnvironment(for: bottle, builtinD3D12IsD3DMetal: false)
        #expect(preset["WINEDLLOVERRIDES"]?.contains("d3d11=n,b") == true)

        let merged = Wine.constructWineEnvironment(
            for: bottle, environment: ["WINEDLLOVERRIDES": "D3D11=B;xaudio2_7,dinput8=n"],
            builtinD3D12IsD3DMetal: false
        )
        let overrides = Wine.parseDLLOverrides(merged["WINEDLLOVERRIDES"] ?? "")
        #expect(overrides["d3d11"] == "b")
        #expect(overrides["xaudio2_7"] == "n")
        #expect(overrides["dinput8"] == "n")
        #expect(overrides["winemetal"] == "b", "the rest of the DXMT preset is untouched")
    }

    @Test("A program's value beats its own backend override and its structured overrides")
    func programValueBeatsProgramOverrides() throws {
        let bottle = try makeBottle(.d3dMetal)
        var programOverrides = ProgramOverrides()
        programOverrides.graphicsBackend = .dxvk
        programOverrides.dllOverrides = [DLLOverrideEntry(dllName: "dinput8", mode: .builtin)]

        let env = Wine.constructWineEnvironment(
            for: bottle, environment: ["WINEDLLOVERRIDES": "dxgi=b;dinput8=n"],
            programOverrides: programOverrides, builtinD3D12IsD3DMetal: false
        )
        let overrides = Wine.parseDLLOverrides(env["WINEDLLOVERRIDES"] ?? "")
        #expect(overrides["dxgi"] == "b")
        #expect(overrides["dinput8"] == "n")
        #expect(overrides["d3d11"] == "n,b")
    }

    @Test("A GameDB profile's WINEDLLOVERRIDES does not outrank the bottle's custom overrides")
    func gameProfileValueIsNotMerged() throws {
        let bottle = try makeBottle(.d3dMetal)
        bottle.settings.dllOverrides = [DLLOverrideEntry(dllName: "dinput8", mode: .builtin)]

        let env = Wine.constructWineEnvironment(
            for: bottle, gameProfileEnvironment: ["WINEDLLOVERRIDES": "dinput8=n"], builtinD3D12IsD3DMetal: false
        )
        #expect(Wine.parseDLLOverrides(env["WINEDLLOVERRIDES"] ?? "")["dinput8"] == "b")
    }

    private func makeBottle(_ backend: GraphicsBackend) throws -> Bottle {
        let url = FileManager.default.temporaryDirectory.appending(path: "dll_merge_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let bottle = Bottle(bottleUrl: url, inFlight: false, isAvailable: true)
        bottle.settings.graphicsBackend = backend
        return bottle
    }
}
