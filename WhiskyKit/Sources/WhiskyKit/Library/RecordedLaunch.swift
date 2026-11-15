//
//  RecordedLaunch.swift
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

/// A launch that has just been written to one of the stores the library reads
/// its last played dates from: a program's run log, or the Steam routing store.
///
/// Posted as ``didRecordNotification`` so a screen already showing those dates
/// can update the one entry that changed, instead of rereading every store or
/// waiting for its next reload. Every launch path records through the same two
/// places (``Wine`` for programs, ``SteamLauncher`` for Steam games), so the
/// Library, the Programs tab, pins, the menu bar and `whisky://` links all
/// post it.
public struct RecordedLaunch: Hashable, Sendable {
    /// What was launched, keyed the way its store keys it.
    public enum Target: Hashable, Sendable {
        /// A program, by executable file name: the run log is per bottle and
        /// per file name, not per path.
        case program(name: String)
        /// A Steam game. The routing store keeps one launch time per App ID
        /// whichever bottle it ran in.
        case steam(appID: Int)
    }

    /// Posted on the main actor right after a launch is recorded. The
    /// notification's `userInfo` carries the ``RecordedLaunch``; read it back
    /// with ``init(notification:)``.
    public static let didRecordNotification = Notification.Name("com.franke.Whisky.launchRecorded")
    static let userInfoKey = "recordedLaunch"

    public let bottleURL: URL
    public let target: Target
    public let date: Date

    public init(bottleURL: URL, target: Target, date: Date) {
        self.bottleURL = bottleURL
        self.target = target
        self.date = date
    }

    /// Reads the launch out of a ``didRecordNotification``, or `nil` for any
    /// other notification.
    public init?(notification: Notification) {
        guard notification.name == Self.didRecordNotification,
              let launch = notification.userInfo?[Self.userInfoKey] as? RecordedLaunch
        else { return nil }
        self = launch
    }

    /// Posts ``didRecordNotification`` for this launch.
    @MainActor
    public func post(to center: NotificationCenter = .default) {
        center.post(name: Self.didRecordNotification, object: nil, userInfo: [Self.userInfoKey: self])
    }

    /// Whether this is a launch of `entry`, by the same key the entry's last
    /// played date is read with.
    public func isLaunch(of entry: LibraryEntry) -> Bool {
        switch (target, entry.launch) {
        case let (.program(name), .program(url)):
            name == url.lastPathComponent
                && bottleURL.standardizedFileURL == entry.bottleURL.standardizedFileURL
        case let (.steam(launched), .steam(appID)):
            launched == appID
        default:
            false
        }
    }

    /// `entry`'s last played date once this launch is counted: this launch's
    /// date when it is a launch of `entry` and later than `current`, `current`
    /// otherwise.
    public func lastPlayed(_ current: Date?, for entry: LibraryEntry) -> Date? {
        guard isLaunch(of: entry) else { return current }
        guard let current else { return date }
        return max(current, date)
    }
}
