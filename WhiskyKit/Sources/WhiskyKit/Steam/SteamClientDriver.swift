//
//  SteamClientDriver.swift
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

/// Everything ``SteamClientOrchestrator`` needs from the outside world: process
/// lists, starting the client, launching and killing games, and two lifecycle
/// hooks. The orchestrator owns the sequencing (single-flight client startup,
/// per-game phases, the shared process snapshot); the driver owns the side
/// effects, so tests can script one without Wine.
@MainActor
public protocol SteamClientDriver: AnyObject {
    /// Lower-cased `.exe` names of Wine processes visible to the host.
    ///
    /// Not bottle-scoped, so the orchestrator only uses it to short-circuit
    /// the negative case: an empty answer means nothing is running anywhere,
    /// and the bottle's own process list is not consulted.
    func hostWineImageNames() async -> Set<String>

    /// The bottle's process list, as `tasklist.exe` reports it.
    func processList() async -> [WineProcess]

    /// Starts the Steam client silently. Must return promptly: the client runs
    /// for the whole session and the orchestrator watches for it separately.
    func startClient(steamExe: URL)

    /// Applies Steam's launcher fixes to the bottle. Only called when
    /// ``SteamClientOrchestrator/shouldApplyLauncherFixes(settings:)`` says so.
    func applyLauncherFixes()

    /// Hands `-applaunch` for the game to the running client.
    func launchGame(_ game: SteamGame) throws

    /// Asks one of the bottle's processes to close.
    func killProcess(winePID: Int32) async

    /// The client is up (started here or found already running).
    func clientDidBecomeReady()

    /// The orchestrator is being stopped; release anything started in
    /// ``clientDidBecomeReady()``.
    func shutdown()
}

/// The production driver: Wine, `tasklist.exe`, `ps`, and ``SteamLauncher``.
///
/// `open` so the app can layer session-scoped behavior on the two lifecycle
/// hooks (download monitoring) without the kit knowing about it.
@MainActor
open class WineSteamClientDriver: SteamClientDriver {
    public let bottle: Bottle

    public init(bottle: Bottle) {
        self.bottle = bottle
    }

    /// Reads `ps` rather than spawning `tasklist.exe`, which is a whole Wine
    /// process: polled every couple of seconds, the wait for a cold Steam
    /// client spent dozens of them competing with the client it was waiting
    /// for. Wine's processes carry their Windows image name in the host
    /// process list, so this answers "nothing is running yet" for free.
    open func hostWineImageNames() async -> Set<String> {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(filePath: "/bin/ps")
            process.arguments = ["-Ao", "comm="]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return [] }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard let output = String(bytes: data, encoding: .utf8) else { return [] }
            return Set(
                output
                    .split(whereSeparator: \.isNewline)
                    .compactMap { line in
                        let name = (line.split(separator: "\\").last ?? line).lowercased()
                        return name.hasSuffix(".exe") ? String(name) : nil
                    }
            )
        }.value
    }

    open func processList() async -> [WineProcess] {
        guard let output = try? await Wine.runWine(["tasklist.exe", "/FO", "CSV"], bottle: bottle) else {
            return []
        }
        return Wine.parseTasklistOutput(output)
    }

    /// `steam.exe -silent` runs for the whole session, so the run is never awaited.
    open func startClient(steamExe: URL) {
        let bottle = self.bottle
        Task {
            _ = try? await Wine.runProgram(at: steamExe, args: ["-silent"], bottle: bottle)
        }
    }

    /// Through the shared path, which carries the locale, DXVK and
    /// GPU-spoofing settings steamwebhelper needs and not just the compat flag.
    open func applyLauncherFixes() {
        LauncherFixes.apply(to: bottle, launcher: .steam)
    }

    /// Shared with `whisky launch`: resolves the GameDB profile and the user's
    /// overrides, records the bottle for this App ID, and hands `-applaunch`
    /// to the client. The returned task can outlive the game, so it is never
    /// awaited. The install URL is already known, which saves a library rescan.
    open func launchGame(_ game: SteamGame) throws {
        _ = try SteamLauncher.launch(appId: game.appId, bottle: bottle, installURL: game.installURL)
    }

    open func killProcess(winePID: Int32) async {
        await Wine.gracefulKillProcess(winePID: winePID, bottle: bottle)
    }

    open func clientDidBecomeReady() {}

    open func shutdown() {}
}
