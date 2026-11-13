//
//  TroubleshootingPreflightTests.swift
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

@testable import WhiskyKit
import XCTest

/// The preflight snapshot the wizard collects, and the backend fix writing
/// where the backend a launch uses is set. Nothing here probes the machine:
/// the audio device and the Recommended backend are injected.
@MainActor
final class TroubleshootingPreflightTests: XCTestCase {
    private var tempDir: URL!
    private var bottle: Bottle!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appending(path: "Preflight-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        bottle = Bottle(bottleUrl: tempDir, inFlight: false, isAvailable: true)
    }

    override func tearDownWithError() throws {
        bottle = nil
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        tempDir = nil
    }

    private func makeProgram(_ relativePath: String) throws -> Program {
        let url = tempDir.appending(path: relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: url)
        return Program(url: url, bottle: bottle, peFile: nil)
    }

    private func setOverride(_ backend: GraphicsBackend?, on program: Program) {
        var overrides = program.settings.overrides ?? ProgramOverrides()
        overrides.graphicsBackend = backend
        program.settings.overrides = overrides
    }

    private static let fakeDevice = AudioDeviceInfo(
        name: "Test Speakers", transportType: .usb, sampleRate: 48_000, outputChannelCount: 2, isDefault: true
    )

    // MARK: - Collection

    func testInputsTakeTheLauncherFromTheBottleWhenTheProgramIsNone() throws {
        bottle.settings.detectedLauncher = .eaApp
        let game = try makeProgram("drive_c/Games/game.exe")

        let inputs = PreflightCollector.inputs(bottle: bottle, program: game, programURL: nil)

        XCTAssertEqual(inputs.launcherType, .eaApp)
        XCTAssertEqual(inputs.programURL, game.url)
    }

    func testInputsPreferTheProgramsOwnLauncher() throws {
        bottle.settings.detectedLauncher = .eaApp
        let steam = try makeProgram("drive_c/Program Files (x86)/Steam/steam.exe")

        let inputs = PreflightCollector.inputs(bottle: bottle, program: steam, programURL: nil)

        XCTAssertEqual(inputs.launcherType, .steam)
    }

    func testGatherFillsTheSnapshot() throws {
        let game = try makeProgram("drive_c/Games/game.exe")
        setOverride(.dxmt, on: game)
        bottle.settings.graphicsBackend = .recommended
        bottle.settings.detectedLauncher = .steam

        let logsFolder = tempDir.appending(path: "Logs")
        try FileManager.default.createDirectory(at: logsFolder, withIntermediateDirectories: true)
        var entry = RunLogEntry(programName: "game.exe", logFileName: "run.log")
        entry.exitCode = 3
        var history = RunLogHistory()
        _ = history.append(entry)
        RunLogStore.save(history, for: "game.exe", in: tempDir)
        try Data("log".utf8).write(to: logsFolder.appending(path: "run.log"))

        let inputs = PreflightCollector.inputs(bottle: bottle, program: game, programURL: nil)
        let preflight = PreflightCollector.gather(
            inputs, logsFolder: logsFolder, audioDevice: { Self.fakeDevice }, recommendedBackend: { _ in .d3dMetal }
        )

        XCTAssertEqual(preflight.launcherType, LauncherType.steam.rawValue)
        XCTAssertEqual(preflight.recentLogURL, logsFolder.appending(path: "run.log"))
        XCTAssertEqual(preflight.lastExitCode, 3)
        XCTAssertEqual(preflight.audioDeviceName, "Test Speakers")
        XCTAssertEqual(preflight.audioTransportType, AudioTransportType.usb.exportName)
        XCTAssertEqual(preflight.audioSampleRate, 48_000)
        XCTAssertEqual(preflight.graphicsBackend, "dxmt", "the program's override is what a launch uses")
        XCTAssertEqual(preflight.bottleGraphicsBackend, "d3dMetal")
        XCTAssertEqual(preflight.programName, "game.exe")
    }

