//
//  WhiskyAppVersionTests.swift
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

@Suite("Whisky App Version Tests")
struct WhiskyAppVersionTests {
    /// A folder laid out like an installed app: `Whisky.app` with its
    /// Info.plist and the CLI in `Contents/Resources`, plus a `bin` folder
    /// for symlinks to it.
    private struct Layout {
        let root: URL
        var app: URL { root.appending(path: "Whisky.app") }
        var cli: URL { app.appending(path: "Contents/Resources/WhiskyCmd") }
        var bin: URL { root.appending(path: "bin") }

        init(version: String?) throws {
            root = FileManager.default.temporaryDirectory
                .appending(path: "whisky-app-version-\(UUID().uuidString)")
            let manager = FileManager.default
            try manager.createDirectory(at: cli.deletingLastPathComponent(), withIntermediateDirectories: true)
            try manager.createDirectory(at: bin, withIntermediateDirectories: true)
            try Data().write(to: cli)
            var info: [String: Any] = ["CFBundleIdentifier": "com.franke.Whisky", "CFBundleVersion": "60"]
            info["CFBundleShortVersionString"] = version
            let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            try data.write(to: app.appending(path: "Contents/Info.plist"))
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    @Test("The app's own version wins, so the app's logs are unchanged")
    func mainBundleVersionWins() throws {
        let layout = try Layout(version: "1.0.0")
        defer { layout.remove() }

        let version = WhiskyAppVersion.shortVersion(
            mainInfo: ["CFBundleShortVersionString": "3.10.0"], executableURL: layout.cli
        )

        #expect(version == "3.10.0")
    }

    @Test("The CLI inside the app reads the app's version")
    func cliInsideTheApp() throws {
        let layout = try Layout(version: "3.10.0")
        defer { layout.remove() }

        // What a bare executable's main bundle has: no version.
        let version = WhiskyAppVersion.shortVersion(
            mainInfo: ["CFBundleExecutable": "WhiskyCmd"], executableURL: layout.cli
        )

        #expect(version == "3.10.0")
        #expect(WhiskyAppVersion.shortVersion(mainInfo: nil, executableURL: layout.cli) == "3.10.0")
    }

    @Test("The CLI run through a symlink, as /usr/local/bin/whisky is, still finds the app")
    func cliThroughSymlink() throws {
        let layout = try Layout(version: "3.10.0")
        defer { layout.remove() }
        let link = layout.bin.appending(path: "whisky")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: layout.cli)

        #expect(WhiskyAppVersion.shortVersion(mainInfo: nil, executableURL: link) == "3.10.0")
    }

    @Test("A CLI outside any app, or in an app without a version, reports none")
    func noEnclosingVersion() throws {
        let layout = try Layout(version: nil)
        defer { layout.remove() }
        let loose = layout.bin.appending(path: "WhiskyCmd")
        try Data().write(to: loose)

        #expect(WhiskyAppVersion.shortVersion(mainInfo: nil, executableURL: loose) == "")
        #expect(WhiskyAppVersion.shortVersion(mainInfo: nil, executableURL: layout.cli) == "")
        #expect(WhiskyAppVersion.shortVersion(mainInfo: nil, executableURL: nil) == "")
    }

    @Test("A log header carries the version the lookup finds")
    func headerUsesTheLookup() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "whisky-app-version-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil)
        defer { try? FileManager.default.removeItem(at: url) }
        let handle = try FileHandle(forWritingTo: url)

        handle.writeApplicationInfo()
        try handle.closeWineLog()

        let header = try String(contentsOf: url, encoding: .utf8)
        #expect(header.hasPrefix("Whisky Version: \(WhiskyAppVersion.current)\n"))
    }
}
