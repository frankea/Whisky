//
//  ChromiumRuntimeDetectorTests.swift
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

/// The Electron and NW.js rule (#372). The fixtures copy the shapes measured
/// on the RSI Launcher 2.19.2 (Electron 45): `ffmpeg.dll` is only a delay
/// import there, next to `d3d11.dll`, `d3d12.dll` and `dxgi.dll`.
@Suite("Chromium runtime detection")
final class ChromiumRuntimeDetectorTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "chromium_runtime_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    /// Electron 45's import shape: graphics and `ffmpeg.dll` delay-loaded only.
    static let electron45 = PEImportFixture(
        normalImports: ["CRYPT32.dll", "DWrite.dll", "KERNEL32.dll", "VERSION.dll", "WINMM.dll", "ntdll.dll"],
        delayImports: ["ffmpeg.dll", "ADVAPI32.dll", "d3d11.dll", "d3d12.dll", "dxgi.dll", "USER32.dll"]
    )

    /// An uninstaller beside it, as electron-builder's NSIS layout has.
    static let uninstaller = PEImportFixture(
        pe32Plus: false, normalImports: ["ADVAPI32.dll", "KERNEL32.dll", "SHELL32.dll", "USER32.dll"]
    )

    func touch(_ paths: [String], in folder: URL) throws {
        for relative in paths {
            let url = folder.appending(path: relative)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data("x".utf8).write(to: url)
        }
    }

    /// An electron-builder install: the app's code in `resources/app.asar`,
    /// Chromium's data files beside the executable.
    func electronFolder(_ name: String = "Electron App") throws -> URL {
        let folder = root.appending(path: "drive_c/Program Files/\(name)")
        try touch(
            [
                "resources/app.asar", "icudtl.dat", "v8_context_snapshot.bin", "snapshot_blob.bin", "ffmpeg.dll",
                "vulkan-1.dll", "d3dcompiler_47.dll", "resources.pak"
            ],
            in: folder
        )
        return folder
    }

    func classify(_ url: URL) -> DXVKSteering? {
        ChromiumRuntimeDetector.classify(executable: url)
    }

    // MARK: - Electron

    @Test("Electron 45, ffmpeg.dll delay-loaded beside delay-loaded Direct3D, is an Electron app")
    func electron45Shape() throws {
        let exe = try electronFolder().appending(path: "Electron App.exe")
        try Self.electron45.write(to: exe)
        #expect(classify(exe) == .chromiumRuntime(kind: .electron, evidence: "resources/app.asar"))
        #expect(DXVKSteering.inspect(executable: exe) == .chromiumRuntime(
            kind: .electron,
            evidence: "resources/app.asar"
        ))
    }

    @Test("An older Electron importing ffmpeg.dll normally, as a PE32 image, matches too")
    func normalFFmpegImport() throws {
        let exe = try electronFolder().appending(path: "Old App.exe")
        try PEImportFixture(pe32Plus: false, normalImports: ["ffmpeg.dll", "KERNEL32.dll"]).write(to: exe)
        #expect(classify(exe) == .chromiumRuntime(kind: .electron, evidence: "resources/app.asar"))
    }

    @Test("An unpacked app folder counts as the app's code")
    func unpackedApp() throws {
        let folder = root.appending(path: "Unpacked")
        try touch(["resources/app/package.json", "icudtl.dat", "snapshot_blob.bin"], in: folder)
        let exe = folder.appending(path: "Unpacked.exe")
        try Self.electron45.write(to: exe)
        #expect(classify(exe) == .chromiumRuntime(kind: .electron, evidence: "resources/app/package.json"))
    }

    @Test("The uninstaller beside an Electron app is not matched")
    func uninstallerSibling() throws {
        let exe = try electronFolder().appending(path: "Uninstall Electron App.exe")
        try Self.uninstaller.write(to: exe)
        #expect(classify(exe) == nil)
    }

    @Test("An executable importing Direct3D normally is not matched, whatever its folder holds")
    func normalGraphicsImportVetoes() throws {
        let folder = try electronFolder()
        for graphics in ["d3d11.dll", "D3D9.dll", "dxgi.dll", "vulkan-1.dll", "opengl32.dll", "d3d12.dll"] {
            let exe = folder.appending(path: "Game \(graphics).exe")
            try PEImportFixture(normalImports: ["KERNEL32.dll", graphics], delayImports: ["ffmpeg.dll"]).write(to: exe)
            #expect(classify(exe) == nil, "\(graphics)")
        }
    }

    @Test("Without Chromium's data files beside it, nothing is matched")
    func missingMarkers() throws {
        let folder = root.appending(path: "No ICU")
        try touch(["resources/app.asar", "v8_context_snapshot.bin"], in: folder)
        let exe = folder.appending(path: "App.exe")
        try Self.electron45.write(to: exe)
        #expect(classify(exe) == nil)
    }

    @Test("A folder with more than 2,000 entries is not read")
    func overBudgetFolder() throws {
        let folder = try electronFolder("Downloads")
        let exe = folder.appending(path: "App.exe")
        try Self.electron45.write(to: exe)
        try touch((0 ..< ChromiumRuntimeDetector.maxFolderEntries).map { "file\($0).txt" }, in: folder)
        #expect(classify(exe) == nil)
    }

    @Test("Nothing under drive_c/windows is matched")
    func windowsFolder() throws {
        let folder = root.appending(path: "drive_c/windows/system32")
        try touch(["resources/app.asar", "icudtl.dat", "v8_context_snapshot.bin"], in: folder)
        let exe = folder.appending(path: "Explorer.exe")
        try Self.electron45.write(to: exe)
        #expect(ChromiumRuntimeDetector.detect(executable: exe) == nil)
        #expect(ChromiumRuntimeDetector.isUnderWindowsFolder(exe))
        #expect(!ChromiumRuntimeDetector
            .isUnderWindowsFolder(root.appending(path: "drive_c/Program Files/windows/a.exe")))
    }

    // MARK: - Precedence

    @Test("A known launcher keeps its launcher path, and the table keeps its row")
    func launcherAndTablePrecedence() throws {
        let folder = try electronFolder("RSI Launcher")
        let launcher = folder.appending(path: "RSI Launcher.exe")
        let frontEnd = folder.appending(path: "3DMark.exe")
        try Self.electron45.write(to: launcher)
        try Self.electron45.write(to: frontEnd)
        #expect(ChromiumRuntimeDetector.detect(executable: launcher) == nil)
        #expect(DXVKSteering.inspect(executable: launcher) == .launcher(.rsiLauncher))
        #expect(DXVKSteering.inspect(executable: frontEnd) == .chromiumFrontEnd(.threeDMark))
        #expect(DXVKSteering.detect(executable: folder.appending(path: "Electron App.exe")) == nil, "name only")
    }

    // MARK: - NW.js

    @Test("An NW.js game, nw.dll and icudtl.dat beside it, is an NW.js app")
    func nwjsGame() throws {
        let folder = root.appending(path: "RPG")
        try touch(["nw.dll", "nw_elf.dll", "icudtl.dat", "package.nw"], in: folder)
        for (name, imports) in [("Game.exe", ["nw.dll"]), ("Nw.exe", ["nw_elf.dll"])] {
            let exe = folder.appending(path: name)
            try PEImportFixture(normalImports: imports + ["KERNEL32.dll"]).write(to: exe)
            #expect(classify(exe) == .chromiumRuntime(kind: .nwjs, evidence: "nw.dll"), "\(name)")
        }
        let notNW = folder.appending(path: "Tool.exe")
        try PEImportFixture(normalImports: ["KERNEL32.dll"]).write(to: notNW)
        #expect(classify(notNW) == nil)
    }

    // MARK: - Squirrel

    @Test("A Squirrel stub is classified by the app it starts, which runs under its name")
    func squirrelStub() throws {
        let install = root.appending(path: "drive_c/users/crossover/AppData/Local/Chat")
        try touch(["Update.exe"], in: install)
        for version in ["app-1.9.0", "app-1.10.2"] {
            let app = install.appending(path: version)
            try touch(["resources/app.asar", "icudtl.dat", "v8_context_snapshot.bin"], in: app)
            try Self.electron45.write(to: app.appending(path: "Chat.exe"))
        }
        let stub = install.appending(path: "Chat.exe")
        try PEImportFixture(normalImports: ["KERNEL32.dll", "SHELL32.dll"]).write(to: stub)

        #expect(classify(stub) == .chromiumRuntime(kind: .electron, evidence: "app-1.10.2/resources/app.asar"))
        #expect(classify(install.appending(path: "app-1.9.0/Chat.exe")) != nil)
        #expect(classify(install.appending(path: "Update.exe")) == nil)
    }

    // MARK: - Cache

    @Test("The cache answers until the executable changes")
    func cacheInvalidatesOnModification() throws {
        let folder = try electronFolder("Cached")
        let exe = folder.appending(path: "Cached.exe")
        let matching = PEImportFixture(delayImports: ["ffmpeg.dll"])
        // The same size, with no ffmpeg.dll.
        let other = PEImportFixture(delayImports: ["fxmpeg.dll"])
        #expect(matching.data().count == other.data().count)

        try matching.write(to: exe)
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let folderStamp = Date(timeIntervalSince1970: 1_700_000_100)
        func setStamps(_ date: Date) throws {
            try FileManager.default.setAttributes(
                [.modificationDate: date],
                ofItemAtPath: exe.path(percentEncoded: false)
            )
            try FileManager.default.setAttributes(
                [.modificationDate: folderStamp], ofItemAtPath: folder.path(percentEncoded: false)
            )
        }
        try setStamps(stamp)
        #expect(ChromiumRuntimeDetector.detect(executable: exe)?.displayName == "Electron")

        // Rewritten in place with the same size and dates: the cache answers.
        try other.data().write(to: exe)
        try setStamps(stamp)
        #expect(ChromiumRuntimeDetector.detect(executable: exe)?.displayName == "Electron")

        // A new modification date: classified again.
        try setStamps(stamp.addingTimeInterval(60))
        #expect(ChromiumRuntimeDetector.detect(executable: exe) == nil)
    }

    @Test("A miss is looked at again when the app's code lands in a resources folder that already existed")
    func appCodeArrivingLater() throws {
        let folder = root.appending(path: "drive_c/Program Files/Extracting")
        try touch(["icudtl.dat", "v8_context_snapshot.bin"], in: folder)
        try FileManager.default.createDirectory(
            at: folder.appending(path: "resources"), withIntermediateDirectories: true
        )
        let exe = folder.appending(path: "Late.exe")
        try Self.electron45.write(to: exe)
        let folderStamp = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes(
            [.modificationDate: folderStamp], ofItemAtPath: folder.path(percentEncoded: false)
        )

        #expect(ChromiumRuntimeDetector.detect(executable: exe) == nil)
        #expect(ChromiumRuntimeDetector.evaluate(executable: exe) == .init(steering: nil, isFinal: false))

        // The installer writes the archive last; the executable's folder keeps its date.
        try touch(["resources/app.asar"], in: folder)
        try FileManager.default.setAttributes(
            [.modificationDate: folderStamp], ofItemAtPath: folder.path(percentEncoded: false)
        )
        #expect(ChromiumRuntimeDetector.detect(executable: exe) == .chromiumRuntime(
            kind: .electron, evidence: "resources/app.asar"
        ))
    }

    @Test("A miss is cached when every file that decides it sits in the executable's folder")
    func finalMisses() throws {
        let plain = root.appending(path: "Plain")
        try touch(["data.pak"], in: plain)
        let tool = plain.appending(path: "Tool.exe")
        try Self.uninstaller.write(to: tool)
        #expect(ChromiumRuntimeDetector.evaluate(executable: tool) == .init(steering: nil, isFinal: true))

        let squirrel = root.appending(path: "Squirrel")
        try touch(["Update.exe"], in: squirrel)
        let stub = squirrel.appending(path: "Chat.exe")
        try Self.uninstaller.write(to: stub)
        #expect(ChromiumRuntimeDetector.evaluate(executable: stub).isFinal == false, "the app folder can still land")
    }

    // MARK: - CEF suggestion

    @Test("CEF is suggested only when the executable imports libcef.dll and no graphics DLL")
    func cefSuggestion() throws {
        let folder = root.appending(path: "CEF Host")
        try touch(["libcef.dll"], in: folder)
        let host = folder.appending(path: "Host.exe")
        try PEImportFixture(normalImports: ["libcef.dll", "KERNEL32.dll"], delayImports: ["d3d11.dll"]).write(to: host)
        let delayHost = folder.appending(path: "DelayHost.exe")
        try PEImportFixture(normalImports: ["KERNEL32.dll"], delayImports: ["libcef.dll"]).write(to: delayHost)
        let game = folder.appending(path: "Game.exe")
        try PEImportFixture(normalImports: ["libcef.dll", "d3d11.dll"]).write(to: game)
        let unrelated = folder.appending(path: "Tool.exe")
        try PEImportFixture(normalImports: ["KERNEL32.dll"]).write(to: unrelated)

        #expect(ChromiumRuntimeDetector.suggestsCEF(for: host))
        #expect(ChromiumRuntimeDetector.suggestsCEF(for: delayHost))
        #expect(!ChromiumRuntimeDetector.suggestsCEF(for: game), "a game that draws with Direct3D itself")
        #expect(!ChromiumRuntimeDetector.suggestsCEF(for: unrelated), "libcef.dll beside it, not imported")

        let elsewhere = root.appending(path: "No CEF/Host.exe")
        try PEImportFixture(normalImports: ["libcef.dll"]).write(to: elsewhere)
        #expect(!ChromiumRuntimeDetector.suggestsCEF(for: elsewhere), "no libcef.dll beside it")
    }

    // MARK: - Resolution

    @Test("A runtime match resolves to DXVK, with a rationale and its evidence in the reason")
    func resolution() {
        let steering = DXVKSteering.chromiumRuntime(kind: .electron, evidence: "resources/app.asar")
        let resolution = GraphicsBackendResolver.resolution(
            for: steering, runtimeInfo: nil, d3dMetalInstalled: true, dxmtRuntimeNative: false
        )
        #expect(resolution.backend == .dxvk)
        #expect(resolution.reason == .steered(steering))
        #expect(resolution.reason.exportName.contains("resources/app.asar"))
        #expect(steering.helperExecutables.isEmpty)
        for games in [GraphicsBackend.d3dMetal, .dxmt] {
            #expect(!resolution.rationale(gamesBackend: games).isEmpty)
        }
        let nwjs = DXVKSteering.chromiumRuntime(kind: .nwjs, evidence: "nw.dll")
        #expect(!BackendResolution(backend: .dxvk, reason: .steered(nwjs)).rationale(gamesBackend: .d3dMetal).isEmpty)
        #expect(nwjs.listedName(executable: URL(filePath: "/x/Game.exe")) == "Game")
        #expect(DXVKSteering.launcher(.steam).listedName(executable: URL(filePath: "/x/steam.exe")) == "Steam")
    }
}
