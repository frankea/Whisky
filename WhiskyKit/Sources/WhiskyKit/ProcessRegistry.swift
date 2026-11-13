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
import IOKit.pwr_mgt
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
    public static let shared = ProcessRegistry()

    /// Posted on the main thread whenever a bottle's tracked processes or launch
    /// session change. `userInfo[bottleURLKey]` holds the bottle's URL.
    public static let didChangeNotification = Notification.Name("com.franke.Whisky.processRegistryDidChange")
    /// The `userInfo` key of ``didChangeNotification`` that holds the bottle URL.
    public static let bottleURLKey = "bottleURL"

    private let lock = NSLock()
    private var activeProcesses: [URL: Set<ProcessInfo>] = [:]

    /// When Whisky last launched something in each bottle during this run of
    /// the app. A bottle is in here from its first launch until its wineserver
    /// is seen idle (``endSession(for:)``), which is what tells a game Whisky
    /// started apart from a wineserver nobody here started. Not persisted: after
    /// a restart, whatever is still running is no longer this run's.
    private var lastLaunches: [URL: Date] = [:]

    /// IOKit power assertion held while at least one Wine process is registered.
    /// Prevents the screen saver and display sleep during gaming sessions where
    /// only a controller is generating input (whisky-app/whisky#547).
    private var displayWakeAssertion: IOPMAssertionID = .init(0)

    let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "ProcessRegistry")

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
        let info = ProcessInfo(
            pid: 0, // Will be updated after launch
            launchTime: Date(),
            bottleURL: bottle.url,
            programName: programName,
            processIdentity: ObjectIdentifier(process)
        )

        var processes = activeProcesses[bottle.url] ?? Set()
        processes.insert(info)
        activeProcesses[bottle.url] = processes
        lastLaunches[bottle.url] = info.launchTime

        ensureDisplayWakeAssertionLocked()
        lock.unlock()

        logger.info("Registered process '\(programName)' for bottle '\(bottle.url.lastPathComponent)'")
        // After unlocking: on the main thread observers run inside the post and
        // query the registry, which would wait on the lock forever.
        postChange(for: bottle.url)
    }

    /// Records that Whisky started something in a bottle without a process to track.
    ///
    /// For launches that block until they finish, such as a batch file or
    /// `winecfg`: there is no program entry to show, but the bottle's wineserver
    /// is Whisky's doing and must not read as orphaned.
    ///
    /// - Parameters:
    ///   - bottleURL: The bottle the launch runs in.
    ///   - date: When it was launched.
    public func noteLaunch(bottleURL: URL, at date: Date = Date()) {
        lock.lock()
        lastLaunches[bottleURL] = date
        lock.unlock()
        postChange(for: bottleURL)
    }

    /// Updates the PID for a registered process.
    ///
    /// This should be called after the process has launched and the PID is known.
    ///
    /// - Parameter pid: The actual process ID
    public func updatePID(pid: Int32, for process: Process) {
        lock.lock()
        defer { lock.unlock() }

        let identity = ObjectIdentifier(process)

        for (bottleURL, processes) in activeProcesses {
            for info in processes where info.processIdentity == identity {
                var mutableProcesses = processes
                mutableProcesses.remove(info)
                let updatedInfo = ProcessInfo(
                    pid: pid,
                    launchTime: info.launchTime,
                    bottleURL: info.bottleURL,
                    programName: info.programName,
                    processIdentity: info.processIdentity
                )
                mutableProcesses.insert(updatedInfo)
                activeProcesses[bottleURL] = mutableProcesses

                logger.debug("Updated PID for process '\(info.programName)' to \(pid)")
                return
            }
        }

        logger.warning("updatePID called for unregistered Process (pid: \(pid))")
    }

    /// Unregisters a process by PID.
    ///
    /// This should be called when a process terminates normally.
    ///
    /// - Parameter pid: The process ID to unregister
    public func unregister(pid: Int32) {
        lock.lock()
        var removed: ProcessInfo?
        search: for (bottleURL, processes) in activeProcesses {
            for info in processes where info.pid == pid {
                var mutableProcesses = processes
                mutableProcesses.remove(info)
                activeProcesses[bottleURL] = mutableProcesses
                releaseDisplayWakeAssertionIfIdleLocked()
                removed = info
                break search
            }
        }
        lock.unlock()

        guard let removed else { return }
        logger.info("Unregistered process '\(removed.programName)' (PID: \(pid))")
        postChange(for: removed.bottleURL)
    }

    /// Unregisters exactly one entry, as ``getProcesses(for:)`` returned it.
    ///
    /// Unlike ``unregister(pid:)`` this cannot hit another entry: once a
    /// launcher process has exited its entry's PID is 0, which many share.
    ///
    /// - Parameter entry: The entry to remove.
    public func unregister(_ entry: ProcessInfo) {
        removeEntries(in: entry.bottleURL) { $0 == entry }
    }

    /// Unregisters the entry registered for `process`, as when it failed to start.
    ///
    /// - Parameter process: The process passed to ``register(process:bottle:programName:)``.
    public func unregister(process: Process) {
        let identity = ObjectIdentifier(process)
        let bottleURLs = getAllProcesses().compactMap { url, entries in
            entries.contains { $0.processIdentity == identity } ? url : nil
        }
        for bottleURL in bottleURLs {
            removeEntries(in: bottleURL) { $0.processIdentity == identity }
        }
    }

    /// Removes the entries of one bottle that match, then reports the change.
    private func removeEntries(in bottleURL: URL, where matches: (ProcessInfo) -> Bool) {
        lock.lock()
        let before = activeProcesses[bottleURL] ?? Set()
        let after = before.filter { !matches($0) }
        activeProcesses[bottleURL] = after.isEmpty ? nil : after
        releaseDisplayWakeAssertionIfIdleLocked()
        lock.unlock()
        if after.count != before.count {
            postChange(for: bottleURL)
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

    /// Returns the number of active processes for a specific bottle.
    ///
    /// This is more efficient than ``getProcesses(for:)`` when only the count
    /// is needed (e.g. for badge indicators).
    ///
    /// - Parameter bottle: The bottle to query.
    /// - Returns: The number of tracked processes for the bottle.
    public func getProcessCount(for bottle: Bottle) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return activeProcesses[bottle.url]?.count ?? 0
    }

    /// Returns the number of active processes for a bottle identified by URL.
    ///
    /// Use this overload from non-`@MainActor` contexts where a ``Bottle``
    /// reference is unavailable.
    ///
    /// - Parameter bottleURL: The URL of the bottle to query.
    /// - Returns: The number of tracked processes for the bottle.
    public func getProcessCount(for bottleURL: URL) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return activeProcesses[bottleURL]?.count ?? 0
    }

    /// When Whisky last launched something in a bottle, or `nil` when nothing it
    /// launched there is still running as far as it knows.
    ///
    /// - Parameter bottleURL: The URL of the bottle to query.
    /// - Returns: The time of the latest launch in the bottle's current session.
    public func lastLaunch(for bottleURL: URL) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return lastLaunches[bottleURL]
    }

    /// Returns whether any active processes exist for a bottle identified by URL.
    ///
    /// - Parameter bottleURL: The URL of the bottle to check.
    /// - Returns: `true` if the bottle has at least one tracked process.
    public func hasActiveProcesses(for bottleURL: URL) -> Bool {
        getProcessCount(for: bottleURL) > 0
    }

    /// Clears the registry for a specific bottle URL.
    ///
    /// The bottle's launch session is kept: a kill takes a moment, and until the
    /// wineserver is gone it is still the one Whisky started, not an orphan.
    /// ``endSession(for:)`` ends it once the wineserver is seen idle.
    ///
    /// - Parameter bottleURL: The bottle URL to clear
    public func clearRegistry(for bottleURL: URL) {
        lock.lock()
        let hadProcesses = activeProcesses[bottleURL] != nil
        activeProcesses[bottleURL] = nil
        releaseDisplayWakeAssertionIfIdleLocked()
        lock.unlock()
        if hadProcesses {
            postChange(for: bottleURL)
        }
    }

    /// Ends a bottle's launch session: its tracked processes and its last launch.
    ///
    /// Called once the bottle's wineserver is seen idle, when nothing Whisky
    /// started there can still be running.
    ///
    /// - Parameter bottleURL: The bottle whose session ended.
    public func endSession(for bottleURL: URL) {
        lock.lock()
        let changed = activeProcesses[bottleURL] != nil || lastLaunches[bottleURL] != nil
        activeProcesses[bottleURL] = nil
        lastLaunches[bottleURL] = nil
        releaseDisplayWakeAssertionIfIdleLocked()
        lock.unlock()
        if changed {
            postChange(for: bottleURL)
        }
    }

    /// Posts ``didChangeNotification`` on the main thread, where views observe it.
    ///
    /// Never call this while holding ``lock``: on the main thread the post is
    /// synchronous, and an observer that reads the registry would deadlock.
    private func postChange(for bottleURL: URL) {
        let post: @Sendable () -> Void = {
            NotificationCenter.default.post(
                name: Self.didChangeNotification, object: nil, userInfo: [Self.bottleURLKey: bottleURL]
            )
        }
        if Thread.isMainThread {
            post()
        } else {
            DispatchQueue.main.async(execute: post)
        }
    }

    // MARK: - Display Wake Assertion

    /// Total tracked process count across all bottles. Caller must hold ``lock``.
    private func totalProcessCountLocked() -> Int {
        activeProcesses.values.reduce(0) { $0 + $1.count }
    }

    /// Acquires an IOKit `NoDisplaySleep` assertion if not already held and at
    /// least one process is registered. Caller must hold ``lock``.
    private func ensureDisplayWakeAssertionLocked() {
        guard displayWakeAssertion == 0, totalProcessCountLocked() > 0 else { return }
        var assertionID = IOPMAssertionID(0)
        let reason = "Whisky game running" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID
        )
        if result == kIOReturnSuccess {
            displayWakeAssertion = assertionID
        } else {
            logger.warning("Failed to create display-sleep assertion: \(result)")
        }
    }

    /// Releases the display-sleep assertion if no processes remain. Caller must
    /// hold ``lock``.
    private func releaseDisplayWakeAssertionIfIdleLocked() {
        guard displayWakeAssertion != 0, totalProcessCountLocked() == 0 else { return }
        IOPMAssertionRelease(displayWakeAssertion)
        displayWakeAssertion = IOPMAssertionID(0)
    }

    // MARK: - Testing Support

    /// Resets the registry to empty state. For testing purposes only.
    public func reset() {
        lock.lock()
        activeProcesses.removeAll()
        lastLaunches.removeAll()
        releaseDisplayWakeAssertionIfIdleLocked()
        lock.unlock()
    }
}
