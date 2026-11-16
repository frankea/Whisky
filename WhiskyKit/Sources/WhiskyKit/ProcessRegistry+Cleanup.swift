//
//  ProcessRegistry+Cleanup.swift
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

public extension ProcessRegistry {
    /// Cleans up all processes across all bottles.
    ///
    /// This method attempts graceful shutdown first (SIGTERM), waits for a timeout,
    /// then optionally force kills (SIGKILL) if processes are still running.
    ///
    /// - Parameters:
    ///   - bottles: Array of bottles to check for processes to clean up
    ///   - force: If true, force kills processes after timeout. If false, only attempts graceful shutdown.
    func cleanupAll(bottles: [Bottle], force: Bool) async {
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
    func cleanup(for bottle: Bottle, force: Bool) async {
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

        // Check if processes are still running. Use kill(pid, 0) to verify
        // OS-level liveness so already-exited processes don't receive SIGKILL.
        let remainingProcesses = getProcesses(for: bottle).filter { Self.isAlive(pid: $0.pid) }

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
}

private extension ProcessRegistry {
    /// Kills a process by sending the specified signal.
    ///
    /// - Parameters:
    ///   - pid: Process ID to kill
    ///   - signal: Signal to send (SIGTERM or SIGKILL)
    func killProcess(_ pid: Int32, signal: Int32) {
        let result = kill(pid, signal)
        if result != 0, errno != ESRCH {
            // ESRCH means process doesn't exist, which is expected
            logger.error("Failed to send signal \(signal) to PID \(pid): \(String(cString: strerror(errno)))")
        }
    }

    /// Returns whether a PID currently corresponds to a running process.
    ///
    /// Sends signal 0, which performs error checking without delivering a signal.
    /// `ESRCH` means the process is gone; any other result (including `EPERM`)
    /// means it is still around.
    static func isAlive(pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno != ESRCH
    }
}
