//
//  ProgramLaunchVirtualDesktopTests.swift
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

@Suite("Program launch virtual desktop")
@MainActor
final class ProgramLaunchVirtualDesktopTests {
    private let tempRoot: URL

    init() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "launch_vd_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    /// Prepares `Games/My Game.exe` with `-x` on a bottle whose virtual desktop is
    /// `bottleEnabled`. The program's overrides set `programEnabled` and
    /// `resolution`; with `withOverrides` false the program has none at all.
    private func prepare(
        bottleEnabled: Bool, programEnabled: Bool?, resolution: ResolutionPreset? = nil,
        withOverrides: Bool = true
    ) async throws -> (arguments: [String], path: String) {
        let bottleURL = tempRoot.appending(path: "Bottle")
        try FileManager.default.createDirectory(
            at: bottleURL.appending(path: "drive_c/windows/system32"), withIntermediateDirectories: true
        )
        let bottle = Bottle(bottleUrl: bottleURL)
        bottle.settings.virtualDesktopEnabled = bottleEnabled

        let url = bottleURL.appending(path: "drive_c/Games/My Game.exe")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("MZ".utf8).write(to: url)

        var overrides = ProgramOverrides()
        overrides.virtualDesktopEnabled = programEnabled
        overrides.resolutionPreset = resolution

        let launch = try await Wine.prepareProgramLaunch(
            at: url, args: ["-x"], bottle: bottle, programOverrides: withOverrides ? overrides : nil,
            overrideWriter: { _, _ in }, importer: { _, _ in }
        )
        return (launch.arguments, url.path(percentEncoded: false))
    }

    @Test("A program set to a virtual desktop is prepared to run in one, from its own folder")
    func virtualDesktopOn() async throws {
        for bottleEnabled in [false, true] {
            let launch = try await prepare(
                bottleEnabled: bottleEnabled, programEnabled: true, resolution: .r1280x720
            )
            #expect(launch.arguments == [
                "explorer", "/desktop=My_Game.exe,1280x720", "start", "/unix", launch.path, "-x"
            ])
        }
    }

    @Test("A program set to run without a virtual desktop leaves the bottle's")
    func virtualDesktopOffLeavesTheBottles() async throws {
        let launch = try await prepare(bottleEnabled: true, programEnabled: false)
        #expect(launch.arguments == ["explorer", "/desktop=root", "start", "/unix", launch.path, "-x"])
    }

    @Test("Without the bottle's virtual desktop, turning it off changes nothing")
    func virtualDesktopOffWithoutTheBottles() async throws {
        let launch = try await prepare(bottleEnabled: false, programEnabled: false)
        #expect(launch.arguments == ["start", "/unix", launch.path, "-x"])
    }

    @Test("A program without a display override joins the bottle's virtual desktop")
    func virtualDesktopInheritedFromTheBottle() async throws {
        for withOverrides in [true, false] {
            let launch = try await prepare(bottleEnabled: true, programEnabled: nil, withOverrides: withOverrides)
            #expect(launch.arguments == ["start", "/unix", launch.path, "-x"])
        }
    }
}
