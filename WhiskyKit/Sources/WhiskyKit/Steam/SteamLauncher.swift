//
//  SteamLauncher.swift
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

/// Errors thrown when launching a Steam game.
public enum SteamLaunchError: LocalizedError, Equatable {
    /// The bottle has no Steam installation.
    case steamNotInstalled
    /// No bottle known to Whisky has that App ID installed.
    case gameNotFound(appId: Int)

    public var errorDescription: String? {
        switch self {
        case .steamNotInstalled:
            String(localized: "steam.launch.error.noClient")
        case let .gameNotFound(appId):
            String(localized: "steam.launch.error.gameNotFound \(appId)")
        }
    }
}

/// The single launch path for Steam games: resolve the game's GameDB profile,
/// then hand `-applaunch` to the Windows client, which owns DRM and the game
/// process itself.
public enum SteamLauncher {
    /// Launches a game through the bottle's Steam client.
    ///
    /// Starts the client first when it isn't running, the way Play does: with
    /// `-silent`, as a launch of its own, and only then hands over `-applaunch`.
    /// `-applaunch` on a cold client would start the client itself, and the
    /// client and its helpers would inherit the game's DLL overrides from that
    /// invocation's environment, which outranks their own `AppDefaults` entries
    /// (#276). The returned task is the `-applaunch` invocation. A command-line
    /// caller has to await it: the launch only happens inside the task, and a
    /// process that exits first takes the task with it before Wine has started
    /// anything.
    ///
    /// - Parameters:
    ///   - appId: The Steam App ID to launch.
    ///   - bottle: The bottle whose Steam client to use.
    ///   - installURL: The game's install folder, to save a library rescan when
    ///     the caller already knows it.
    ///   - record: Whether to remember this bottle for the App ID.
    ///   - clientIsRunning: Whether the caller has already made sure the client
    ///     is up, as Play does, which saves checking again.
    ///   - onOutput: Receives the `-applaunch` invocation's output events,
    ///     starting with ``ProcessOutput/started`` once Wine is running it.
    /// - Returns: The client invocation, which finishes with its run result.
    /// - Throws: ``SteamLaunchError/steamNotInstalled`` if the bottle has no client.
    @MainActor
    @discardableResult
    public static func launch(
        appId: Int, bottle: Bottle, installURL: URL? = nil, record: Bool = true,
        clientIsRunning: Bool = false,
        onOutput: (@MainActor (ProcessOutput) -> Void)? = nil
    ) throws -> Task<Wine.ProgramRunResult, any Error> {
        guard let steamRoot = SteamLibrary.detectInstall(bottleURL: bottle.url) else {
            throw SteamLaunchError.steamNotInstalled
        }

        if record {
            GameRouting().record(appId: appId, bottleURL: bottle.url)
        }

        let installURL = installURL ?? SteamLibrary.enumerate(bottleURL: bottle.url)
            .first { $0.appId == appId }?.installURL
        let plan = LaunchResolver.plan(
            steamAppId: appId,
            userOverrides: installURL.flatMap { userOverrides(forInstallURL: $0, bottle: bottle) }
        )
        let steamExe = steamRoot.appending(path: "steam.exe")
        let gameExecutables = installURL.map { SteamLibrary.executableURLs(under: $0).map(\.lastPathComponent) } ?? []

        return Task {
            try await Wine.prepareBottlePrefix(bottle: bottle)
            await Wine.syncAudioRegistry(bottle: bottle)
            if !clientIsRunning {
                let running = await hostSteamPIDs()
                await startClientIfNeeded(
                    isRunning: { await isClientRunning(bottle: bottle, hostSteamPIDs: running) },
                    start: {
                        Task { _ = try? await Wine.runProgram(at: steamExe, args: ["-silent"], bottle: bottle) }
                    },
                    hasStarted: { await !hostSteamPIDs().subtracting(running).isEmpty }
                )
            }
            return try await Wine.runProgram(
                at: steamExe, args: ["-applaunch", String(appId)], bottle: bottle,
                programOverrides: plan.overrides,
                gameProfileEnvironment: plan.gameProfileEnvironment,
                // the plan is the game's; steam.exe is only the vehicle
                overridesApplyToDescendants: true,
                descendantExecutables: gameExecutables,
                onOutput: onOutput
            )
        }
    }

