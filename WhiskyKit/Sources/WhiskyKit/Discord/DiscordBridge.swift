//
//  DiscordBridge.swift
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

/// Starts the in-bottle relay that lets a game reach the host's Discord client.
///
/// A game that publishes its own rich presence writes to the named pipe
/// `\\.\pipe\discord-ipc-0`, which exists only inside the prefix and reaches
/// nothing. The relay serves that pipe and forwards every byte to the socket
/// Discord listens on, so a game's own presence arrives intact, cover art,
/// party state, join buttons and all. Games that publish nothing are unaffected;
/// those are what ``DiscordPresence`` is for.
///
/// The relay is built from `scripts/discord-bridge` and shipped as a resource.
/// It is run out of the bundle rather than installed into the bottle, so
/// enabling and disabling this leaves no trace in a prefix.
public enum DiscordBridge {
    private static let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "DiscordBridge")

    /// The relay binary's name, without its extension.
    public static let executableName = "WhiskyDiscordBridge"

    /// The bundled relay, or `nil` if the resource is missing from this build.
    public static var executableURL: URL? {
        Bundle.module.url(forResource: executableName, withExtension: "exe")
    }

    /// The arguments that run the relay in a bottle.
    ///
    /// The socket directory is passed explicitly because the relay is a PE
    /// process: it sees Wine's Windows environment, where the host's `TMPDIR`
    /// may not have survived, and the sockets are named relative to it.
    static func launchArguments(executableURL: URL, socketDirectory: URL) -> [String] {
        [
            "start", "/unix", executableURL.path(percentEncoded: false),
            "--dir", socketDirectory.path(percentEncoded: false)
        ]
    }

    /// Starts the relay for `bottle` if it is not already running there.
    ///
    /// Safe to call on every launch: the relay holds a per-prefix mutex and a
    /// second copy exits immediately. Failures are logged rather than thrown,
    /// since a missing relay must not stop the program that asked for it.
    @MainActor
    public static func start(for bottle: Bottle) {
        guard let executableURL else {
            logger.error("The Discord bridge is missing from this build")
            return
        }

        do {
            let output = try Wine.runWineProcess(
                name: "\(executableName).exe",
                args: launchArguments(executableURL: executableURL, socketDirectory: DiscordIPC.socketDirectory),
                bottle: bottle
            )
            // `start /unix` returns as soon as the relay is running, so this
            // drains a stream that is already finishing rather than the relay's
            // own lifetime.
            Task { for await _ in output {} }
        } catch {
            logger.error("Could not start the Discord bridge: \(error.localizedDescription, privacy: .public)")
        }
    }
}
