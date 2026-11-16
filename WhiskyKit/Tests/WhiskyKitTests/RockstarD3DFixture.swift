//
//  RockstarD3DFixture.swift
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
@testable import WhiskyKit

extension RockstarD3DRuntime {
    /// A runtime and store that hold nothing, so a launch with the payload
    /// pinned as deployed can never swap: the tests that do not test the swap
    /// answer the same on a Mac with GPTK deployed as on one without.
    static func unavailable(in root: URL) -> RockstarD3DRuntime {
        RockstarD3DRuntime(
            libraryFolder: root.appending(path: "no runtime"), store: root.appending(path: "no store")
        )
    }
}

/// A bottle, a DXVK payload, and a runtime with the GPTK payload deployed,
/// for the tests of the Rockstar Games Launcher's swapped layout (#382).
@MainActor
final class RockstarD3DFixture {
    let root: URL
    let library: URL
    let store: URL
    let dxvk: URL
    let bottle: Bottle

    /// The engine the runtime and the store's originals are stamped for.
    static let engine = (major: 4, minor: 8, patch: 3)

    init(prefix: String, steam: Bool = true) throws {
        root = FileManager.default.temporaryDirectory.appending(path: "\(prefix)_\(UUID().uuidString)")
        library = root.appending(path: "Libraries")
        store = root.appending(path: "D3DMetal")
        dxvk = root.appending(path: "DXVK")
        let bottleURL = root.appending(path: "Bottle")
        for dir in ["drive_c/windows/system32", "drive_c/windows/syswow64", "drive_c/Program Files"] {
            try FileManager.default.createDirectory(
                at: bottleURL.appending(path: dir), withIntermediateDirectories: true
            )
        }
        bottle = Bottle(bottleUrl: bottleURL)
        try makeDXVK(version: "")
        try makeRuntime()
        try makePrefix()
        if steam {
            try makeSteam()
        }
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }

    var runtime: RockstarD3DRuntime {
        RockstarD3DRuntime(libraryFolder: library, store: store)
    }

    var driveC: URL {
        bottle.url.appending(path: "drive_c")
    }

    func system32(_ dll: String) -> URL {
        driveC.appending(path: "windows/system32").appending(path: dll)
    }

    func syswow64(_ dll: String) -> URL {
        driveC.appending(path: "windows/syswow64").appending(path: dll)
    }

    // MARK: - Payloads

    /// A native DXVK fake for `arch` and `dll`, tagged with `version`.
    static func dxvkBytes(_ arch: String, _ dll: String, version: String = "") -> Data {
        DXMTGameFolderFixture.nativeFake("DXVK\(version) \(arch) \(dll)")
    }

    /// DXVK-macOS ships `d3d11`, `d3d10core` and `d3d9`, never `dxgi`.
    func makeDXVK(version: String) throws {
        for arch in ["x64", "x32"] {
            let folder = dxvk.appending(path: arch)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for dll in ["d3d11.dll", "d3d10core.dll", "d3d9.dll"] {
                try Self.dxvkBytes(arch, dll, version: version).write(to: folder.appending(path: dll))
            }
        }
    }

    /// Wine's own builtin of `dll`: marked, importing wined3d, tagged.
    static func wineBytes(_ dll: String, tag: String = "") -> Data {
        var data = fakePE(builtin: true)
        data.append(wined3dImport)
        data.append(Data("wine \(dll)\(tag)".utf8))
        return data
    }

    /// A runtime with the payload deployed: Apple's forwarders in the
    /// `d3d11` and `dxgi` slots, Wine's own in the store's `originals/`,
    /// stamped for ``engine``.
    func makeRuntime(originalsTag: String = "") throws {
        let wineLib = library.appending(path: "Wine/lib")
        let peDir = wineLib.appending(path: "wine/x86_64-windows")
        for dir in [peDir, wineLib.appending(path: "wine/x86_64-unix"), wineLib.appending(path: "external")] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try Data("bridge".utf8).write(to: wineLib.appending(path: "wine/x86_64-unix/dxgi.so"))
        try Data("dylib".utf8).write(to: wineLib.appending(path: "external/libd3dshared.dylib"))
        for dll in ["d3d11.dll", "dxgi.dll"] {
            var forwarder = fakePE(builtin: true)
            forwarder.append(Data("apple \(dll)".utf8))
            try forwarder.write(to: peDir.appending(path: dll))
        }
        try Self.wineBytes("d3d10core.dll").write(to: peDir.appending(path: "d3d10core.dll"))
        try writeRuntimeVersion(at: library, Self.engine.major, Self.engine.minor, Self.engine.patch)
        try writeOriginals(tag: originalsTag, stamp: "\(Self.engine.major).\(Self.engine.minor).\(Self.engine.patch)")
    }

