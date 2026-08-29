//
//  SteamOrchestratorTestSupport.swift
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

/// A driver that answers from a script of process lists and records every
/// side effect the orchestrator asks for.
@MainActor
final class FakeSteamClientDriver: SteamClientDriver {
    /// Image names per process-list read; the last entry repeats forever.
    var script: [[String]]
    /// When set, what `ps` reports instead of mirroring the script.
    var hostOverride: Set<String>?
    /// Simulated `tasklist.exe` latency, for the coalescing test.
    var listDelay: Duration = .zero
    var onStartClient: (() -> Void)?
    var onLaunchGame: ((SteamGame) -> Void)?
    var launchFailure: Error?

    private(set) var listCalls = 0
    private(set) var hostCalls = 0
    private(set) var startClientCalls = 0
    private(set) var fixesCalls = 0
    private(set) var launched: [Int] = []
    private(set) var killed: [Int32] = []
    private(set) var readyCalls = 0
    private(set) var shutdownCalls = 0

    init(script: [[String]]) {
        self.script = script
    }

    private var current: [String] {
        script.first ?? []
    }

    func hostWineImageNames() async -> Set<String> {
        hostCalls += 1
        return hostOverride ?? Set(current)
    }

    func processList() async -> [WineProcess] {
        listCalls += 1
        if listDelay > .zero {
            try? await Task.sleep(for: listDelay)
        }
        let names = script.count > 1 ? script.removeFirst() : current
        return names.enumerated().map { index, name in
            WineProcess(imageName: name, winePID: Int32(100 + index), memoryUsage: "0", kind: .app)
        }
    }

    func startClient(steamExe _: URL) {
        startClientCalls += 1
        onStartClient?()
    }

    func applyLauncherFixes() {
        fixesCalls += 1
    }

    func launchGame(_ game: SteamGame) throws {
        if let launchFailure {
            throw launchFailure
        }
        launched.append(game.appId)
        onLaunchGame?(game)
    }

    func killProcess(winePID: Int32) async {
        killed.append(winePID)
    }

    func clientDidBecomeReady() {
        readyCalls += 1
    }

    func shutdown() {
        shutdownCalls += 1
    }
}

/// A bottle with a fake Steam install and games, plus timing that does not
/// make the tests sit through production waits.
@MainActor
enum SteamOrchestratorFixture {
    static let fast = SteamClientOrchestrator.Timing(
        clientReadyTimeout: 0.3,
        launchGrace: 0.3,
        pollInterval: .milliseconds(5),
        trackingInterval: .milliseconds(10),
        // Shorter than the launch grace, or a poll answers from the snapshot
        // taken before the game appeared. The snapshot tests pin their own.
        snapshotLifetime: 0.01
    )

    /// Each game gets a `game<N>.exe` in its install directory, so the
    /// orchestrator has an executable name to watch for.
    static func makeBottle(steamInstalled: Bool = true, games: [Int] = [1_086_940]) throws -> (Bottle, [SteamGame]) {
        let fileManager = FileManager.default
        let dir = fileManager.temporaryDirectory.appending(path: UUID().uuidString)
        let steamRoot = dir.appending(path: "drive_c/Program Files (x86)/Steam")
        let steamApps = steamRoot.appending(path: "steamapps")
        try fileManager.createDirectory(at: steamApps, withIntermediateDirectories: true)
        // Enumeration needs the client present; the not-installed case removes it after.
        try Data().write(to: steamRoot.appending(path: "steam.exe"))
        for (index, appId) in games.enumerated() {
            let name = "Game \(index + 1)"
            let installDir = steamApps.appending(path: "common/\(name)")
            try fileManager.createDirectory(at: installDir, withIntermediateDirectories: true)
            try Data().write(to: installDir.appending(path: "game\(index + 1).exe"))
            let acf = """
            "AppState"
            {
                "appid"        "\(appId)"
                "name"        "\(name)"
                "installdir"        "\(name)"
                "StateFlags"        "4"
            }
            """
            try acf.write(to: steamApps.appending(path: "appmanifest_\(appId).acf"), atomically: true, encoding: .utf8)
        }
        let bottle = Bottle(bottleUrl: dir, inFlight: false, isAvailable: true)
        let found = SteamLibrary.enumerate(bottleURL: dir).sorted { $0.appId < $1.appId }
        if !steamInstalled {
            try fileManager.removeItem(at: steamRoot.appending(path: "steam.exe"))
        }
        return (bottle, found)
    }

    /// Waits for `condition` to hold, failing the test if it never does.
    static func eventually(
        _ message: Comment, timeout: Duration = .seconds(3), _ condition: () -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(condition(), message)
    }

    static func awaitIdle(_ orchestrator: SteamClientOrchestrator) async {
        await eventually("launch should finish") { orchestrator.phases.isEmpty }
    }
}
