//
//  ChromiumFrontEndTests.swift
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
import SemanticVersion
import Testing
@testable import WhiskyKit

/// The curated table of Chromium front ends Recommended runs on DXVK (#372),
/// and how the resolver reports the pick.
@Suite("Chromium front ends")
struct ChromiumFrontEndTests {
    /// Names too generic for an `AppDefaults` entry, which is keyed on the
    /// file name alone and so reaches every executable by that name.
    static let genericNames: Set<String> = [
        "launcher.exe", "game.exe", "client.exe", "start.exe", "setup.exe", "app.exe", "update.exe",
        "main.exe", "run.exe", "play.exe", "installer.exe", "uninstall.exe", "updater.exe", "helper.exe",
        "browser.exe", "nw.exe", "electron.exe", "cefclient.exe", "cefsharp.browsersubprocess.exe",
        "unrealcefsubprocess.exe", "qtwebengineprocess.exe", "msedgewebview2.exe", "crashpad_handler.exe"
    ]

    private static var allNames: [String] {
        ChromiumFrontEnd.all.flatMap { $0.executables + $0.helperExecutables }
    }

    // MARK: - Matching

    @Test("3DMark's front end matches by file name, without case, on either path style", arguments: [
        "/Users/u/Bottles/B/drive_c/Program Files (x86)/Steam/steamapps/common/3DMark/bin/x64/3DMark.exe",
        "C:\\Program Files (x86)\\Steam\\steamapps\\common\\3DMark\\bin\\x64\\3DMark.exe",
        "C:/Program Files/UL/3DMark/3dmark.exe",
        "/tmp/3DMARK.EXE"
    ])
    func matchesTheFrontEnd(_ path: String) {
        let url = URL(fileURLWithPath: path)
        #expect(ChromiumFrontEnd.match(url: url) == .threeDMark)
        #expect(DXVKSteering.detect(executable: url) == .chromiumFrontEnd(.threeDMark))
    }

    @Test("Other executables match nothing, even beside libcef.dll", arguments: [
        "/b/drive_c/Games/Some Game/Game.exe",
        "/b/drive_c/Games/3DMark/bin/x64/workloads/TimeSpy.exe",
        "/b/drive_c/Games/3DMark/3DMark.exe.bak",
        "/b/drive_c/Games/3DMarkLauncher.exe"
    ])
    func matchesNothingElse(_ path: String) {
        #expect(ChromiumFrontEnd.match(url: URL(fileURLWithPath: path)) == nil)
        #expect(ChromiumFrontEnd.match(executableName: "") == nil)
    }

    @Test("A launcher keeps its own path, ahead of the table")
    func launcherComesFirst() {
        let steam = URL(fileURLWithPath: "/b/drive_c/Program Files (x86)/Steam/steam.exe")
        #expect(DXVKSteering.detect(executable: steam) == .launcher(.steam))
        let rsi =
            URL(fileURLWithPath: "/b/drive_c/Program Files/Roberts Space Industries/RSI Launcher/RSI Launcher.exe")
        #expect(DXVKSteering.detect(executable: rsi) == .launcher(.rsiLauncher))
    }

    @Test("A game with CEF in its folder is not steered")
    func embeddedCEFIsNotSteered() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "cef_game_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let game = folder.appending(path: "Game.exe")
        try Data("MZ".utf8).write(to: game)
        #expect(!ChromiumFrontEnd.shipsCEF(beside: game))
        try Data("MZ".utf8).write(to: folder.appending(path: "libcef.dll"))

