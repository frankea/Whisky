//
//  SteamClientOrchestrator.swift
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

import Combine
import Foundation

public enum SteamOrchestratorError: LocalizedError, Equatable {
    /// steam.exe did not appear in the process list within the ready timeout.
    case clientTimeout
    /// The bottle no longer contains a Steam installation.
    case steamNotInstalled

    public var errorDescription: String? {
        switch self {
        case .clientTimeout:
            String(localized: "steam.client.timeout")
        case .steamNotInstalled:
            String(localized: "steam.client.missing")
        }
    }
}

/// Runs Steam games through the Windows Steam client without making the user
/// look at it: ensures the client is up (silently), fires `-applaunch`, and
/// watches for the game process to actually appear.
///
/// The side effects go through a ``SteamClientDriver``; this type owns the
/// sequencing. Three pieces of it are the reason it lives in the kit:
///
/// - **Single-flight client startup.** Concurrent launches await one startup
///   attempt instead of each racing to start their own client.
/// - **Per-game phases.** The launch grace period runs for up to two minutes,
///   and starting a second game while the first precompiles shaders is normal.
/// - **One short-lived process snapshot.** The launch watch polls every 2s and
///   the status poller every 10s; sharing a snapshot stops them each running
///   their own `tasklist.exe`, and concurrent reads coalesce into one.
@MainActor
public final class SteamClientOrchestrator: ObservableObject {
    public enum Phase: Equatable, Sendable {
        case startingClient
        case launching
    }

    /// The waits and intervals, injectable so tests do not sit through them.
    public struct Timing: Sendable {
        /// How long to wait for steam.exe after starting the client.
        public var clientReadyTimeout: TimeInterval = 90
        /// Steam forks the game and the -applaunch invocation returns
        /// immediately; shader precompilation can hold the real game process
        /// back for a long time. Lutris ships 120 seconds for this same wait.
        public var launchGrace: TimeInterval = 120
        /// How often a wait re-reads the process list.
        public var pollInterval: Duration = .seconds(2)
        /// How often running-state tracking re-reads the process list.
        public var trackingInterval: Duration = .seconds(10)
        /// How long one process snapshot answers for.
        public var snapshotLifetime: TimeInterval = 1

        public init(
            clientReadyTimeout: TimeInterval = 90,
            launchGrace: TimeInterval = 120,
            pollInterval: Duration = .seconds(2),
            trackingInterval: Duration = .seconds(10),
            snapshotLifetime: TimeInterval = 1
        ) {
            self.clientReadyTimeout = clientReadyTimeout
            self.launchGrace = launchGrace
            self.pollInterval = pollInterval
            self.trackingInterval = trackingInterval
            self.snapshotLifetime = snapshotLifetime
        }
    }

    /// Where each in-flight launch is, keyed by App ID.
    @Published public private(set) var phases: [Int: Phase] = [:]
    /// App IDs whose executables are currently in the bottle's process list.
    @Published public private(set) var runningAppIds: Set<Int> = []
    @Published public var launchError: String?

    let bottle: Bottle
    let driver: SteamClientDriver
    let timing: Timing

    private var trackingTask: Task<Void, Never>?
    private var executableNamesByAppId: [Int: Set<String>] = [:]
    /// The in-flight client startup, shared by every concurrent launch.
    private var clientStartup: Task<Void, Error>?
    private var launchTasks: [Int: Task<Void, Never>] = [:]
    var processSnapshot: (processes: [WineProcess], taken: Date)?
    var snapshotRead: Task<[WineProcess], Never>?

    private lazy var watch = SteamProcessWatch(pollInterval: timing.pollInterval) { [weak self] in
        await self?.runningImageNames() ?? []
    }

    /// - Parameters:
    ///   - bottle: The bottle whose Steam client this drives.
    ///   - driver: The side-effect boundary; defaults to Wine.
    ///   - timing: Waits and intervals; defaults are the production values.
    public init(bottle: Bottle, driver: SteamClientDriver? = nil, timing: Timing = Timing()) {
        self.bottle = bottle
        self.driver = driver ?? WineSteamClientDriver(bottle: bottle)
        self.timing = timing
    }

    /// Launches a game via `-applaunch`, bringing the client up first if needed.
    ///
    /// Owns the task rather than the caller so ``stop()`` can cancel a launch
    /// still inside its grace period.
    public func launch(_ game: SteamGame) {
        guard phases[game.appId] == nil else { return }
        phases[game.appId] = .startingClient
        launchTasks[game.appId] = Task { await performLaunch(game) }
    }