    /// Writes Wine's `d3d11` and `dxgi` into the store's `originals/`, stamped `stamp`.
    func writeOriginals(tag: String, stamp: String) throws {
        let originals = store.appending(path: "originals")
        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
        for dll in ["d3d11.dll", "dxgi.dll"] {
            try Self.wineBytes(dll, tag: tag).write(to: originals.appending(path: dll))
        }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        try encoder.encode(GPTKOriginalsRecord(runtimeVersion: stamp))
            .write(to: GPTKImporter.originalsRecordURL(inStore: store))
    }

    var d3d11Source: URL {
        store.appending(path: "originals/d3d11.dll")
    }

    var dxgiSource: URL {
        store.appending(path: "originals/dxgi.dll")
    }

    /// The prefix's Wine placeholders, which DXVK's files go over.
    private func makePrefix() throws {
        for dll in ["d3d11.dll", "dxgi.dll", "d3d10core.dll", "d3d9.dll"] {
            try fakePE(builtin: true).write(to: system32(dll))
            try fakePE(builtin: true).write(to: syswow64(dll))
        }
    }

    // MARK: - Steam

    var steamRoot: URL {
        driveC.appending(path: "Program Files (x86)/Steam")
    }

    var steamExe: URL {
        steamRoot.appending(path: "steam.exe")
    }

    static let steamKey = "Program Files (x86)/Steam"

    /// Steam with its 64-bit Chromium folders, the 32-bit `cef.win7`, and the overlay.
    private func makeSteam() throws {
        try write(PEBuilder.createMinimalPE32(), to: steamExe)
        for (folder, image) in [
            ("cef.win64", PEBuilder.createMinimalPE32Plus()),
            ("cef.win7x64", PEBuilder.createMinimalPE32Plus()),
            ("cef.win7", PEBuilder.createMinimalPE32())
        ] {
            try write(image, to: steamRoot.appending(path: "bin/cef/\(folder)/steamwebhelper.exe"))
        }
        try write(PEBuilder.createMinimalPE32Plus(), to: steamRoot.appending(path: "gameoverlayui64.exe"))
    }

    /// Lists a game in Steam's library under `appId`, with an executable.
    @discardableResult
    func addGame(appId: Int, name: String, installDir: String, exe: String = "Game.exe") throws -> URL {
        let steamApps = steamRoot.appending(path: "steamapps")
        let manifest = """
        "AppState"
        {
            "appid"        "\(appId)"
            "name"        "\(name)"
            "installdir"        "\(installDir)"
            "StateFlags"        "4"
        }
        """
        try FileManager.default.createDirectory(at: steamApps, withIntermediateDirectories: true)
        try manifest.write(
            to: steamApps.appending(path: "appmanifest_\(appId).acf"), atomically: true, encoding: .utf8
        )
        let url = steamApps.appending(path: "common").appending(path: installDir).appending(path: exe)
        try write(PEBuilder.createMinimalPE32Plus(), to: url)
        return url
    }

    /// Persists a per-program graphics backend for `executable`.
    func setBackend(_ backend: GraphicsBackend, for executable: URL) throws {
        let settingsURL = Program.settingsLocations(
            for: executable, bottleURL: bottle.url, legacyName: executable.lastPathComponent
        ).identity
        var settings = ProgramSettings()
        var overrides = ProgramOverrides()
        overrides.graphicsBackend = backend
        settings.overrides = overrides
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try settings.encode(to: settingsURL)
    }

    // MARK: - Rockstar

    static let socialClubKey = "Program Files/Rockstar Games/Social Club"

    var socialClub: URL {
        driveC.appending(path: Self.socialClubKey)
    }

    var rockstarLauncher: URL {
        driveC.appending(path: "Program Files/Rockstar Games/Launcher/Launcher.exe")
    }

    /// Installs Rockstar's launcher, and Social Club with it unless asked not to.
    func installRockstar(socialClub withSocialClub: Bool = true) throws {
        try write(PEBuilder.createMinimalPE32Plus(), to: rockstarLauncher)
        if withSocialClub {
            try write(PEBuilder.createMinimalPE32Plus(), to: socialClub.appending(path: "SocialClubHelper.exe"))
        }
    }

    // MARK: - Launches

    func launch(
        _ url: URL, launcher: LauncherType? = nil, descendants: [LauncherType] = [],
        payloadDeployed: Bool = true, runtime: RockstarD3DRuntime? = nil
    ) -> RockstarD3DLaunch {
        RockstarD3DLaunch(
            url: url, launcher: launcher ?? LauncherType.detect(from: url), descendantLaunchers: descendants,
            recommendedBackend: .d3dMetal, payloadDeployed: payloadDeployed, runtime: runtime ?? self.runtime
        )
    }

