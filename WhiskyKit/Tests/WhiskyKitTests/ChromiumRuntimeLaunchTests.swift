//
//  ChromiumRuntimeLaunchTests.swift
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

/// What a launch writes for an Electron app found by its files (#372): the
/// same as for a front end from the table, DXVK's set in its own entry under
/// Recommended while the bottle keeps the games' backend.
@Suite("Chromium runtime launches")
@MainActor
final class ChromiumRuntimeLaunchTests {
    let tempRoot: URL
    let bottleURL: URL
    let dxvkFolder: URL
    let appFolder: URL

    init() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "chromium_runtime_launch_\(UUID().uuidString)")
        bottleURL = tempRoot.appending(path: "Bottle")
        dxvkFolder = tempRoot.appending(path: "DXVK")
        let driveC = bottleURL.appending(path: "drive_c")
        appFolder = driveC.appending(path: "Program Files/Chat")
        try touch(["windows/system32/d3d11.dll", "windows/syswow64/d3d11.dll"], in: driveC)
        try touch(["resources/app.asar", "icudtl.dat", "v8_context_snapshot.bin", "ffmpeg.dll"], in: appFolder)
        try ChromiumRuntimeDetectorTests.electron45.write(to: appFolder.appending(path: "Chat.exe"))
        try ChromiumRuntimeDetectorTests.uninstaller.write(to: appFolder.appending(path: "Uninstall Chat.exe"))
        for arch in ["x64", "x32"] {
            let folder = dxvkFolder.appending(path: arch)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("DXVK".utf8).write(to: folder.appending(path: "d3d11.dll"))
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func touch(_ paths: [String], in base: URL) throws {
        for relative in paths {
            let url = base.appending(path: relative)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("MZ".utf8).write(to: url)
        }
    }

    func makeBottle(_ backend: GraphicsBackend = .recommended) -> Bottle {
        let bottle = Bottle(bottleUrl: bottleURL)
        bottle.settings.graphicsBackend = backend
        return bottle
    }

    var dxvkDeployed: Bool {
        let dll = bottleURL.appending(path: "drive_c/windows/system32/d3d11.dll")
        return (try? Data(contentsOf: dll)) == Data("DXVK".utf8)
    }

    func prepare(
        _ name: String, in bottle: Bottle, programOverrides: ProgramOverrides? = nil, recorder: ScopeRecorder
    ) async throws {
        _ = try await Wine.prepareProgramLaunch(
            at: appFolder.appending(path: name), bottle: bottle, programOverrides: programOverrides,
            recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: true,
            overrideWriter: recorder.writer, importer: recorder.importer, dxvkFolder: dxvkFolder
        )
    }

    @Test("Launched on Recommended, an Electron app gets DXVK in its own entry and the bottle keeps D3DMetal")
    func electronAppIsSteered() async throws {
        let bottle = makeBottle()
        let recorder = ScopeRecorder()

        try await prepare("Chat.exe", in: bottle, recorder: recorder)

        let entry = recorder.overrides(for: .program("Chat.exe"))
        #expect(entry?["d3d11"] == "n,b")
        #expect(entry?["dxgi"] == "n,b")
        #expect(recorder.overrides(for: .bottle)?["d3d11"] != "n,b")
        #expect(dxvkDeployed)
    }

    @Test("Its uninstaller keeps the bottle's backend")
    func uninstallerIsNotSteered() async throws {
        let bottle = makeBottle()
        let recorder = ScopeRecorder()

        try await prepare("Uninstall Chat.exe", in: bottle, recorder: recorder)

        #expect(recorder.overrides(for: .program("Uninstall Chat.exe"))?["d3d11"] != "n,b")
        #expect(!dxvkDeployed)
    }

    @Test("An explicit backend on the app, or on the bottle, is not steered")
    func explicitChoicesWin() async throws {
        var overrides = ProgramOverrides()
        overrides.graphicsBackend = .d3dMetal
        let programRecorder = ScopeRecorder()
        try await prepare("Chat.exe", in: makeBottle(), programOverrides: overrides, recorder: programRecorder)
        #expect(programRecorder.overrides(for: .program("Chat.exe"))?["d3d11"] != "n,b")

        let bottleRecorder = ScopeRecorder()
        try await prepare("Chat.exe", in: makeBottle(.d3dMetal), recorder: bottleRecorder)
        #expect(bottleRecorder.overrides(for: .program("Chat.exe"))?["d3d11"] != "n,b")
        #expect(!dxvkDeployed)
    }

    @Test("A program carries the steering it was scanned with, and falls back to its name")
    func programSteering() {
        let bottle = makeBottle()
        let chat = appFolder.appending(path: "Chat.exe")
        let scanned = Program(
            url: chat, bottle: bottle, peFile: nil, dxvkSteering: DXVKSteering.inspect(executable: chat)
        )
        #expect(scanned.dxvkSteering == .chromiumRuntime(kind: .electron, evidence: "resources/app.asar"))
        #expect(Program(url: chat, bottle: bottle, peFile: nil).dxvkSteering == nil, "name only, no read")

        let steam = bottleURL.appending(path: "drive_c/Program Files (x86)/Steam/steam.exe")
        #expect(Program(url: steam, bottle: bottle, peFile: nil).dxvkSteering == .launcher(.steam))
    }

    @Test("The preflight reports the Electron steering as the reason")
    func preflightReason() {
        let backends = PreflightCollector.resolvedBackends(
            bottle: .recommended, programOverride: nil, programURL: appFolder.appending(path: "Chat.exe"),
            recommended: { GraphicsBackendResolver.resolution(
                for: $0, runtimeInfo: nil, d3dMetalInstalled: true, dxmtRuntimeNative: false
            ) }
        )
        #expect(backends.effective == .dxvk)
        #expect(backends.bottle == .d3dMetal)
        #expect(backends.reason == .steered(.chromiumRuntime(kind: .electron, evidence: "resources/app.asar")))
    }
}
