//
//  DiscordIntegration.swift
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

/// The single point where a launch meets Whisky's Discord support.
///
/// Two independent features hang off this, both off by default and both per
/// bottle: ``DiscordPresence`` publishes the program Whisky launched, and
/// ``DiscordBridge`` lets a game publish its own. They are not alternatives:
/// a bottle may run both, and Discord shows the game's own activity in
/// preference to Whisky's when a game supplies one.
@MainActor
public final class DiscordIntegration {
    public static let shared = DiscordIntegration()

    private static let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "DiscordIntegration")

    /// How long to leave a presence alone before probing whether its bottle is
    /// still running. The probe is a `wineserver -k0`, so this is also how often
    /// a process is spawned while a presence is up.
    static let watchInterval: Duration = .seconds(30)

    private var watcher: Task<Void, Never>?

    private init() {}

    /// Called as a program is about to launch.
    ///
    /// Both halves are best-effort by construction: nothing here throws, and
    /// nothing here is awaited by the launch.
    public func programLaunching(_ url: URL, bottle: Bottle) {
        if bottle.settings.discordBridge {
            DiscordBridge.start(for: bottle)
        }

        guard bottle.settings.discordPresence else { return }
        guard DiscordPresence.isAvailable else {
            Self.logger.info("Discord presence is enabled but no client id is configured")
            return
        }

        let program = url.deletingPathExtension().lastPathComponent
        Task { await DiscordPresence.shared.publish(program: program) }
        watch(bottle: bottle)
    }

    /// Clears the presence once `bottle` stops running.
    ///
    /// Whisky launches through `start /unix`, which returns long before the
    /// program it started exits, so there is no process to wait on: the bottle's
    /// wineserver going idle is the signal that the session is over. The first
    /// probe is deliberately one interval late, since the wineserver may not be
    /// up yet at the moment of launch.
    private func watch(bottle: Bottle) {
        watcher?.cancel()
        watcher = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.watchInterval)
                if Task.isCancelled { return }

                if await !Wine.isWineserverRunning(for: bottle) {
                    await DiscordPresence.shared.clear()
                    return
                }
            }
        }
    }
}
