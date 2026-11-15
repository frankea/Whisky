//
//  DXMTGameFolderFixture.swift
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
@testable import WhiskyKit

/// Bottles, payloads and game folders for the tests of DXMT copies beside a
/// game's executables.
struct DXMTGameFolderFixture {
    let root: URL

    /// DXMT's translation trio, the files a game folder gets.
    static let trio = ["d3d11.dll", "d3d10core.dll", "dxgi.dll"]

    /// Where the test game lives inside `drive_c`.
    static let gameFolder = "Program Files (x86)/Steam/steamapps/common/Game"

    init(prefix: String) throws {
        root = FileManager.default.temporaryDirectory.appending(path: "\(prefix)_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// Removes the fixture, making every folder writable first so a test that
    /// locked one cannot leave it behind.
    func cleanUp() {
        let fileManager = FileManager.default
        if let paths = fileManager.enumerator(atPath: root.path(percentEncoded: false)) {
            for case let path as String in paths {
                try? fileManager.setAttributes(
                    [.posixPermissions: 0o755], ofItemAtPath: root.appending(path: path).path(percentEncoded: false)
                )
            }
        }
        try? fileManager.removeItem(at: root)
    }

    /// A markerless (native) PE stub tagged with its origin after the 0x40 window.
    static func nativeFake(_ tag: String) -> Data {
        Data(count: 0x40) + Data(tag.utf8) + Data(count: 16)
    }

    static func contents(_ url: URL) -> Data? {
        try? Data(contentsOf: url)
    }

    @MainActor
    func makeBottle(_ backend: GraphicsBackend = .recommended) throws -> Bottle {
        let bottleURL = root.appending(path: "Bottle")
        try FileManager.default.createDirectory(
            at: bottleURL.appending(path: "drive_c/windows/system32"), withIntermediateDirectories: true
        )
        let bottle = Bottle(bottleUrl: bottleURL)
        bottle.settings.graphicsBackend = backend
        return bottle
    }

    @MainActor
    func steam(in bottle: Bottle) throws -> URL {
        let url = bottle.url.appending(path: "drive_c/Program Files (x86)/Steam/steam.exe")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("MZ".utf8).write(to: url)
        return url
    }

    /// A game executable with a real PE header of the given architecture,
    /// `padding` bytes larger than the minimal image.
    @MainActor
    func makeGame(
        in bottle: Bottle, folder: String = gameFolder, name: String = "Game.exe", arch: Architecture = .x64,
        padding: Int = 0
    ) throws -> URL {
        let url = bottle.url.appending(path: "drive_c").appending(path: folder).appending(path: name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let image = arch == .x32 ? PEBuilder.createMinimalPE32() : PEBuilder.createMinimalPE32Plus()
        try (image + Data(count: padding)).write(to: url)
        return url
    }

    /// Lists the test game in the bottle's Steam library under `appId`, with
    /// ``gameFolder`` as its install folder, so `SteamLibrary.enumerate` finds it.
    @MainActor
    func registerSteamGame(in bottle: Bottle, appId: Int) throws {
        let steamApps = bottle.url.appending(path: "drive_c/Program Files (x86)/Steam/steamapps")
        try FileManager.default.createDirectory(at: steamApps, withIntermediateDirectories: true)
        let manifest = """
        "AppState"
        {
            "appid"        "\(appId)"
            "name"        "Game"
            "installdir"        "Game"
            "StateFlags"        "4"
        }
        """
        try manifest.write(
            to: steamApps.appending(path: "appmanifest_\(appId).acf"), atomically: true, encoding: .utf8
        )
    }

    /// DXVK-macOS ships d3d10core and d3d11 (and d3d9), never dxgi.
    func makeDXVKPayload() throws -> URL {
        let payload = root.appending(path: "DXVK")
        for arch in ["x64", "x32"] {
            let folder = payload.appending(path: arch)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for dll in ["d3d11.dll", "d3d10core.dll"] {
                try Self.nativeFake("DXVK \(arch) \(dll)").write(to: folder.appending(path: dll))
            }
        }
        return payload
    }

    /// A DXMT payload. `version` tells two payloads apart, as an engine update would.
    func makeDXMTPayload(arches: [String] = ["x64", "x32"], version: String = "") throws -> URL {
        let payload = root.appending(path: "DXMT\(version)")
        for arch in arches {
            let folder = payload.appending(path: arch)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for dll in Self.trio + ["winemetal.dll"] {
                try Self.dxmtFake(arch, dll, version: version).write(to: folder.appending(path: dll))
            }
        }
        return payload
    }

    static func dxmtFake(_ arch: String, _ dll: String, version: String = "") -> Data {
        nativeFake("DXMT\(version) \(arch) \(dll)")
    }

    @MainActor
    func system32(_ bottle: Bottle, _ dll: String) -> URL {
        bottle.url.appending(path: "drive_c/windows/system32").appending(path: dll)
    }

    /// Whether `folder` holds exactly DXMT's trio for `arch`.
    static func holdsDXMT(_ folder: URL, arch: String = "x64", version: String = "") -> Bool {
        trio.allSatisfy { contents(folder.appending(path: $0)) == dxmtFake(arch, $0, version: version) }
    }

    /// Whether `folder` holds none of the trio.
    static func holdsNoTrio(_ folder: URL) -> Bool {
        trio
            .allSatisfy {
                !FileManager.default.fileExists(atPath: folder.appending(path: $0).path(percentEncoded: false))
            }
    }
}
