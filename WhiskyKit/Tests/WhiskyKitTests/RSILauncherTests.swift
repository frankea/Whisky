//
//  RSILauncherTests.swift
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

/// The RSI Launcher draws its window only on DXVK (#168). It is detected as a
/// launcher so Recommended steers it there, while Star Citizen, the game it
/// starts from the folder beside it, resolves the way the bottle's games do.
/// Started by the launcher over DXMT, the game still loads the DXVK files the
/// launcher's launch left in the prefix.
@Suite("RSI Launcher")
@MainActor
final class RSILauncherTests {
    private static let installFolder = "Program Files/Roberts Space Industries/RSI Launcher"
    private static let gameFolder = "Program Files/Roberts Space Industries/StarCitizen/LIVE/Bin64"

    private let tempRoot: URL

    init() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "rsi_launcher_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func makeBottle(_ backend: GraphicsBackend = .recommended) throws -> Bottle {
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
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("MZ".utf8).write(to: url)
        return url
    }

    private func rsiLauncher(in bottle: Bottle) throws -> URL {
        try makeExecutable("\(Self.installFolder)/RSI Launcher.exe", in: bottle)
    }

    private func starCitizen(in bottle: Bottle) throws -> URL {
        try makeExecutable("\(Self.gameFolder)/StarCitizen.exe", in: bottle)
    }

    /// Prepares a launch of `url` against a runtime pinned to D3DMetal.
    private func prepare(
        _ url: URL, in bottle: Bottle, programOverrides: ProgramOverrides? = nil, recorder: ScopeRecorder
    ) async throws -> Wine.PreparedLaunch {
        try await Wine.prepareProgramLaunch(
            at: url, bottle: bottle, programOverrides: programOverrides,
            recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: true,
            overrideWriter: recorder.writer, importer: recorder.importer
        )
    }

    private func expectDXVK(_ overrides: [String: String]?, _ label: String) {
        #expect(overrides?["dxgi"] == "n,b", "\(label): dxgi")
        #expect(overrides?["d3d11"] == "n,b", "\(label): d3d11")
        #expect(overrides?["d3d10core"] == "n,b", "\(label): d3d10core")
    }

    private func expectNoTranslationLayer(_ overrides: [String: String]?, _ label: String) {
        #expect(overrides != nil, "\(label) has an entry")
        for dll in ["dxgi", "d3d9", "d3d10core", "d3d11", "d3d12"] {
            #expect(overrides?[dll] == nil, "\(label) must not mention \(dll)")
        }
    }

    // MARK: - Detection

    @Test("The launcher is detected from its executable and its install folder", arguments: [
        "C:/Program Files/Roberts Space Industries/RSI Launcher/RSI Launcher.exe",
        "C:\\Program Files\\Roberts Space Industries\\RSI Launcher\\RSI Launcher.exe",
        "/Users/u/Bottles/B/drive_c/Program Files/Roberts Space Industries/RSI Launcher/RSI Launcher.exe",
        "/Users/u/Bottles/B/drive_c/Games/RSI/RSI Launcher.exe",
        "/Users/u/Bottles/B/drive_c/Program Files/Roberts Space Industries/RSI Launcher/Uninstall RSI Launcher.exe",
        "C:/PROGRAM FILES/ROBERTS SPACE INDUSTRIES/RSI LAUNCHER/RSI LAUNCHER.EXE"
    ])
    func detectsTheLauncher(_ path: String) {
        #expect(LauncherType.detect(from: URL(fileURLWithPath: path)) == .rsiLauncher)
    }

    @Test("A Mac folder named like another launcher does not claim it first")
    func detectionComesBeforeLooseMatches() {
        // "/steam/" and "/origin/" in the bottle's location match Steam and EA App.
        for root in ["/Volumes/Steam/Bottles/B", "/Users/u/Origin/B"] {
            let url = URL(fileURLWithPath: "\(root)/drive_c/\(Self.installFolder)/RSI Launcher.exe")
            #expect(LauncherType.detect(from: url) == .rsiLauncher, "\(root)")
        }
    }

    @Test("Star Citizen and other executables are not the launcher", arguments: [
        "/Users/u/Bottles/B/drive_c/Program Files/Roberts Space Industries/StarCitizen/LIVE/Bin64/StarCitizen.exe",
        "C:\\Program Files\\Roberts Space Industries\\StarCitizen\\LIVE\\Bin64\\StarCitizen.exe",
        "C:/Program Files/Roberts Space Industries/StarCitizen/PTU/Bin64/StarCitizen.exe",
        "C:/Program Files/Roberts Space Industries/StarCitizen/LIVE/Launcher.exe",
        "C:/Program Files/Roberts Space Industries/RSI Launcher Backup/app.exe",
        "C:/Users/User/Downloads/RSI-Setup-2.10.0.exe",
        "C:/Games/Some Game/Launcher.exe",
        "C:/Games/Some Game/launcher.exe"
    ])
    func doesNotDetectOthers(_ path: String) {
        #expect(LauncherType.detect(from: URL(fileURLWithPath: path)) == nil)
    }

    // MARK: - Resolution

    @Test("Recommended resolves the launcher to DXVK on every runtime")
    func resolverGivesTheLauncherDXVK() {
        let runtime = WhiskyWineVersion(version: SemanticVersion(3, 1, 1), dxmtVersion: "0.80")
        for (d3dMetal, dxmtNative) in [(true, false), (false, true), (false, false)] {
            #expect(
                GraphicsBackendResolver.resolve(
                    for: .rsiLauncher, runtimeInfo: runtime,
                    d3dMetalInstalled: d3dMetal, dxmtRuntimeNative: dxmtNative
                ) == .dxvk
            )
        }
    }

    @Test("Star Citizen on its own resolves the way the bottle's games do")
    func gameResolvesAsAGame() {
        let url = URL(fileURLWithPath: "C:/\(Self.gameFolder)/StarCitizen.exe")
        let runtime = WhiskyWineVersion(version: SemanticVersion(3, 1, 1), dxmtVersion: "0.80")
        let launcher = LauncherType.detect(from: url)
        #expect(GraphicsBackendResolver.resolve(for: launcher, d3dMetalInstalled: true) == .d3dMetal)
        #expect(
            GraphicsBackendResolver.resolve(
                for: launcher, runtimeInfo: runtime, d3dMetalInstalled: false, dxmtRuntimeNative: true
            ) == .dxmt
        )
    }

    // MARK: - Launch preparation

    @Test("Launching the launcher on a Recommended bottle gives its own entry DXVK")
    func launchSteersTheLauncherToDXVK() async throws {
        let bottle = try makeBottle()
        let recorder = ScopeRecorder()

        let launch = try await prepare(rsiLauncher(in: bottle), in: bottle, recorder: recorder)

        // Its Chromium children run as the same executable, so they read this entry.
        expectDXVK(recorder.overrides(for: .program("RSI Launcher.exe")), "RSI Launcher.exe")
        // The prefix default is the games', and nothing is left for a child to inherit.
        expectNoTranslationLayer(recorder.overrides(for: .bottle), "the bottle scope")
        #expect(launch.environment["WINEDLLOVERRIDES"] == nil)
        #expect(bottle.settings.graphicsBackend == .recommended)
    }

    @Test("A program on Recommended in a bottle set to D3DMetal still steers the launcher")
    func programOnRecommendedSteersTheLauncher() async throws {
        let bottle = try makeBottle(.d3dMetal)
        var overrides = ProgramOverrides()
        overrides.graphicsBackend = .recommended
        let recorder = ScopeRecorder()

        _ = try await prepare(rsiLauncher(in: bottle), in: bottle, programOverrides: overrides, recorder: recorder)

        expectDXVK(recorder.overrides(for: .program("RSI Launcher.exe")), "RSI Launcher.exe")
    }

    @Test("Star Citizen in the same bottle keeps the bottle's Recommended backend")
    func gameKeepsTheBottlesBackend() async throws {
        let bottle = try makeBottle()
        let recorder = ScopeRecorder()

        let launch = try await prepare(starCitizen(in: bottle), in: bottle, recorder: recorder)

        expectNoTranslationLayer(recorder.overrides(for: .program("StarCitizen.exe")), "StarCitizen.exe")
        #expect(launch.environment["WINEDLLOVERRIDES"] == nil)
    }

    @Test("Over DXMT, Star Citizen started by the launcher loads the DXVK files the launcher's launch leaves")
    func launcherLeavesDXVKWhereTheGameLoadsIt() async throws {
        let bottle = try makeBottle()
        let system32 = bottle.url.appending(path: "drive_c/windows/system32")
        let dlls = ["d3d10core.dll", "d3d11.dll"]
        // An earlier launch from Whisky left DXMT's files.
        for dll in dlls {
            try Data("DXMT \(dll)".utf8).write(to: system32.appending(path: dll))
        }
        let dxvkFolder = tempRoot.appending(path: "DXVK")
        for arch in ["x64", "x32"] {
            let folder = dxvkFolder.appending(path: arch)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for dll in dlls {
                try Data("DXVK \(dll)".utf8).write(to: folder.appending(path: dll))
            }
        }
        let recorder = ScopeRecorder()

        _ = try await Wine.prepareProgramLaunch(
            at: rsiLauncher(in: bottle), bottle: bottle,
            recommendedBackend: .dxmt, builtinD3D12IsD3DMetal: false,
            overrideWriter: recorder.writer, importer: recorder.importer, dxvkFolder: dxvkFolder
        )

        expectDXVK(recorder.overrides(for: .program("RSI Launcher.exe")), "RSI Launcher.exe")
        // DXVK's files replaced DXMT's, and the bottle scope, which Star Citizen
        // reads when the launcher starts it, prefers the native ones: the game
        // runs on DXVK. The bottle itself stays on Recommended.
        for dll in dlls {
            #expect(try Data(contentsOf: system32.appending(path: dll)) == Data("DXVK \(dll)".utf8), "\(dll)")
        }
        let bottleScope = recorder.overrides(for: .bottle)
        #expect(bottleScope?["d3d11"] == "n,b")
        #expect(bottleScope?["d3d10core"] == "n,b")
        #expect(bottle.settings.graphicsBackend == .recommended)
    }

    // MARK: - Launcher fixes

    @Test("Detecting the launcher changes nothing bottle-wide that Star Citizen would inherit")
    func detectionLeavesTheBottleAlone() throws {
        let bottle = try makeBottle()
        bottle.settings.launcherCompatibilityMode = true
        bottle.settings.launcherMode = .auto
        let gpuSpoofing = bottle.settings.gpuSpoofing
        let locale = bottle.settings.launcherLocale
        let url = URL(fileURLWithPath: "C:/\(Self.installFolder)/RSI Launcher.exe")

        #expect(LauncherFixes.detectAndApply(from: url, for: bottle))

        #expect(bottle.settings.detectedLauncher == .rsiLauncher)
        #expect(bottle.settings.graphicsBackend == .recommended)
        #expect(!bottle.settings.dxvk)
        #expect(!bottle.settings.launcherSwitchedBackend)
        #expect(bottle.settings.gpuSpoofing == gpuSpoofing)
        #expect(bottle.settings.launcherLocale == locale)
        // No bottle-wide DXVK requirement, which the launcher auto-enable would deploy.
        #expect(bottle.settings.detectedLauncher?.requiresDXVK == false)
        let env = Wine.constructWineEnvironment(
            for: bottle, recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: true
        )
        for key in ["LC_ALL", "LANG"] {
            #expect(env[key] == nil, "\(key)")
        }
        expectNoTranslationLayer(Wine.parseDLLOverrides(env["WINEDLLOVERRIDES"] ?? ""), "the bottle's overrides")
    }
}
