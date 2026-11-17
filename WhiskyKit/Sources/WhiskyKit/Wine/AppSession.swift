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
/// the last run ended cleanly and which bottles it had started something in,
/// so it stops only what that run left behind, never a game started from the
/// `whisky` command, a shortcut or a Terminal while the app was closed.
public struct AppSessionRecord: Codable, Equatable, Sendable {
    /// When the run started.
    public var startedAt: Date
    /// Whether the run reached the end of its quit handler.
    public var endedCleanly: Bool
    /// The bottles the run had a launch session in, by standardized path.
    public var bottlePaths: Set<String>

    public init(startedAt: Date, endedCleanly: Bool = false, bottlePaths: Set<String> = []) {
        self.startedAt = startedAt
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
/// Safe to call from any thread.
public final class AppSessionStore: @unchecked Sendable {
    /// The defaults key the record is stored under.
    public static let defaultsKey = "appSession"

    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()
    private var current: AppSessionRecord?

    public init(defaults: UserDefaults = .standard, key: String = AppSessionStore.defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    /// Starts this run's record and returns the previous run's, if any.
    ///
    /// - Parameter date: When this run started.
    /// - Returns: The previous run's record, or `nil` on the first run or when it can't be read.
    @discardableResult
    public func begin(at date: Date = Date()) -> AppSessionRecord? {
        lock.lock()
        defer { lock.unlock() }
        let previous = defaults.data(forKey: key).flatMap {
            try? PropertyListDecoder().decode(AppSessionRecord.self, from: $0)
        }
        current = AppSessionRecord(startedAt: date)
        save()
        return previous
    }

    /// Records whether this run has a launch session in a bottle.
    ///
    /// - Parameters:
    ///   - bottleURL: The bottle.
    ///   - active: `true` while something this run launched may be running there.
    public func setLaunchSession(_ active: Bool, for bottleURL: URL) {
        lock.lock()
        defer { lock.unlock() }
        guard var record = current else { return }
        let path = AppSessionRecord.key(for: bottleURL)
        let changed = active ? record.bottlePaths.insert(path).inserted : record.bottlePaths.remove(path) != nil
        guard changed else { return }
        current = record
        save()
    }

    /// Marks this run as ended cleanly. Call at the end of the quit handler.
    public func endCleanly() {
        lock.lock()
        defer { lock.unlock() }
        guard var record = current else { return }
        record.endedCleanly = true
        current = record
        save()
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

    /// The action for one bottle.
    ///
    /// Stops a bottle only when all of these hold:
    /// - its wineserver is running;
    /// - its kill-on-quit policy says to stop it on quit;
    /// - the previous run of the app did not end cleanly, so its quit never stopped it;
    /// - that run had launched something in it, so what's running is that run's;
    /// - this run hasn't launched anything in it yet (a `whisky://` link or a
    ///   Dock pin can start a game before the sweep runs).
    ///
    /// - Parameters:
    ///   - bottleURL: The bottle.
    ///   - wineserverRunning: Whether the bottle's wineserver answered.
    ///   - stopsOnQuit: Whether the bottle's kill-on-quit policy stops it on quit.
    ///   - previousSession: The previous run's record, or `nil` if there is none.
    ///   - launchedThisSession: Whether this run has already launched something in the bottle.
    public static func action(
        for bottleURL: URL,
        wineserverRunning: Bool,
        stopsOnQuit: Bool,
        previousSession: AppSessionRecord?,
        launchedThisSession: Bool
    ) -> Action {
        guard wineserverRunning, stopsOnQuit, !launchedThisSession,
              let previousSession, !previousSession.endedCleanly,
              previousSession.contains(bottleURL)
        else { return .leave }
        return .stop
    }
}