    func testGatherReadsThePersistedOverrideWithoutAProgram() throws {
        let game = try makeProgram("drive_c/Games/game.exe")
        setOverride(.wined3d, on: game)
        bottle.settings.graphicsBackend = .dxvk

        let inputs = PreflightCollector.inputs(bottle: bottle, program: nil, programURL: game.url)
        let preflight = PreflightCollector.gather(
            inputs, logsFolder: tempDir, audioDevice: { nil }, recommendedBackend: { _ in .d3dMetal }
        )

        XCTAssertEqual(preflight.graphicsBackend, "wined3d")
        XCTAssertEqual(preflight.bottleGraphicsBackend, "dxvk")
        XCTAssertNil(preflight.audioDeviceName)
        XCTAssertNil(preflight.recentLogURL)
    }

    func testRecentRunWithoutAProgramTakesTheNewestInTheBottle() throws {
        var older = RunLogEntry(programName: "a.exe", logFileName: "a.log")
        older.exitCode = 1
        var olderHistory = RunLogHistory()
        _ = olderHistory.append(older)
        RunLogStore.save(olderHistory, for: "a.exe", in: tempDir)

        var newer = RunLogEntry(programName: "b.exe", logFileName: "b.log")
        newer.exitCode = 2
        var newerHistory = RunLogHistory()
        _ = newerHistory.append(newer)
        RunLogStore.save(newerHistory, for: "b.exe", in: tempDir)

        let run = PreflightCollector.recentRun(programName: nil, bottleURL: tempDir, logsFolder: tempDir)

        XCTAssertEqual(run.exitCode, 2)
        XCTAssertNil(run.logURL, "a deleted log is not offered")
    }

    func testResolvedBackendsFollowTheLaunch() {
        let recommended: (LauncherType?) -> GraphicsBackend = { $0 == nil ? .d3dMetal : .dxvk }
        let game = URL(filePath: "/b/drive_c/Games/game.exe")
        let steam = URL(filePath: "/b/drive_c/Program Files (x86)/Steam/steam.exe")

        let plain = PreflightCollector.resolvedBackends(
            bottle: .recommended, programOverride: nil, programURL: game, recommended: recommended
        )
        XCTAssertEqual(plain.effective, .d3dMetal)
        XCTAssertEqual(plain.bottle, .d3dMetal)

        let launcher = PreflightCollector.resolvedBackends(
            bottle: .recommended, programOverride: nil, programURL: steam, recommended: recommended
        )
        XCTAssertEqual(launcher.effective, .dxvk, "Recommended steers a launcher to DXVK")

        let overridden = PreflightCollector.resolvedBackends(
            bottle: .dxmt, programOverride: .wined3d, programURL: game, recommended: recommended
        )
        XCTAssertEqual(overridden.effective, .wined3d)
        XCTAssertEqual(overridden.bottle, .dxmt)
    }

    func testWineserverStateReplacesOnlyThatField() {
        let preflight = PreflightData(
            bottleURL: tempDir, bottleName: "B", launcherType: "Steam", isWineserverRunning: false,
            processCount: 2, audioSampleRate: 44_100, graphicsBackend: "dxvk", bottleGraphicsBackend: "dxmt"
        )

        let running = preflight.with(isWineserverRunning: true)

        XCTAssertTrue(running.isWineserverRunning)
        XCTAssertEqual(running.launcherType, "Steam")
        XCTAssertEqual(running.processCount, 2)
        XCTAssertEqual(running.audioSampleRate, 44_100)
        XCTAssertEqual(running.bottleGraphicsBackend, "dxmt")
    }

    func testSnapshotsSavedBeforeTheNewFieldsStillDecode() throws {
        let legacy = """
        {"bottleURL":"file:///tmp/b","bottleName":"B","isWineserverRunning":false,"processCount":0,\
        "graphicsBackend":"dxvk","collectedAt":0}
        """
        let preflight = try JSONDecoder().decode(PreflightData.self, from: Data(legacy.utf8))

        XCTAssertNil(preflight.bottleGraphicsBackend)
        XCTAssertNil(preflight.audioSampleRate)
    }