    /// Polls the bottle's process list so the library can show which games
    /// are running, including ones started outside Whisky.
    public func startTracking(games: [SteamGame]) {
        trackingTask?.cancel()
        for game in games where executableNamesByAppId[game.appId] == nil {
            executableNamesByAppId[game.appId] = SteamLibrary.executableNames(under: game.installURL)
        }
        trackingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshRunningState()
                guard let interval = self?.timing.trackingInterval else { return }
                try? await Task.sleep(for: interval)
            }
        }
    }

    /// Asks the game's processes to close, then refreshes the running state.
    public func stop(_ game: SteamGame) async {
        let names = executableNamesByAppId[game.appId]
            ?? SteamLibrary.executableNames(under: game.installURL)

        for process in await runningProcesses()
            where names.contains(process.imageName.lowercased()) {
            await driver.killProcess(winePID: process.winePID)
        }
        processSnapshot = nil
        await refreshRunningState()
    }

    /// Stops process tracking, cancels in-flight launches, and lets the driver
    /// release anything the ready hook started. Call when the owning view
    /// disappears.
    public func stop() {
        trackingTask?.cancel()
        trackingTask = nil
        for task in launchTasks.values {
            task.cancel()
        }
        launchTasks.removeAll()
        clientStartup?.cancel()
        clientStartup = nil
        driver.shutdown()
    }

    /// Whether Play should apply Steam's launcher fixes to this bottle.
    ///
    /// Skipped in manual mode: the user picked that launcher and that compat
    /// setting, and Play must not quietly overrule either. Skipped too when
    /// the bottle is already configured for Steam, so a launch does not
    /// re-persist settings it did not change.
    public static func shouldApplyLauncherFixes(settings: BottleSettings) -> Bool {
        guard settings.launcherMode == .auto else { return false }
        return !(settings.launcherCompatibilityMode && settings.detectedLauncher == .steam)
    }

    // MARK: - Launch sequence

    private func performLaunch(_ game: SteamGame) async {
        defer {
            phases[game.appId] = nil
            launchTasks[game.appId] = nil
        }

        guard let steamRoot = SteamLibrary.detectInstall(bottleURL: bottle.url) else {
            launchError = SteamOrchestratorError.steamNotInstalled.errorDescription
            return
        }
        let steamExe = steamRoot.appending(path: "steam.exe")

        do {
            try await ensureClientRunning(steamExe: steamExe)
        } catch {
            launchError = error.localizedDescription
            return
        }

        phases[game.appId] = .launching
        do {
            try driver.launchGame(game)
        } catch {
            launchError = error.localizedDescription
            return
        }

        if await !waitForGameProcess(installURL: game.installURL) {
            launchError = String(localized: "steam.launch.timeout")
        }
    }

    private func ensureClientRunning(steamExe: URL) async throws {
        if let clientStartup {
            return try await clientStartup.value
        }
        let startup = Task { try await startClient(steamExe: steamExe) }
        clientStartup = startup
        defer { clientStartup = nil }
        try await startup.value
    }

    private func startClient(steamExe: URL) async throws {
        if await isClientRunning() {
            driver.clientDidBecomeReady()
            return
        }

        if Self.shouldApplyLauncherFixes(settings: bottle.settings) {
            driver.applyLauncherFixes()
        }
        driver.startClient(steamExe: steamExe)

        if await watch.waitForAny(of: ["steam.exe"], timeout: timing.clientReadyTimeout) {
            driver.clientDidBecomeReady()
            return
        }
        throw SteamOrchestratorError.clientTimeout
    }

    private func isClientRunning() async -> Bool {
        await runningImageNames().contains("steam.exe")
    }

    /// Waits for any of the game's executables to appear in the process list.
    ///
    /// Returns `true` when the game shows up (or when no candidate exe names
    /// could be determined, in which case there is nothing to watch for).
    private func waitForGameProcess(installURL: URL) async -> Bool {
        let candidates = SteamLibrary.executableNames(under: installURL)
        return await watch.waitForAny(of: candidates, timeout: timing.launchGrace)
    }

    private func refreshRunningState() async {
        runningAppIds = await watch.runningKeys(byExecutables: executableNamesByAppId)
    }
}

// MARK: - Process snapshot

extension SteamClientOrchestrator {
    func runningImageNames() async -> Set<String> {
        guard await driver.hostWineImageNames().isEmpty == false else { return [] }
        return await Set(runningProcesses().map { $0.imageName.lowercased() })
    }

    /// One process list per ``Timing/snapshotLifetime``, and one read at a
    /// time: a caller arriving while a read is in flight awaits that read.
    func runningProcesses() async -> [WineProcess] {
        if let processSnapshot, Date().timeIntervalSince(processSnapshot.taken) < timing.snapshotLifetime {
            return processSnapshot.processes
        }
        if let snapshotRead {
            return await snapshotRead.value
        }

        let read = Task { await driver.processList() }
        snapshotRead = read
        let processes = await read.value
        snapshotRead = nil
        processSnapshot = (processes, Date())
        return processes
    }
}
