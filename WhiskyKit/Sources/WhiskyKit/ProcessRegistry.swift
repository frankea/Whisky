//
//  ProcessRegistry.swift
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

import Foundation
import os.log

/// Registry for tracking Wine processes launched by Whisky.
///
/// This singleton maintains a thread-safe mapping of active Wine processes
/// to their associated bottles, enabling automatic cleanup on app termination.
/// It supports both graceful shutdown (SIGTERM) and force kill (SIGKILL)
/// operations with configurable timeouts.
///
/// ## Usage
///
/// ```swift
/// // Register a process when launching
/// ProcessRegistry.shared.register(process: wineProcess, bottle: bottle, programName: "game.exe")
///
/// // Clean up processes when app terminates
/// await ProcessRegistry.shared.cleanupAll(force: false)
/// ```
public final class ProcessRegistry: @unchecked Sendable {
    static let shared = ProcessRegistry()

    private let lock = NSLock()
    private var activeProcesses: [URL: Set<ProcessInfo>] = [:]

    private let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "ProcessRegistry")

    /// Information about a tracked Wine process.
    public struct ProcessInfo: Hashable, Sendable {
        /// Process ID (may be 0 if not yet launched)
        public let pid: Int32
        /// When the process was launched
        public let launchTime: Date
        /// URL of the bottle containing this process
        public let bottleURL: URL
        /// Name of the program/executable
        public let programName: String

        public func hash(into hasher: inout Hasher) {
            hasher.combine(pid)
            hasher.combine(launchTime)
            hasher.combine(bottleURL)
            hasher.combine(programName)
        }

        public static func == (lhs: ProcessInfo, rhs: ProcessInfo) -> Bool {
            lhs.pid == rhs.pid &&
                lhs.launchTime == rhs.launchTime &&
                lhs.bottleURL == rhs.bottleURL &&
                lhs.programName == rhs.programName
        }
    }

    private init() {}

    // MARK: - Registration

    /// Registers a Wine process for tracking.
    ///
    /// This method should be called before launching a Wine process.
    /// The PID will be updated after the process starts.
    ///
    /// - Parameters:
    ///   - process: The Process object (may not have PID yet)
    ///   - bottle: The Bottle containing this process
    ///   - programName: Name of the program being launched
    public func register(process: Process, bottle: Bottle, programName: String) {
        lock.lock()
        defer { lock.unlock() }

        let info = ProcessInfo(
            pid: 0, // Will be updated after launch
            launchTime: Date(),
            bottleURL: bottle.url,
            programName: programName
        )

        var processes = activeProcesses[bottle.url] ?? Set()
        processes.insert(info)
        activeProcesses[bottle.url] = processes

        logger.info("Registered process '\(programName)' for bottle '\(bottle.url.lastPathComponent)'")
    }

    /// Updates the PID for a registered process.
    ///
    /// This should be called after the process has launched and the PID is known.
    ///
    /// - Parameter pid: The actual process ID
    public func updatePID(pid: Int32, for process: Process) {
        lock.lock()
        defer { lock.unlock() }

        // Find and update the process with PID 0
        for (bottleURL, processes) in activeProcesses {
            for info in processes where info.pid == 0 {
                var mutableProcesses = processes
                mutableProcesses.remove(info)
                let updatedInfo = ProcessInfo(
                    pid: pid,
                    launchTime: info.launchTime,
                    bottleURL: info.bottleURL,
                    programName: info.programName
                )
                mutableProcesses.insert(updatedInfo)
                activeProcesses[bottleURL] = mutableProcesses

                logger.debug("Updated PID for process '\(info.programName)' to \(pid)")
                return
            }
        }
    }

    /// Unregisters a process by PID.
    ///
    /// This should be called when a process terminates normally.
    ///
    /// - Parameter pid: The process ID to unregister
    public func unregister(pid: Int32) {
        lock.lock()
        defer { lock.unlock() }

        for (bottleURL, processes) in activeProcesses {
            for info in processes where info.pid == pid {
                var mutableProcesses = processes
                mutableProcesses.remove(info)
                activeProcesses[bottleURL] = mutableProcesses

                logger.info("Unregistered process '\(info.programName)' (PID: \(pid))")
                return
            }
        }
    }

    // MARK: - Querying

    /// Returns all active processes for a specific bottle.
    ///
    /// - Parameter bottle: The bottle to query
    /// - Returns: Array of ProcessInfo for the bottle
    public func getProcesses(for bottle: Bottle) -> [ProcessInfo] {
        lock.lock()
        defer { lock.unlock() }
        return Array(activeProcesses[bottle.url] ?? Set())
    }

    /// Returns all active processes across all bottles.
    ///
    /// - Returns: Dictionary mapping bottle URLs to process sets
    public func getAllProcesses() -> [URL: Set<ProcessInfo>] {
        lock.lock()
        defer { lock.unlock() }
        return activeProcesses
    }

    // MARK: - Cleanup

    /// Cleans up all processes across all bottles.
    ///
    /// This method attempts graceful shutdown first (SIGTERM), waits for a timeout,
    /// then optionally force kills (SIGKILL) if processes are still running.
    ///
    /// - Parameters:
    ///   - bottles: Array of bottles to check for processes to clean up
    ///   - force: If true, force kills processes after timeout. If false, only attempts graceful shutdown.
    public func cleanupAll(bottles: [Bottle], force: Bool) async {
        let allProcesses = getAllProcesses()

        for (bottleURL, _) in allProcesses {
            guard let bottle = bottles.first(where: { $0.url == bottleURL }) else {
                logger.warning("Bottle not found for cleanup: \(bottleURL.path)")
                continue
            }

            await cleanup(for: bottle, force: force)
        }
    }

    /// Cleans up processes for a specific bottle.
    ///
    /// This method sends SIGTERM to all processes, waits for them to terminate,
    /// and optionally sends SIGKILL if force is enabled and processes are still running.
    ///
    /// - Parameters:
    ///   - bottle: The bottle to clean up
    ///   - force: If true, force kill after timeout
    public func cleanup(for bottle: Bottle, force: Bool) async {
        let processes = getProcesses(for: bottle)

        guard !processes.isEmpty else {
            logger.debug("No processes to clean up for bottle '\(bottle.url.lastPathComponent)'")
            return
        }

        logger.info("Cleaning up \(processes.count) process(es) for bottle '\(bottle.url.lastPathComponent)'")

        // Send SIGTERM for graceful shutdown
        for process in processes where process.pid > 0 {
            killProcess(process.pid, signal: SIGTERM)
            logger.debug("Sent SIGTERM to process '\(process.programName)' (PID: \(process.pid))")
        }

        // Wait for processes to terminate
        try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds

        // Check if processes are still running
        let remainingProcesses = getProcesses(for: bottle).filter { $0.pid > 0 }

        if !remainingProcesses.isEmpty, force {
            logger
                .warning(
                    "Force killing \(remainingProcesses.count) process(es) for bottle '\(bottle.url.lastPathComponent)'"
                )

            // Send SIGKILL for force termination
            for process in remainingProcesses {
                killProcess(process.pid, signal: SIGKILL)
                logger.debug("Sent SIGKILL to process '\(process.programName)' (PID: \(process.pid))")
            }

            // Wait for force kill to complete
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        }

        // Clear registry for this bottle
        clearRegistry(for: bottle.url)

        logger.info("Completed cleanup for bottle '\(bottle.url.lastPathComponent)'")
    }

    /// Clears the registry for a specific bottle URL.
    ///
    /// - Parameter bottleURL: The bottle URL to clear
    private func clearRegistry(for bottleURL: URL) {
        lock.lock()
        activeProcesses[bottleURL] = nil
        lock.unlock()
    }

    /// Kills a process by sending the specified signal.
    ///
    /// - Parameters:
    ///   - pid: Process ID to kill
    ///   - signal: Signal to send (SIGTERM or SIGKILL)
    private func killProcess(_ pid: Int32, signal: Int32) {
        let result = kill(pid, signal)
        if result != 0, errno != ESRCH {
            // ESRCH means process doesn't exist, which is expected
            logger.error("Failed to send signal \(signal) to PID \(pid): \(String(cString: strerror(errno)))")
        }
    }

    // MARK: - Testing Support

    /// Resets the registry to empty state. For testing purposes only.
    public func reset() {
        lock.lock()
        activeProcesses.removeAll()
        lock.unlock()
    }
}
