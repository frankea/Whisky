//
//  SparkleUpdaterDelegate.swift
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

import AppKit
import Sparkle

/// Adds gentle scheduled-update reminders on top of Sparkle's standard user
/// driver (whisky-app/whisky#765, lighter-touch variant).
///
/// Sparkle's default behaviour pops a focus-stealing update dialog the moment a
/// scheduled background check finds a new version. With this delegate, when the
/// app isn't already active the reminder is *deferred*: a Dock-tile badge appears
/// and `updateAvailable` flips on so the in-app "Check for Updates" item reads
/// "Install Update…", letting the user act when ready. User-initiated checks and
/// the actual download / install / relaunch still use Sparkle's proven standard
/// UI unchanged.
///
/// `@unchecked Sendable` follows the project's singleton convention (see
/// `ProcessRegistry`): the type carries mutable UI state but every access is on
/// the main thread — Sparkle invokes these `SPUStandardUserDriverDelegate`
/// callbacks on the main thread, so each one hops through `MainActor` before
/// touching `NSApp` or the published flag.
final class SparkleUpdaterDelegate: NSObject, ObservableObject, SPUStandardUserDriverDelegate, @unchecked Sendable {
    static let shared = SparkleUpdaterDelegate()

    /// True when a scheduled check found an update whose modal alert we deferred.
    /// Drives the in-app "Install Update…" affordance.
    @Published var updateAvailable = false

    /// Opt into handling our own gentle reminders for scheduled updates.
    var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInState state: SPUUserUpdateState
    ) -> Bool {
        // Let Sparkle show its standard alert immediately when the user is already
        // looking at Whisky; otherwise defer to the gentle in-app reminder below.
        MainActor.assumeIsolated { NSApp.isActive }
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        // When Sparkle isn't showing the alert itself (we deferred), raise the
        // gentle indicator instead of stealing focus with a modal.
        guard !handleShowingUpdate else { return }
        MainActor.assumeIsolated { self.setUpdateAvailable(true) }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated { self.setUpdateAvailable(false) }
    }

    func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { self.setUpdateAvailable(false) }
    }

    @MainActor
    private func setUpdateAvailable(_ value: Bool) {
        updateAvailable = value
        NSApp.dockTile.badgeLabel = value ? "1" : ""
    }
}