    // MARK: - Backend fix scope

    func testSwitchBackendChangesTheProgramOverrideWhenOneIsSet() throws {
        bottle.settings.graphicsBackend = .recommended
        let game = try makeProgram("drive_c/Games/game.exe")
        setOverride(.d3dMetal, on: game)

        let preview = try XCTUnwrap(FixApplicator.preview(
            fixId: "switch-backend", params: ["backend": "dxvk"], bottle: bottle, program: game
        ))
        XCTAssertEqual(preview.scope, "program")
        XCTAssertEqual(preview.currentValue, GraphicsBackend.d3dMetal.displayName)

        let attempt = FixApplicator.apply(
            fixId: "switch-backend", params: ["backend": "dxvk"], bottle: bottle, program: game
        )
        XCTAssertEqual(game.settings.overrides?.graphicsBackend, .dxvk)
        XCTAssertEqual(bottle.settings.graphicsBackend, .recommended, "the bottle was not where the value lived")
        XCTAssertEqual(attempt.beforeValue, "d3dMetal")
        XCTAssertEqual(attempt.params?["scope"], "program")

        XCTAssertTrue(FixApplicator.undo(attempt: attempt, bottle: bottle, program: game))
        XCTAssertEqual(game.settings.overrides?.graphicsBackend, .d3dMetal)
    }

    func testSwitchBackendChangesTheBottleWithoutAnOverride() throws {
        bottle.settings.graphicsBackend = .d3dMetal
        let game = try makeProgram("drive_c/Games/game.exe")

        let preview = try XCTUnwrap(FixApplicator.preview(
            fixId: "switch-backend", params: ["backend": "dxvk"], bottle: bottle, program: game
        ))
        let attempt = FixApplicator.apply(
            fixId: "switch-backend", params: ["backend": "dxvk"], bottle: bottle, program: game
        )

        XCTAssertEqual(preview.scope, "bottle")
        XCTAssertEqual(bottle.settings.graphicsBackend, .dxvk)
        XCTAssertNil(game.settings.overrides?.graphicsBackend)
        XCTAssertEqual(attempt.params?["scope"], "bottle")
        XCTAssertTrue(FixApplicator.undo(attempt: attempt, bottle: bottle, program: game))
        XCTAssertEqual(bottle.settings.graphicsBackend, .d3dMetal)
    }

    func testUndoingAProgramSwitchWithoutTheProgramFails() {
        let attempt = FixAttempt(
            fixId: "switch-backend", beforeValue: "dxmt", afterValue: "dxvk", result: .applied,
            params: ["backend": "dxvk", "scope": "program"]
        )

        XCTAssertFalse(FixApplicator.undo(attempt: attempt, bottle: bottle, program: nil))
    }

    func testLauncherFixesFallBackToTheBottlesLauncher() throws {
        bottle.settings.detectedLauncher = .steam

        let preview = try XCTUnwrap(FixApplicator.preview(
            fixId: "apply-launcher-fixes", params: [:], bottle: bottle, program: nil
        ))

        XCTAssertEqual(preview.currentValue, LauncherType.steam.displayName)
    }

    // MARK: - Enhanced sync fix

    func testEnhancedSyncPreviewKeepsAnEnabledModeAndTurnsOnMSync() throws {
        let expected: [EnhancedSync: String] = [
            .none: String(localized: "config.enhancedSync.msync"),
            .esync: String(localized: "config.enhancedSync.esync"),
            .msync: String(localized: "config.enhancedSync.msync")
        ]
        for (mode, newValue) in expected {
            bottle.settings.enhancedSync = mode
            let preview = try XCTUnwrap(FixApplicator.preview(
                fixId: "enable-esync", params: [:], bottle: bottle, program: nil
            ))
            XCTAssertEqual(preview.newValue, newValue, "\(mode)")
        }
    }
}
