//
//  SteamExecutableScanCallerTests.swift
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

    private static let emptyPlan = LaunchPlan(
        overrides: ProgramOverrides(),
        gameProfileEnvironment: [:],
        provenance: []
    )

    /// A bottle with Steam and 3DMark, and where the two are.
    private struct ThreeDMarkBottle {
        let bottle: Bottle
        let install: URL
        let steamExe: URL
    }

    /// A bottle with Steam and 3DMark, whose front end can carry the user's settings.
    /// `frontEndName` stands in for a Chromium host outside the front-end table.
    private func make3DMarkBottle(
        tuning frontEnd: ProgramOverrides?, frontEndName: String = "3DMark.exe"
    ) throws -> ThreeDMarkBottle {
        let bottleURL = tempRoot.appending(path: "Bottle")
        let install = bottleURL.appending(path: "drive_c/Games/3DMark")
        try touch(
            ["windows/system32/.keep", "Program Files (x86)/Steam/steam.exe"], in: bottleURL.appending(path: "drive_c")
        )
        try touch(["bin/x64/\(frontEndName)", "bin/x64/libcef.dll", "bin/x64/workloads/Workload.exe"], in: install)
        let bottle = Bottle(bottleUrl: bottleURL)
        if let frontEnd {
            Program(url: install.appending(path: "bin/x64/\(frontEndName)"), bottle: bottle, peFile: nil)
                .settings.overrides = frontEnd
        }
        return ThreeDMarkBottle(
            bottle: bottle, install: install,
            steamExe: bottleURL.appending(path: "drive_c/Program Files (x86)/Steam/steam.exe")
        )
    }

    @Test("A Chromium front end keeps its own settings on a Steam launch; the workloads keep the game's plan")
    func chromiumHostKeepsItsOwnSettings() async throws {
        var frontEnd = ProgramOverrides()
        frontEnd.graphicsBackend = .dxvk
        let fixture = try make3DMarkBottle(tuning: frontEnd)
        let (bottle, install, steamExe) = (fixture.bottle, fixture.install, fixture.steamExe)
        let plan = LaunchResolver.plan(
            steamAppId: 223_850,
            userOverrides: SteamLauncher.userOverrides(forInstallURL: install, bottle: bottle),
            appliedConfiguration: nil, entries: []
        )
        let recorder = ScopeRecorder()

        // What SteamLauncher.launch hands Wine.runProgram.
        let executables = SteamLauncher.gameExecutables(installURL: install, plan: plan)
        _ = try await Wine.prepareProgramLaunch(
            at: steamExe, args: ["-applaunch", "223850"], bottle: bottle,
            programOverrides: plan.overrides, overridesApplyToDescendants: true,
            descendantExecutables: executables,
            ownSettingsExecutables: SteamLibrary.scanExecutables(under: install).chromiumHosts,
            recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: true,
            overrideWriter: recorder.writer, importer: recorder.importer
        )

        #expect(SteamLauncher.userOverrides(forInstallURL: install, bottle: bottle) == nil)
        #expect(executables == ["Workload.exe"])
        #expect(recorder.overrides(for: .program("3DMark.exe"))?["d3d11"] == "n,b")
        #expect(recorder.overrides(for: .program("Workload.exe")) != nil)
        #expect(recorder.overrides(for: .program("Workload.exe"))?["d3d11"] != "n,b")
    }

    @Test("A Chromium host outside the front-end table nobody tuned gets no entry from a Steam launch")
    func untunedChromiumHostIsLeftAlone() async throws {
        let fixture = try make3DMarkBottle(tuning: nil, frontEndName: "Benchmark.exe")
        let (bottle, install, steamExe) = (fixture.bottle, fixture.install, fixture.steamExe)
        let recorder = ScopeRecorder()

        _ = try await Wine.prepareProgramLaunch(
            at: steamExe, args: ["-applaunch", "223850"], bottle: bottle, overridesApplyToDescendants: true,
            descendantExecutables: SteamLauncher.gameExecutables(installURL: install, plan: Self.emptyPlan),
            ownSettingsExecutables: SteamLibrary.scanExecutables(under: install).chromiumHosts,
            recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: true,
            overrideWriter: recorder.writer, importer: recorder.importer
        )

        #expect(!recorder.programScopes.contains("Benchmark.exe"))
        #expect(recorder.programScopes.contains("Workload.exe"))
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
