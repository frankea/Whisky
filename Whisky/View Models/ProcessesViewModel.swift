//
//  ProcessesViewModel.swift
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

import os.log
import SwiftUI
import WhiskyKit

/// Drives the Processes page with hybrid polling, registry merging, and shutdown orchestration.
@MainActor
class ProcessesViewModel: ObservableObject {
    // MARK: - Published State

    /// Merged, sorted process list from tasklist + registry.
    @Published var processes: [WineProcess] = []
    /// Whether the polling loop is active.
    @Published var isPolling: Bool = false
    /// Current shutdown state for UI feedback.
    @Published var shutdownState: ShutdownState = .idle
    /// Filter mode for the process list.
    @Published var filterMode: FilterMode = .appsOnly
    /// Selected Wine PID for table selection.
    @Published var selectedProcessID: Int32?

    // MARK: - Private

    private var pollingTask: Task<Void, Never>?
    private let bottle: Bottle
    private let pollingInterval: TimeInterval = 3.0

    private let logger = Logger(
        subsystem: Bundle.whiskyBundleIdentifier,
        category: "ProcessesViewModel"
    )

    // MARK: - Filter Mode

    /// Controls which processes are shown in the table.
    enum FilterMode: String, CaseIterable {
        /// Show only user applications (ProcessKind.app).
        case appsOnly
        /// Show all processes including services and system.
        case all
    }

    // MARK: - Computed Properties

    /// Processes filtered by the current filter mode.
    var filteredProcesses: [WineProcess] {
        switch filterMode {
        case .appsOnly:
            processes.filter { $0.kind == .app }
        case .all:
            processes
        }
    }

    /// Count of app-kind processes, used for the navigation badge.
    var appCount: Int {
        processes.filter { $0.kind == .app }.count
    }

    // MARK: - Init

    init(bottle: Bottle) {
        self.bottle = bottle
    }

    // MARK: - Polling Lifecycle

