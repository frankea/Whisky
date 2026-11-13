//
//  BottleRunState.swift
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

/// Whether a bottle has something running, and whether Whisky started it.
///
/// A program launch runs `wine start /unix`, which hands the program to the
/// bottle's wineserver and exits within seconds. The game then runs with no
/// process of Whisky's own to watch, so the wineserver is the only live signal,
/// and the ``ProcessRegistry`` session (when Whisky last launched something in
/// the bottle) is what says whose that wineserver is.
public enum BottleRunState: Equatable, Sendable {
    /// Nothing is running in the bottle.
    case idle
    /// Something Whisky launched in this run of the app is running, or is still starting.
    ///
    /// `trackedCount` is the number of launches the ``ProcessRegistry`` still
    /// tracks, which can be 0 while the session runs on: after the bottle was
    /// told to stop, or once the Processes page found a launcher gone that
    /// handed off to another executable.
    case running(trackedCount: Int)
    /// The bottle's wineserver is up and neither a launch in this run of the
    /// app nor one of Whisky's own helpers accounts for it: left over from
    /// before a restart, or started outside Whisky.
    case orphaned

    /// How long after a launch a bottle counts as running without its
    /// wineserver: `wine` brings the wineserver up a moment after it starts,
    /// and a probe in that window must not end the session.
    public static let startupGrace: TimeInterval = 30

    /// Decides a bottle's state from what is known about it.
    ///
    /// - Parameters:
    ///   - trackedCount: The launches the ``ProcessRegistry`` tracks for the bottle.
    ///   - lastLaunch: When Whisky last launched something in the bottle, or `nil`
    ///     when it has no session there.
    ///   - wineserverRunning: Whether the bottle's wineserver answered a probe.
    ///   - helpersAccountForWineserver: Whether Whisky's own helpers, such as
    ///     bottle creation or the Processes page's listing, account for the
    ///     wineserver (``WineHelperActivity/accountsForWineserver(bottleURL:now:)``).
    ///     Such a wineserver runs nothing to show or stop.
    ///   - now: The time of the probe.
    ///   - grace: How long a launch counts as starting up; ``startupGrace`` by default.
    /// - Returns: The bottle's state. ``idle`` with a session still recorded means the
    ///   session is over and should be ended.
    public static func resolve(
        trackedCount: Int,
        lastLaunch: Date?,
        wineserverRunning: Bool,
        helpersAccountForWineserver: Bool = false,
        now: Date = Date(),
        grace: TimeInterval = startupGrace
    ) -> BottleRunState {
        let hasSession = lastLaunch != nil || trackedCount > 0
        if wineserverRunning {
            if hasSession {
                return .running(trackedCount: trackedCount)
            }
            return helpersAccountForWineserver ? .idle : .orphaned
        }
        // A launch can be ahead of its wineserver; the startup window keeps it
        // running until the wineserver has had time to come up.
        if let lastLaunch, now.timeIntervalSince(lastLaunch) < grace {
            return .running(trackedCount: trackedCount)
        }
        return .idle
    }

    /// Whether something Whisky launched is running.
    public var isRunning: Bool {
        if case .running = self {
            return true
        }
        return false
    }

    /// The number a running-count badge shows: the tracked launches, and at
    /// least 1 while a session runs without one. 0 when nothing Whisky launched runs.
    public var badgeCount: Int {
        if case let .running(trackedCount) = self {
            return max(trackedCount, 1)
        }
        return 0
    }
}