    /// A Steam start, deploying DXVK as `prepareProgramLaunch` does for it.
    @discardableResult
    func startSteam(
        descendants: [LauncherType] = [], payloadDeployed: Bool = true, ops: RockstarD3DFileOps = .live
    ) throws -> RockstarD3DLayout? {
        try Wine.deployDXVK(
            bottle: bottle, from: dxvk,
            rockstar: launch(steamExe, descendants: descendants, payloadDeployed: payloadDeployed), ops: ops
        )
    }

    // MARK: - Files

    func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    static func contents(_ url: URL) -> Data? {
        try? Data(contentsOf: url)
    }

    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// The inode and modification date of `url`, to tell a file left alone from one written again.
    static func identity(_ url: URL) -> [String]? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        else { return nil }
        return ["\(attributes[.systemFileNumber] ?? "")", "\(attributes[.modificationDate] ?? "")"]
    }

    /// Whether `folder` holds DXVK's x64 `d3d11.dll` and `d3d10core.dll`.
    static func holdsDXVKCopies(_ folder: URL, version: String = "") -> Bool {
        Wine.rockstarD3DCopyDLLs.allSatisfy {
            contents(folder.appending(path: $0)) == dxvkBytes("x64", $0, version: version)
        }
    }

    /// Whether `folder` holds neither copy.
    static func holdsNoCopies(_ folder: URL) -> Bool {
        Wine.rockstarD3DCopyDLLs.allSatisfy { !exists(folder.appending(path: $0)) }
    }

    /// The copy folders a fresh swap in this fixture serves, relative to `drive_c`.
    static let steamCopyKeys = [
        "\(steamKey)/bin/cef/cef.win64", "\(steamKey)/bin/cef/cef.win7x64", steamKey
    ]

    var record: RockstarD3DLayoutRecord? {
        RockstarD3DLayoutRecord.load(from: bottle.url)
    }
}

/// File operations that log each step by name and forward to the real ones,
/// optionally failing one, or stopping dead at one as a crash would. The swap
/// runs on the main actor, so nothing touches the log concurrently.
final class RockstarOpsRecorder: @unchecked Sendable {
    private(set) var log: [String] = []
    /// Throws at the step whose log entry starts with this, once reached.
    var failAt: String?
    /// Throws at the step whose log entry starts with this, and skips every
    /// step after it, as if the process died there.
    var crashAt: String?
    private(set) var crashed = false
    /// Leaves `dxgi.dll` alone, as a deploy that could not place it does.
    var skipDXGI = false
    /// Whether `system32\d3d11.dll` was already Wine's when `dxgi` was reconciled.
    private(set) var d3d11StrippedAtDXGI: Bool?

    struct Injected: Error, LocalizedError {
        var errorDescription: String? { "injected" }
    }

    /// Logs a step, and answers whether to perform it.
    private func step(_ name: String) throws -> Bool {
        guard !crashed else {
            log.append("skipped \(name)")
            return false
        }
        log.append(name)
        if let crashAt, name.hasPrefix(crashAt) {
            crashed = true
            throw Injected()
        }
        if let failAt, name.hasPrefix(failAt) {
            throw Injected()
        }
        return true
    }

    var ops: RockstarD3DFileOps {
        let live = RockstarD3DFileOps.live
        var ops = RockstarD3DFileOps()
        ops.installCopy = { destination, source in
            if try self.step("installCopy \(destination.deletingLastPathComponent().lastPathComponent)") {
                try live.installCopy(destination, source)
            }
        }
        ops.removeCopy = { url in
            if try self.step("removeCopy \(url.deletingLastPathComponent().lastPathComponent)") {
                try live.removeCopy(url)
            }
        }
        ops.createFolder = { url in
            if try self.step("createFolder \(url.lastPathComponent)") {
                try live.createFolder(url)
            }
        }
        ops.removeFolderIfEmpty = { url in
            if (try? self.step("removeFolderIfEmpty \(url.lastPathComponent)")) == true {
                live.removeFolderIfEmpty(url)
            }
        }
        ops.enableDXVK = { bottle, folder, source, reconcileDXGI in
            guard try self.step(source == nil ? "enableDXVK(nil)" : "enableDXVK(source)") else { return }
            try Wine.enableDXVK(bottle: bottle, from: folder, system32D3D11Source: source) { prefix in
                self.log.append("dxgi")
                let d3d11 = prefix.appending(path: "drive_c/windows/system32/d3d11.dll")
                self.d3d11StrippedAtDXGI = source.map { Wine.isStrippedCopy(d3d11, of: $0) }
                if !self.skipDXGI {
                    reconcileDXGI(prefix)
                }
            }
        }
        ops.saveRecord = { record, url in
            if try self.step(record.system32D3D11 == nil ? "saveRecord(interim)" : "saveRecord(final)") {
                try live.saveRecord(record, url)
            }
        }
        ops.removeRecord = { url in
            if try self.step("removeRecord") {
                try live.removeRecord(url)
            }
        }
        return ops
    }
}