    /// Starts the periodic polling loop. Guards against double-start.
    func startPolling() {
        guard pollingTask == nil else { return }
        isPolling = true

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshProcessList()
                try? await Task.sleep(for: .seconds(self?.pollingInterval ?? 3.0))
            }
        }
    }

    /// Stops the polling loop and cleans up.
    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        isPolling = false
    }

    // MARK: - Data Refresh

    /// Fetches the current process list from tasklist.exe, merges with registry data, and updates the published list.
    func refreshProcessList() async {
        // Skip refresh during shutdown to avoid race conditions
        guard shutdownState == .idle else { return }

        do {
            let output = try await Wine.runWine(
                ["tasklist.exe", "/FO", "CSV"],
                bottle: bottle
            )
            var parsed = Wine.parseTasklistOutput(output)

            // Merge with registry data
            let registryProcesses = ProcessRegistry.shared.getProcesses(for: bottle)

            for index in parsed.indices {
                let lowerImageName = parsed[index].imageName.lowercased()
                if let match = registryProcesses.first(where: {
                    $0.programName.lowercased() == lowerImageName
                }) {
                    parsed[index].source = .whisky
                    parsed[index].launchTime = match.launchTime
                    parsed[index].macosPID = match.pid
                }
            }

            // Clean up stale registry entries (in registry but not in tasklist)
            let tasklistNames = Set(parsed.map { $0.imageName.lowercased() })
            for registryEntry in registryProcesses
                where !tasklistNames.contains(registryEntry.programName.lowercased()) {
                ProcessRegistry.shared.unregister(pid: registryEntry.pid)
                logger.debug(
                    "Unregistered stale registry entry: \(registryEntry.programName)"
                )
            }

            // Sort: apps first, then services, then system; alphabetically within each group
            parsed.sort { lhs, rhs in
                let lhsOrder = kindSortOrder(lhs.kind)
                let rhsOrder = kindSortOrder(rhs.kind)
                if lhsOrder != rhsOrder {
                    return lhsOrder < rhsOrder
                }
                return lhs.imageName.localizedCaseInsensitiveCompare(rhs.imageName) == .orderedAscending
            }

            processes = parsed
        } catch {
            logger.error("Failed to refresh process list: \(error.localizedDescription)")
            // Keep previous process list on error
        }
    }

    /// Returns a sort order value for process kind grouping.
    private func kindSortOrder(_ kind: ProcessKind) -> Int {
        switch kind {
        case .app: 0
        case .service: 1
        case .system: 2
        }
    }

    // MARK: - Kill Actions

    /// Gracefully quits a single process via taskkill.exe.
    func quitProcess(_ process: WineProcess) async {
        await Wine.gracefulKillProcess(winePID: process.winePID, bottle: bottle)
        try? await Task.sleep(for: .seconds(1.0))
        await refreshProcessListDuringShutdown()
    }

    /// Force quits a single process via taskkill.exe /F.
    func forceQuitProcess(_ process: WineProcess) async {
        await Wine.forceKillProcess(winePID: process.winePID, bottle: bottle)
        try? await Task.sleep(for: .seconds(0.5))
        await refreshProcessListDuringShutdown()
    }

    // MARK: - Shutdown Orchestration

    /// Executes a 3-step graceful shutdown: per-app kill, wineserver -k, SIGKILL fallback.
    ///
    /// - Returns: The number of processes that were stopped.
    func stopBottle() async -> Int {
        let initialCount = processes.count
        shutdownState = .stopping
        stopPolling()

        // Step 1: Graceful per-app kill
        let appProcesses = processes.filter { $0.kind == .app }
        for process in appProcesses {
            await Wine.gracefulKillProcess(winePID: process.winePID, bottle: bottle)
        }
        try? await Task.sleep(for: .seconds(4.0))

        // Check remaining
        await refreshProcessListDuringShutdown()

        // Step 2: wineserver -k if processes remain
        if !processes.isEmpty {
            shutdownState = .forceKilling
            Wine.killBottle(bottle: bottle)
            try? await Task.sleep(for: .seconds(2.0))
        }

        // Step 3: SIGKILL remaining tracked macOS PIDs as last resort
        let registryEntries = ProcessRegistry.shared.getProcesses(for: bottle)
        for entry in registryEntries where entry.pid > 0 {
            kill(entry.pid, SIGKILL)
            logger.info("Sent SIGKILL to macOS PID \(entry.pid) (\(entry.programName))")
        }

        // Cleanup
        ProcessRegistry.shared.clearRegistry(for: bottle.url)
        shutdownState = .idle
        await refreshProcessListDuringShutdown()
        startPolling()

        let stoppedCount = initialCount - processes.count
        return max(stoppedCount, 0)
    }

    /// Executes a force shutdown: skips graceful step, goes directly to wineserver -k + SIGKILL.
    ///
    /// - Returns: The number of processes that were stopped.
    func forceStopBottle() async -> Int {
        let initialCount = processes.count
        shutdownState = .forceKilling
        stopPolling()

        // Direct to wineserver -k
        Wine.killBottle(bottle: bottle)
        try? await Task.sleep(for: .seconds(2.0))

        // SIGKILL remaining tracked macOS PIDs
        let registryEntries = ProcessRegistry.shared.getProcesses(for: bottle)
        for entry in registryEntries where entry.pid > 0 {
            kill(entry.pid, SIGKILL)
            logger.info("Force sent SIGKILL to macOS PID \(entry.pid) (\(entry.programName))")
        }

        // Cleanup
        ProcessRegistry.shared.clearRegistry(for: bottle.url)
        shutdownState = .idle
        await refreshProcessListDuringShutdown()
        startPolling()

        let stoppedCount = initialCount - processes.count
        return max(stoppedCount, 0)
    }

    // MARK: - Private Helpers

    /// Refreshes the process list bypassing the shutdown guard. Used during shutdown steps.
    private func refreshProcessListDuringShutdown() async {
        let savedState = shutdownState
        shutdownState = .idle
        await refreshProcessList()
        shutdownState = savedState
    }
}
