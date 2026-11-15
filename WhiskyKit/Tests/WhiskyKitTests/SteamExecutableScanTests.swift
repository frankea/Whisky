//
//  SteamExecutableScanTests.swift
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

/// The install-folder scan a Steam launch keys the game's overrides, the
/// user's settings and the process watch on (#373): deep enough for Unreal and
/// `bin\x64` layouts, and blind to what must not get the game's overrides.
@Suite("Steam executable scan")
final class SteamExecutableScanTests {
    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "steam_exe_scan_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    /// Creates empty files at install-relative paths, folders included.
    private func touch(_ paths: [String], in base: URL? = nil) throws {
        let base = base ?? root
        for relative in paths {
            let url = base.appending(path: relative)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data("MZ".utf8).write(to: url)
        }
    }

    /// The scan's results as install-relative paths, in the scan's order.
    ///
    /// Relative to the install folder's name rather than its full path: the
    /// scan can hand back the temporary folder as `/private/var` or `/var`.
    private func scanned(_ subfolder: String? = nil) -> [String] {
        let installURL = subfolder.map { root.appending(path: $0) } ?? root
        let marker = "/" + root.lastPathComponent + "/" + (subfolder.map { $0 + "/" } ?? "")
        return SteamLibrary.executableURLs(under: installURL).map { url in
            url.path(percentEncoded: false).components(separatedBy: marker).last ?? ""
        }
    }

    /// A shipped Unreal Engine game, as Steam installs one.
    private func makeUnrealInstall() throws {
        try touch([
            "FSD.exe",
            "FSD/Binaries/Win64/FSD-Win64-Shipping.exe",
            "FSD/Binaries/Win64/steam_api64.dll",
            "FSD/Binaries/ThirdParty/Tool/Tool.exe",
            "FSD/Content/Movies/Intro.exe",
            "FSD/Content/Paks/FSD-WindowsNoEditor.pak",
            "FSD/Plugins/Wwise/Binaries/Win64/WwiseTool.exe",
            "Engine/Binaries/Win64/CrashReportClient.exe",
            "Engine/Binaries/Win64/EpicWebHelper.exe",
            "Engine/Binaries/Win64/UnrealCEFSubProcess.exe",
            "Engine/Binaries/ThirdParty/CEF3/Win64/libcef.dll",
            "Engine/Binaries/ThirdParty/CEF3/Win64/CefHelper.exe",
            "Engine/Extras/Redist/en-us/UE4PrereqSetup_x64.exe",
            "Engine/Programs/CrashReportClient/Content/Tool.exe",
            "_CommonRedist/vcredist/2019/VC_redist.x64.exe",
            "_CommonRedist/DirectX/Jun2010/DXSETUP.exe"
        ])
    }

    // MARK: - Layouts

    @Test("An Unreal install yields the bootstrap stub and the shipping executable, nothing else")
    func unrealLayout() throws {
        try makeUnrealInstall()

        #expect(scanned() == ["FSD.exe", "FSD/Binaries/Win64/FSD-Win64-Shipping.exe"])
    }

    @Test("3DMark's bin/x64 executable is found, its Chromium helpers are not")
    func binX64Layout() throws {
        try touch([
            "3DMark/bin/x64/3DMark.exe",
            "3DMark/bin/x64/libcef.dll",
            "3DMark/bin/x64/CefSharp.BrowserSubprocess.exe",
            "3DMark/bin/x64/3DMarkWebHelper.exe",
            "3DMark/bin/x64/crashpad_handler.exe"
        ])
        #expect(scanned("3DMark") == ["bin/x64/3DMark.exe"])
    }

    @Test("A Unity game's data folder is not read below the first level")
    func unityDataFolderIsSkipped() throws {
        try touch([
            "Game.exe",
            "UnityCrashHandler64.exe",
            "Game_Data/Tool.exe",
            "Game_Data/StreamingAssets/Bundled.exe"
        ])

        #expect(scanned() == ["Game.exe", "UnityCrashHandler64.exe", "Game_Data/Tool.exe"])
    }

    // MARK: - Unchanged at the root and the first level

