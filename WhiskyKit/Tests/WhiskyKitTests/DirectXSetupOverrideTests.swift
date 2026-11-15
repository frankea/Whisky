//
//  DirectXSetupOverrideTests.swift
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

/// The DirectX June 2010 redistributable's setup exits -9 under Wine Mono
/// unless `mscoree` is disabled for it (furknataman/Kadeh).
@Suite("DirectX setup overrides")
@MainActor
final class DirectXSetupOverrideTests {
    private let tempRoot: URL

    init() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "dxsetup_overrides_\(UUID().uuidString)")
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
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("MZ".utf8).write(to: url)
        return url
    }

    private func launch(_ url: URL, in bottle: Bottle, recorder: ScopeRecorder) async throws {
        _ = try await Wine.prepareProgramLaunch(
            at: url, bottle: bottle, recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: false,
            overrideWriter: recorder.writer, importer: recorder.importer
        )
    }

    @Test("Every launch keeps mscoree away from DirectX's setup")
    func everyLaunchWritesTheSetupEntry() async throws {
        let bottle = try makeBottle(.d3dMetal)
        let game = try makeExecutable("Games/Some Game/Game.exe", in: bottle)
        let recorder = ScopeRecorder()

        try await launch(game, in: bottle, recorder: recorder)

        #expect(recorder.overrides(for: .program("DXSETUP.exe")) == ["mscoree": ""])
        #expect(recorder.overrides(for: .bottle)?["mscoree"] == nil, "the bottle's own .NET is left alone")
    }

    @Test("A direct launch of the setup keeps mscoree disabled, on top of its own set")
    func directLaunchKeepsTheOverride() async throws {
        let bottle = try makeBottle(.dxvk)
        // Lowercase, as some redistributable folders name it.
        let setup = try makeExecutable("Games/Some Game/_CommonRedist/DirectX/Jun2010/dxsetup.exe", in: bottle)
        let recorder = ScopeRecorder()

        try await launch(setup, in: bottle, recorder: recorder)

        // One entry, compared without case as Wine does, holding both.
        #expect(recorder.programScopes.filter { $0.lowercased() == "dxsetup.exe" }.count == 1)
        let entry = recorder.overrides(for: .program("DXSETUP.exe"))
        #expect(entry?["mscoree"] == "")
        #expect(entry?["dxgi"] == "n,b", "the launch's own set is kept")
    }

    @Test("A Steam game launch writes the setup's entry too")
    func steamGameLaunchWritesTheSetupEntry() async throws {
        let bottle = try makeBottle(.recommended)
        let steam = try makeExecutable("Program Files (x86)/Steam/steam.exe", in: bottle)
        let recorder = ScopeRecorder()

        _ = try await Wine.prepareProgramLaunch(
            at: steam, args: ["-applaunch", "1"], bottle: bottle, overridesApplyToDescendants: true,
            descendantExecutables: ["Game.exe"], recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: false,
            overrideWriter: recorder.writer, importer: recorder.importer
        )

        #expect(recorder.overrides(for: .program("DXSETUP.exe")) == ["mscoree": ""])
    }

    @Test("Only the setup itself carries its launch's own set")
    func overridesForTheSetupEntry() {
        let own = "d3d11=n,b;dxgi=n,b"
        let setup = URL(filePath: "/B/drive_c/DXSETUP.exe")
        let other = URL(filePath: "/B/drive_c/Game.exe")
        #expect(Wine.directXSetupOverrides(launching: setup, own: own) == "d3d11=n,b;dxgi=n,b;mscoree=")
        #expect(Wine.directXSetupOverrides(launching: other, own: own) == "mscoree=")
        #expect(Wine.directXSetupOverrides(launching: setup, own: nil) == "mscoree=")
    }
}