    /// Starts the client when it isn't running, then waits until it is.
    ///
    /// Gives up waiting after `timeout` and lets `-applaunch` go ahead anyway,
    /// which is what happened before the client was started separately.
    ///
    /// - Parameters:
    ///   - isRunning: Whether `steam.exe` is running in the bottle. Asked once.
    ///   - start: Starts `steam.exe -silent`. Must return promptly: the client
    ///     runs for the whole session.
    ///   - hasStarted: Whether the client this started is up. Polled, so it must
    ///     not start a Wine process: on a prefix the start is still booting, a
    ///     poll every few seconds keeps the boot's services alive, and the
    ///     launch's registry import waits on their output until they exit.
    ///   - timeout: How long to wait for the client to appear.
    ///   - pollInterval: How often to look.
    /// - Returns: Whether the client is running.
    @MainActor
    @discardableResult
    static func startClientIfNeeded(
        isRunning: @MainActor () async -> Bool,
        start: @MainActor () -> Void,
        hasStarted: @MainActor () async -> Bool,
        timeout: Duration = .seconds(90),
        pollInterval: Duration = .seconds(2)
    ) async -> Bool {
        if await isRunning() {
            return true
        }
        start()
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: pollInterval)
            if await hasStarted() {
                return true
            }
        }
        return false
    }

    /// Whether `steam.exe` is running in the bottle.
    ///
    /// Without a `steam.exe` anywhere on the host the answer is no, and no Wine
    /// process is started to find that out.
    @MainActor
    static func isClientRunning(bottle: Bottle, hostSteamPIDs: Set<Int32>) async -> Bool {
        guard !hostSteamPIDs.isEmpty else { return false }
        return await WineSteamClientDriver(bottle: bottle).processList()
            .contains { $0.imageName.lowercased() == "steam.exe" }
    }

    /// The host process IDs of every process whose Windows image is `steam.exe`,
    /// in any bottle. Wine's processes carry their Windows path in the host
    /// process list, so this costs one `ps` and no Wine process.
    static func hostSteamPIDs() async -> Set<Int32> {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(filePath: "/bin/ps")
            process.arguments = ["-Ao", "pid=,comm="]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return [] }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return steamPIDs(inProcessListing: String(bytes: data, encoding: .utf8) ?? "")
        }.value
    }

    /// The IDs in a `ps -Ao pid=,comm=` listing whose command is a Windows
    /// `steam.exe`.
    static func steamPIDs(inProcessListing output: String) -> Set<Int32> {
        Set(output.split(whereSeparator: \.isNewline).compactMap { line -> Int32? in
            let fields = line.trimmingCharacters(in: .whitespaces)
                .split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard fields.count == 2, let pid = Int32(fields[0]) else { return nil }
            let image = fields[1].split(separator: "\\").last ?? fields[1]
            return image.lowercased() == "steam.exe" ? pid : nil
        })
    }

    /// The user's persisted overrides for a game's executables, so settings
    /// tuned in the Programs tab survive a launch from the library or the cli.
    ///
    /// Resolution is read-only: no ``Program`` is materialized, so Play never
    /// writes settings plists for the executables that don't win. Only an
    /// executable with persisted overrides can win, so skipping the default
    /// plists changes nothing for the winner.
    @MainActor
    static func userOverrides(forInstallURL installURL: URL, bottle: Bottle) -> ProgramOverrides? {
        let scanned = Dictionary(
            bottle.programs.compactMap { program in
                program.settings.overrides.map { (program.url.standardizedFileURL, $0) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        let candidates = SteamLibrary.executableURLs(under: installURL).map { url in
            // Falls back to a plist read for executables the bottle scan has
            // not reached, so Play works before the Programs tab is opened.
            let overrides = scanned[url.standardizedFileURL]
                ?? Program.persistedOverrides(for: url, bottleURL: bottle.url)
            return ProgramOverrideCandidate(url: url, overrides: overrides ?? ProgramOverrides())
        }
        return SteamLibrary.preferredOverrides(among: candidates)
    }

    /// Finds the installed game an App ID names, and the bottle holding it.
    ///
    /// Narrowing `bottles` to a single bottle chooses where to look, never
    /// whether to look: an App ID that arrives from outside the app may only
    /// ever reach a game the user actually has. The library entry is also what
    /// lets a caller name the game rather than echo the App ID back.
    ///
    /// - Parameters:
    ///   - appId: The Steam App ID to locate.
    ///   - bottles: The bottles to search.
    ///   - routing: The route store to consult.
    /// - Returns: The library entry and the bottle it was found in.
    /// - Throws: ``SteamLaunchError/gameNotFound(appId:)`` when no bottle has it.
    @MainActor
    public static func resolveGame(
        appId: Int, in bottles: [Bottle], routing: GameRouting = GameRouting()
    ) throws -> (game: SteamGame, bottle: Bottle) {
        let bottle = try resolveBottle(appId: appId, in: bottles, routing: routing)
        guard let game = SteamLibrary.enumerate(bottleURL: bottle.url)
            .first(where: { $0.appId == appId })
        else {
            throw SteamLaunchError.gameNotFound(appId: appId)
        }
        return (game, bottle)
    }

    /// Finds the bottle to launch an App ID from: the remembered route when it
    /// still has the game installed, otherwise the first bottle that does.
    ///
    /// - Parameters:
    ///   - appId: The Steam App ID to locate.
    ///   - bottles: The bottles to search.
    ///   - routing: The route store to consult.
    /// - Returns: The bottle holding the game.
    /// - Throws: ``SteamLaunchError/gameNotFound(appId:)`` when no bottle has it.
    @MainActor
    public static func resolveBottle(
        appId: Int, in bottles: [Bottle], routing: GameRouting = GameRouting()
    ) throws -> Bottle {
        let installs: (Bottle) -> Bool = { bottle in
            SteamLibrary.enumerate(bottleURL: bottle.url).contains { $0.appId == appId }
        }

        if let routed = routing.bottleURL(forAppId: appId),
           let bottle = bottles.first(where: { $0.url.standardizedFileURL == routed.standardizedFileURL }),
           installs(bottle) {
            return bottle
        }

        guard let bottle = bottles.first(where: installs) else {
            throw SteamLaunchError.gameNotFound(appId: appId)
        }
        return bottle
    }
}