    @Test("The root and the first folder level are listed whatever they hold")
    func firstLevelIsUnfiltered() throws {
        try touch([
            "UnityCrashHandler64.exe",
            "unins000.exe",
            "_CommonRedist/Setup.exe",
            "EasyAntiCheat/EasyAntiCheat_EOS_Setup.exe",
            "Launcher/Launcher.exe",
            "Launcher/libcef.dll",
            "Launcher/CefHelper.exe"
        ])

        #expect(Set(scanned()) == [
            "UnityCrashHandler64.exe", "unins000.exe", "_CommonRedist/Setup.exe",
            "EasyAntiCheat/EasyAntiCheat_EOS_Setup.exe", "Launcher/Launcher.exe", "Launcher/CefHelper.exe"
        ])
    }

    @Test("Redistributable, installer and anti-cheat folders are not read below the first level")
    func skippedFoldersBelowTheFirstLevel() throws {
        try touch([
            "Game/bin/Game.exe",
            "Game/Redist/vc_redist.x64.exe",
            "Game/Installers/Setup2.exe",
            "Game/__Installer/directx/redist/DXSETUP.exe",
            "Game/Support/Tool.exe",
            "Game/EasyAntiCheat/EasyAntiCheat_Setup.exe",
            "Game/BattlEye/BEService_x64.exe",
            "Game/DotNet/NDP472.exe"
        ])

        #expect(scanned() == ["Game/bin/Game.exe"])
    }

    // MARK: - Bounds

    @Test("Executables four folders down are found, five down are not")
    func depthCap() throws {
        try touch(["a/b/c/d/Four.exe", "a/b/c/d/e/Five.exe"])

        #expect(scanned() == ["a/b/c/d/Four.exe"])
    }

    @Test("Symbolic links below the first level are never followed, to a folder or a file")
    func symlinksAreNotFollowed() throws {
        let outside = FileManager.default.temporaryDirectory.appending(path: "steam_exe_outside_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outside) }
        try touch(["Outside.exe", "nested/Nested.exe"], in: outside)
        try touch(["Game/bin/Game.exe"])
        let fileManager = FileManager.default
        try fileManager.createSymbolicLink(
            at: root.appending(path: "Game/bin/linked"), withDestinationURL: outside
        )
        try fileManager.createSymbolicLink(
            at: root.appending(path: "Game/bin/Alias.exe"), withDestinationURL: outside.appending(path: "Outside.exe")
        )
        try fileManager.createSymbolicLink(at: root.appending(path: "Top"), withDestinationURL: outside)

        #expect(scanned() == ["Game/bin/Game.exe"])
    }

    @Test("Results below the first level stop at the limit, shallowest and by name first")
    func resultLimit() throws {
        let names = (0 ..< SteamLibrary.deepScanResultLimit + 6).map { "a/b/Game\(String(1_000 + $0).dropFirst()).exe" }
        try touch(names)

        #expect(scanned() == Array(names.prefix(SteamLibrary.deepScanResultLimit)))
    }

    @Test("The order is shallowest first and by name within a folder, scan after scan")
    func orderIsStable() throws {
        try touch(["Zed.exe", "Alpha.exe", "bin/Tool.exe", "Game/Binaries/Win64/B.exe", "Game/Binaries/Win64/A.exe"])

        let first = scanned()
        #expect(first == [
            "Alpha.exe", "Zed.exe", "bin/Tool.exe", "Game/Binaries/Win64/A.exe", "Game/Binaries/Win64/B.exe"
        ])
        #expect(scanned() == first)
    }

    // MARK: - Rules

    @Test("Folders the scan leaves unread", arguments: [
        ("_CommonRedist", nil), ("redist", "Game"), ("ThirdParty", "Binaries"), ("Extras", "Engine"),
        ("Plugins", "Engine"), ("Content", "FSD"), ("Paks", "Content"), ("Game_Data", nil)
    ] as [(String, String?)])
    func skippedFolders(_ name: String, _ parent: String?) {
        #expect(SteamLibrary.skipsDescent(into: name, parentName: parent), "\(parent ?? "")/\(name)")
    }

    @Test("Folders the scan reads", arguments: [
        ("Binaries", "Engine"), ("Binaries", "FSD"), ("x64", "bin"), ("Win64", "Binaries")
    ] as [(String, String?)])
    func readFolders(_ name: String, _ parent: String?) {
        #expect(!SteamLibrary.skipsDescent(into: name, parentName: parent), "\(parent ?? "")/\(name)")
    }

    @Test("Executables below the first level that are never the game", arguments: [
        ("CrashReportClient.exe", false), ("UnityCrashHandler64.exe", false), ("crashpad_handler.exe", false),
        ("UnrealCEFSubProcess.exe", false), ("EpicWebHelper.exe", false), ("unins000.exe", false),
        ("UE4PrereqSetup_x64.exe", false), ("GameLauncher.exe", false),
        ("BootstrapPackagedGame-Win64-Shipping.exe", false), ("GameHelper.exe", true)
    ])
    func auxiliaryExecutables(_ name: String, _ besideChromium: Bool) {
        #expect(!SteamLibrary.isGameExecutable(name, besideChromium: besideChromium), "\(name)")
    }

    @Test("Executables below the first level that can be the game", arguments: [
        ("Game-Win64-Shipping.exe", false), ("3DMark.exe", true), ("GameHelper.exe", false)
    ])
    func gameExecutables(_ name: String, _ besideChromium: Bool) {
        #expect(SteamLibrary.isGameExecutable(name, besideChromium: besideChromium), "\(name)")
    }
}