        #expect(ChromiumFrontEnd.shipsCEF(beside: game), "only the suggestion and the export see it")
        #expect(DXVKSteering.detect(executable: game) == nil)
    }

    // MARK: - Table hygiene

    @Test("Every row is verified, distinct, and lists at least one executable")
    func rowsAreVerified() {
        #expect(!ChromiumFrontEnd.all.isEmpty)
        #expect(Set(ChromiumFrontEnd.all.map(\.id)).count == ChromiumFrontEnd.all.count)
        for row in ChromiumFrontEnd.all {
            #expect(!row.verifiedIn.isEmpty, "\(row.id) has no verification")
            #expect(!row.executables.isEmpty, "\(row.id)")
            #expect(!row.installLocations.isEmpty, "\(row.id)")
        }
        let names = Self.allNames.map { $0.lowercased() }
        #expect(Set(names).count == names.count, "each name belongs to one row")
    }

    @Test("No name is generic enough to reach unrelated programs")
    func namesAreDistinctive() {
        for name in Self.allNames {
            #expect(!Self.genericNames.contains(name.lowercased()), "\(name) is too generic for AppDefaults")
            #expect(name.lowercased().hasSuffix(".exe"), "\(name)")
        }
    }

    @Test("No name is a launcher's, or detects as one")
    func namesDoNotCollideWithLaunchers() {
        let launcherNames = Set(
            LauncherType.allCases.flatMap { $0.helperExecutables + $0.chainExecutables }.map { $0.lowercased() }
                + ["steam.exe"]
        )
        for name in Self.allNames {
            #expect(!launcherNames.contains(name.lowercased()), "\(name)")
            #expect(LauncherType.detect(from: URL(fileURLWithPath: "/b/drive_c/Games/\(name)")) == nil, "\(name)")
        }
    }

    @Test("No name is a GameDB game's executable")
    func namesDoNotCollideWithGameDB() {
        let gameNames = Set(GameDBLoader.loadDefaults().flatMap { $0.exeNames ?? [] }.map { $0.lowercased() })
        #expect(!gameNames.isEmpty)
        for name in Self.allNames {
            #expect(!gameNames.contains(name.lowercased()), "\(name)")
        }
    }

    // MARK: - Resolution

    @Test("A front end resolves to DXVK, steered, on every runtime")
    func frontEndResolvesToDXVK() {
        let runtime = WhiskyWineVersion(version: SemanticVersion(3, 1, 1), dxmtVersion: "0.80")
        for (d3dMetal, dxmtNative) in [(true, false), (false, true), (false, false)] {
            let resolution = GraphicsBackendResolver.resolution(
                for: .chromiumFrontEnd(.threeDMark), runtimeInfo: runtime,
                d3dMetalInstalled: d3dMetal, dxmtRuntimeNative: dxmtNative
            )
            #expect(resolution == BackendResolution(backend: .dxvk, reason: .steered(.chromiumFrontEnd(.threeDMark))))
        }
    }

    @Test("An unsteered executable keeps the D3DMetal, DXMT, DXVK chain, with its reason")
    func unsteeredKeepsTheChain() {
        let runtime = WhiskyWineVersion(version: SemanticVersion(3, 1, 1), dxmtVersion: "0.80")
        let cases: [(payloads: (d3dMetal: Bool, dxmtNative: Bool), expected: BackendResolution)] = [
            ((true, false), BackendResolution(backend: .d3dMetal, reason: .d3dMetal)),
            ((false, true), BackendResolution(backend: .dxmt, reason: .dxmt)),
            ((false, false), BackendResolution(backend: .dxvk, reason: .dxvkFallback))
        ]
        for (payloads, expected) in cases {
            let (d3dMetal, dxmtNative) = payloads
            let resolution = GraphicsBackendResolver.resolution(
                for: nil, runtimeInfo: runtime, d3dMetalInstalled: d3dMetal, dxmtRuntimeNative: dxmtNative
            )
            #expect(resolution == expected)
            // The launcher wrapper answers the same as before.
            #expect(
                GraphicsBackendResolver.resolve(
                    runtimeInfo: runtime, d3dMetalInstalled: d3dMetal, dxmtRuntimeNative: dxmtNative
                ) == expected.backend
            )
            #expect(
                GraphicsBackendResolver.resolve(
                    for: .steam, runtimeInfo: runtime, d3dMetalInstalled: d3dMetal, dxmtRuntimeNative: dxmtNative
                ) == .dxvk
            )
        }
    }

    @Test("Every reason has a rationale and an export name")
    func everyReasonExplainsItself() {
        let reasons: [RecommendedReason] = [
            .steered(.launcher(.steam)), .steered(.chromiumFrontEnd(.threeDMark)), .d3dMetal, .dxmt, .dxvkFallback
        ]
        for reason in reasons {
            for games in [GraphicsBackend.d3dMetal, .dxmt, .dxvk] {
                let resolution = BackendResolution(backend: .dxvk, reason: reason)
                #expect(!resolution.rationale(gamesBackend: games).isEmpty)
            }
            #expect(!reason.exportName.isEmpty)
        }
        #expect(RecommendedReason.steered(.chromiumFrontEnd(.threeDMark)).exportName.contains("3DMark"))
    }

    @Test("A steering names what it steers and carries its helpers")
    func steeringDescribesItself() {
        let launcher = DXVKSteering.launcher(.steam)
        #expect(launcher.displayName == LauncherType.steam.displayName)
        #expect(launcher.helperExecutables == LauncherType.steam.helperExecutables)
        #expect(launcher.evidence == "launcher: \(LauncherType.steam.rawValue)")

        let frontEnd = DXVKSteering.chromiumFrontEnd(.threeDMark)
        #expect(frontEnd.displayName == "3DMark")
        #expect(frontEnd.helperExecutables == ChromiumFrontEnd.threeDMark.helperExecutables)
        #expect(frontEnd.evidence == "Chromium front end: 3DMark")
    }
}
