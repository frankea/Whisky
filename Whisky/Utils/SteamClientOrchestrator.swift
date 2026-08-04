//
//  SteamClientOrchestrator.swift
//  Whisky
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
import WhiskyKit

enum SteamOrchestratorError: LocalizedError {
    /// steam.exe did not appear in the process list within the ready timeout.
    case clientTimeout
    /// The bottle no longer contains a Steam installation.
    case steamNotInstalled

    var errorDescription: String? {
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
@MainActor
final class SteamClientOrchestrator: ObservableObject {
    enum Phase: Equatable {
        case startingClient
        case launching
    }

    /// Where each in-flight launch is, keyed by App ID. Per-game rather than
    /// global: the grace period below runs for up to two minutes, and starting
    /// a second game while the first precompiles shaders is normal.
    @Published private(set) var phases: [Int: Phase] = [:]
    @Published private(set) var downloadStatus: StallStatus = .noDownloads
    /// App IDs whose executables are currently in the bottle's process list.
    @Published private(set) var runningAppIds: Set<Int> = []
    @Published var launchError: String?

    private let bottle: Bottle
    private let downloadMonitor = SteamDownloadMonitor()
    private var cancellables: Set<AnyCancellable> = []
    private var trackingTask: Task<Void, Never>?
    private var executableNamesByAppId: [Int: Set<String>] = [:]
    /// The in-flight client startup, so concurrent launches await one attempt
    /// instead of each racing to start their own client.
    private var clientStartup: Task<Void, Error>?
    private var launchTasks: [Int: Task<Void, Never>] = [:]
    /// The launch watch polls every 2s and the status poller every 10s; sharing
    /// one short-lived snapshot stops them each running their own tasklist.exe.
    private var processSnapshot: (processes: [WineProcess], taken: Date)?
    private var snapshotRead: Task<[WineProcess], Never>?
    private let snapshotLifetime: TimeInterval = 1

    private lazy var watch = SteamProcessWatch(pollInterval: .seconds(2)) { [weak self] in
        await self?.runningImageNames() ?? []
    }

    private let clientReadyTimeout: TimeInterval = 90
    /// Steam forks the game and the -applaunch invocation returns immediately;
    /// shader precompilation can hold the real game process back for a long
    /// time. Lutris ships 120 seconds for this same wait.
    private let launchGrace: TimeInterval = 120

    init(bottle: Bottle) {
        self.bottle = bottle
        downloadMonitor.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] status in self?.downloadStatus = status }
            .store(in: &cancellables)
    }

    /// Launches a game via `-applaunch`, bringing the client up first if needed.
    ///
    /// Owns the task rather than the caller so ``stop()`` can cancel a launch
    /// still inside its grace period.
    func launch(_ game: SteamGame) {
        guard phases[game.appId] == nil else { return }
        phases[game.appId] = .startingClient
        launchTasks[game.appId] = Task { await performLaunch(game) }
    }

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
        // Shared with `whisky launch`: resolves the GameDB profile and the
        // user's overrides, records the bottle for this App ID, and hands
        // -applaunch to the client. The returned task can outlive the game, so
        // it is never awaited. installURL is already known here, which saves
        // the launcher a library rescan.
        do {
            try SteamLauncher.launch(
                appId: game.appId, bottle: bottle, installURL: game.installURL
            )
        } catch {
            launchError = error.localizedDescription
            return
        }

        if await !waitForGameProcess(installURL: game.installURL) {
            launchError = String(localized: "steam.launch.timeout")
        }
    }

    /// Polls the bottle's process list so the library can show which games
    /// are running, including ones started outside Whisky.
    func startTracking(games: [SteamGame]) {
        trackingTask?.cancel()
        for game in games where executableNamesByAppId[game.appId] == nil {
            let installURL = game.installURL
            executableNamesByAppId[game.appId] = SteamLibrary.executableNames(under: installURL)
        }
        trackingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshRunningState()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    /// Asks the game's processes to close, then refreshes the running state.
    func stop(_ game: SteamGame) async {
        let names = executableNamesByAppId[game.appId]
            ?? SteamLibrary.executableNames(under: game.installURL)

        for process in await runningProcesses()
            where names.contains(process.imageName.lowercased()) {
            await Wine.gracefulKillProcess(winePID: process.winePID, bottle: bottle)
        }
        processSnapshot = nil
        await refreshRunningState()
    }

    private func refreshRunningState() async {
        runningAppIds = await watch.runningKeys(byExecutables: executableNamesByAppId)
    }

    /// Stops download monitoring and process tracking. Call when the owning
    /// view disappears.
    func stop() {
        trackingTask?.cancel()
        trackingTask = nil
        for task in launchTasks.values {
            task.cancel()
        }
        launchTasks.removeAll()
        clientStartup?.cancel()
        clientStartup = nil
        downloadMonitor.stopMonitoring()
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
            startDownloadMonitoringIfNeeded()
            return
        }

        applySteamLauncherFixes()

        let bottle = self.bottle
        // steam.exe -silent runs for the whole session -- never await it.
        Task {
            _ = try? await Wine.runProgram(at: steamExe, args: ["-silent"], bottle: bottle)
        }

        if await watch.waitForAny(of: ["steam.exe"], timeout: clientReadyTimeout) {
            startDownloadMonitoringIfNeeded()
            return
        }
        throw SteamOrchestratorError.clientTimeout
    }

    /// Applies Steam's launcher fixes through the shared path, which carries the
    /// locale, DXVK and GPU-spoofing settings steamwebhelper needs and not just
    /// the compat flag.
    ///
    /// Skipped in manual mode: the user picked that launcher and that compat
    /// setting, and Play must not quietly overrule either.
    private func applySteamLauncherFixes() {
        guard bottle.settings.launcherMode == .auto else { return }
        guard !(bottle.settings.launcherCompatibilityMode
            && bottle.settings.detectedLauncher == .steam)
        else { return }
        LauncherFixes.apply(to: bottle, launcher: .steam)
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
        return await watch.waitForAny(of: candidates, timeout: launchGrace)
    }

    private func startDownloadMonitoringIfNeeded() {
        guard !downloadMonitor.isMonitoring else { return }
        downloadMonitor.startMonitoring(bottleURL: bottle.url, detectedLauncher: .steam)
    }

    private func runningImageNames() async -> Set<String> {
        await Set(runningProcesses().map { $0.imageName.lowercased() })
    }

    private func runningProcesses() async -> [WineProcess] {
        if let processSnapshot, Date().timeIntervalSince(processSnapshot.taken) < snapshotLifetime {
            return processSnapshot.processes
        }
        if let snapshotRead {
            return await snapshotRead.value
        }

        let read = Task { await readProcessList() }
        snapshotRead = read
        let processes = await read.value
        snapshotRead = nil
        processSnapshot = (processes, Date())
        return processes
    }

    private func readProcessList() async -> [WineProcess] {
        guard let output = try? await Wine.runWine(["tasklist.exe", "/FO", "CSV"], bottle: bottle) else {
            return []
        }
        return Wine.parseTasklistOutput(output)
    }
}
