//
//  AppSession.swift
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

/// What one run of the Whisky app did, kept across restarts.
///
/// Quitting Whisky stops Wine in the bottles its kill-on-quit policy covers.
/// When the app crashes or is force-quit, that never happens, so the next
/// launch finishes the job. This record is how the next launch knows whether
/// the last run ended cleanly, which bottles it had started something in, and
/// when it was last alive, so it stops only what that run left behind and not
/// a game started from the `whisky` command, a shortcut or a Terminal after it.
public struct AppSessionRecord: Codable, Equatable, Sendable {
    /// When the run started.
    public var startedAt: Date
    /// The last time the run was known to be alive (``AppSessionStore/heartbeatInterval``).
    public var lastSeen: Date
    /// The run's process ID, to tell a crashed run from another copy of the app still running.
    public var processID: Int32?
    /// Whether the run reached the end of its quit handler.
    public var endedCleanly: Bool
    /// The bottles the run had a launch session in, by standardized path.
    public var bottlePaths: Set<String>

    public init(
        startedAt: Date,
        lastSeen: Date? = nil,
        processID: Int32? = nil,
        endedCleanly: Bool = false,
        bottlePaths: Set<String> = []
    ) {
        self.startedAt = startedAt
        self.lastSeen = lastSeen ?? startedAt
        self.processID = processID
        self.endedCleanly = endedCleanly
        self.bottlePaths = bottlePaths
    }

    /// Whether the run had a launch session in a bottle.
    public func contains(_ bottleURL: URL) -> Bool {
        bottlePaths.contains(Self.key(for: bottleURL))
    }

    static func key(for bottleURL: URL) -> String {
        let path = bottleURL.standardizedFileURL.path(percentEncoded: false)
        // A directory URL may or may not end in a slash; both name the same bottle.
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}

/// Keeps the app's ``AppSessionRecord`` in user defaults.
///
/// Only the app uses this; `whisky` command runs are not app sessions.
/// Nothing is written until ``begin(at:processID:)``. Safe to call from any thread.
public final class AppSessionStore: @unchecked Sendable {
    /// The defaults key the record is stored under.
    public static let defaultsKey = "appSession"
    /// How often the app should call ``heartbeat(at:)`` while it runs.
    public static let heartbeatInterval: Duration = .seconds(20)

    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()
    private var current: AppSessionRecord?

    public init(defaults: UserDefaults = .standard, key: String = AppSessionStore.defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    /// The stored record, without starting this run's.
    public func storedRecord() -> AppSessionRecord? {
        lock.lock()
        defer { lock.unlock() }
        return readStored()
    }

    /// Starts this run's record and returns the previous run's, if any.
    ///
    /// - Parameters:
    ///   - date: When this run started.
    ///   - processID: This run's process ID.
    /// - Returns: The previous run's record, or `nil` on the first run or when it can't be read.
    @discardableResult
    public func begin(at date: Date = Date(), processID: Int32? = nil) -> AppSessionRecord? {
        lock.lock()
        defer { lock.unlock() }
        let previous = readStored()
        current = AppSessionRecord(startedAt: date, processID: processID)
        save()
        return previous
    }

    /// Records that this run is still alive.
    public func heartbeat(at date: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        guard var record = current else { return }
        record.lastSeen = date
        current = record
        save()
    }

    /// Records whether this run has a launch session in a bottle.
    ///
    /// - Parameters:
    ///   - active: `true` while something this run launched may be running there.
    ///   - bottleURL: The bottle.
    ///   - date: Now, which also counts as a heartbeat.
    public func setLaunchSession(_ active: Bool, for bottleURL: URL, at date: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        guard var record = current else { return }
        let path = AppSessionRecord.key(for: bottleURL)
        if active {
            record.bottlePaths.insert(path)
        } else {
            record.bottlePaths.remove(path)
        }
        record.lastSeen = date
        current = record
        save()
    }

    /// Marks this run as ended cleanly. Call at the end of the quit handler.
    public func endCleanly(at date: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        guard var record = current else { return }
        record.endedCleanly = true
        record.lastSeen = date
        current = record
        save()
    }

    /// Reads the stored record. Call with ``lock`` held.
    private func readStored() -> AppSessionRecord? {
        defaults.data(forKey: key).flatMap { try? PropertyListDecoder().decode(AppSessionRecord.self, from: $0) }
    }

    /// Writes ``current``. Call with ``lock`` held.
    private func save() {
        guard let current, let data = try? PropertyListEncoder().encode(current) else { return }
        defaults.set(data, forKey: key)
    }
}

/// Decides what the app does at launch about a bottle whose wineserver is running.
public enum StartupOrphanSweep {
    public enum Action: Equatable, Sendable {
        /// Stop the bottle: the last run left it running and a clean quit would have stopped it.
        case stop
        /// Leave it running. The sidebar still offers to stop a bottle nobody here started.
        case leave
    }

    /// How long after the previous run's last heartbeat a wineserver may have
    /// started and still count as that run's: one heartbeat interval, plus a
    /// margin for a launch whose wineserver comes up a moment after it.
    public static let heartbeatGrace: TimeInterval = 30

    /// The action for one bottle.
    ///
    /// Stops a bottle only when all of these hold:
    /// - its wineserver is running, and started while the previous run was
    ///   still alive (up to ``heartbeatGrace`` after its last heartbeat), so it
    ///   is not one a `whisky` command or shortcut started after the crash;
    /// - its kill-on-quit policy says to stop it on quit;
    /// - the previous run of the app did not end cleanly, so its quit never stopped it;
    /// - that run had launched something in it;
    /// - this run hasn't launched anything in it yet (a `whisky://` link or a
    ///   Dock pin can start a game before the sweep runs).
    ///
    /// A wineserver whose start time can't be read is left running.
    ///
    /// - Parameters:
    ///   - bottleURL: The bottle.
    ///   - wineserverStartedAt: When the bottle's running wineserver started, or `nil` if none is running.
    ///   - stopsOnQuit: Whether the bottle's kill-on-quit policy stops it on quit.
    ///   - previousSession: The previous run's record, or `nil` if there is none.
    ///   - launchedThisSession: Whether this run has already launched something in the bottle.
    public static func action(
        for bottleURL: URL,
        wineserverStartedAt: Date?,
        stopsOnQuit: Bool,
        previousSession: AppSessionRecord?,
        launchedThisSession: Bool
    ) -> Action {
        guard let wineserverStartedAt, stopsOnQuit, !launchedThisSession,
              let previousSession, !previousSession.endedCleanly,
              previousSession.contains(bottleURL),
              wineserverStartedAt <= previousSession.lastSeen.addingTimeInterval(heartbeatGrace)
        else { return .leave }
        return .stop
    }
}