/// What the deeper scan changes for the callers that key on it.
@Suite("Steam executable scan callers")
@MainActor
final class SteamExecutableScanCallerTests {
    private let tempRoot: URL

    init() throws {
        tempRoot = FileManager.default.temporaryDirectory.appending(path: "steam_exe_callers_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func touch(_ paths: [String], in base: URL) throws {
        for relative in paths {
            let url = base.appending(path: relative)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data("MZ".utf8).write(to: url)
        }
    }

    private let unrealLayout = [
        "FSD.exe",
        "FSD/Binaries/Win64/FSD-Win64-Shipping.exe",
        "Engine/Binaries/Win64/CrashReportClient.exe",
        "Engine/Binaries/Win64/UnrealCEFSubProcess.exe"
    ]

    @Test("A Steam launch writes the game's plan to the deep shipping executable, and none to engine helpers")
    func launchWritesTheDeepExecutablesEntry() async throws {
        let bottleURL = tempRoot.appending(path: "Bottle")
        let install = bottleURL.appending(path: "drive_c/Games/FSD")
        try touch(
            ["windows/system32/.keep", "Program Files (x86)/Steam/steam.exe"], in: bottleURL.appending(path: "drive_c")
        )
        try touch(unrealLayout, in: install)
        let bottle = Bottle(bottleUrl: bottleURL)
        let steamExe = bottleURL.appending(path: "drive_c/Program Files (x86)/Steam/steam.exe")
        var overrides = ProgramOverrides()
        overrides.graphicsBackend = .dxvk
        let plan = LaunchPlan(overrides: overrides, gameProfileEnvironment: [:], provenance: [])
        let recorder = ScopeRecorder()

        // What SteamLauncher.launch hands Wine.runProgram.
        let executables = SteamLauncher.gameExecutables(installURL: install, plan: plan)
        _ = try await Wine.prepareProgramLaunch(
            at: steamExe, args: ["-applaunch", "548430"], bottle: bottle,
            programOverrides: plan.overrides, overridesApplyToDescendants: true,
            descendantExecutables: executables,
            recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: true,
            overrideWriter: recorder.writer, importer: recorder.importer
        )

        #expect(executables == ["FSD.exe", "FSD-Win64-Shipping.exe"])
        for game in executables {
            #expect(recorder.overrides(for: .program(game))?["d3d11"] == "n,b", "\(game)")
        }
        #expect(!recorder.programScopes.contains("CrashReportClient.exe"))
        #expect(!recorder.programScopes.contains("UnrealCEFSubProcess.exe"))
    }

    @Test("Settings tuned on the deep shipping executable reach a Steam launch")
    func deepExecutablesSettingsWin() throws {
        let bottleURL = tempRoot.appending(path: "Bottle")
        let install = bottleURL.appending(path: "drive_c/Games/FSD")
        try touch(unrealLayout, in: install)
        let bottle = Bottle(bottleUrl: bottleURL)
        var tuned = ProgramOverrides()
        tuned.graphicsBackend = .dxvk
        let shipping = install.appending(path: "FSD/Binaries/Win64/FSD-Win64-Shipping.exe")
        Program(url: shipping, bottle: bottle, peFile: nil).settings.overrides = tuned

        #expect(SteamLauncher.userOverrides(forInstallURL: install, bottle: bottle) == tuned)
    }

    @Test("The library shows a game running by its deep shipping executable, not by its crash reporter")
    func trackingSeesTheDeepExecutable() async throws {
        let (bottle, games) = try SteamOrchestratorFixture.makeBottle()
        try touch(unrealLayout.filter { $0 != "FSD.exe" }, in: games[0].installURL)
        let driver = FakeSteamClientDriver(script: [["steam.exe", "crashreportclient.exe"]])
        let orchestrator = SteamClientOrchestrator(
            bottle: bottle, driver: driver, timing: SteamOrchestratorFixture.patient
        )

        orchestrator.startTracking(games: games)
        // Let the scan and a refresh land before checking it stayed empty.
        try await Task.sleep(for: .milliseconds(100))
        #expect(orchestrator.runningAppIds.isEmpty)

        driver.script = [["steam.exe", "fsd-win64-shipping.exe"]]
        orchestrator.processSnapshot = nil
        await SteamOrchestratorFixture.eventually("the shipping executable should count as the game") {
            orchestrator.runningAppIds == [games[0].appId]
        }
        orchestrator.stop()
    }
}
