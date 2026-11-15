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
    /// The game's DLL overrides go into the `AppDefaults` entries of its
    /// executables, and the `-applaunch` invocation carries none in its
    /// environment, which every process it starts would inherit and which
    /// outranks their own entries. So the game gets its plan whether the
    /// running client or this invocation starts it, and the client and its
    /// helpers keep DXVK even when `-applaunch` brings them up (#276).
    ///
    /// The plan's launch arguments follow the App ID, and the client passes them
    /// on to the game.
    ///
    /// The plan follows the GameDB variant the user applied to the bottle, when
    /// it is this game's, rather than the recommended one.
    ///
    /// Starts the client first when it isn't running, the way Play does: with
    /// `-silent`, as a launch of its own, and only then hands over `-applaunch`,
    /// so the client never inherits the game's environment variables. The
    /// returned task is the `-applaunch` invocation. A command-line
    /// caller has to await it: the launch only happens inside the task, and a
    /// process that exits first takes the task with it before Wine has started
    /// anything. When this launch started the client, the result's
    /// `outputCompletion` also waits for the client's output to close, so a
    /// command-line caller that awaits it keeps reading the client's log for
    /// the whole session.
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
    ///     starting with ``ProcessOutput/started`` once Wine is running it, and
    ///     going on after ``ProcessOutput/terminated(_:)`` until its output closes.
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
            let now = Date()
            GameRouting().record(appId: appId, bottleURL: bottle.url, at: now)
            RecordedLaunch(bottleURL: bottle.url, target: .steam(appID: appId), date: now).post()
        }

        let installURL = installURL ?? SteamLibrary.enumerate(bottleURL: bottle.url)
            .first { $0.appId == appId }?.installURL
        // One scan for both uses: it runs on the main actor.
        let scan = installURL.map { SteamLibrary.scanExecutables(under: $0) }
        let plan = launchPlan(appId: appId, scan: scan, bottle: bottle)
        let request = appLaunchRequest(appId: appId, scan: scan, plan: plan)
        let steamExe = steamRoot.appending(path: "steam.exe")

        return Task {
            try await Wine.prepareBottlePrefix(bottle: bottle)
            var clientRun: Task<Wine.ProgramRunResult, any Error>?
            if !clientIsRunning {
                let running = await hostSteamPIDs()
                await startClientIfNeeded(
                    isRunning: { await isClientRunning(bottle: bottle, hostSteamPIDs: running) },
                    start: { clientRun = startClient(steamExe: steamExe, bottle: bottle) },
                    hasStarted: { await !hostSteamPIDs().subtracting(running).isEmpty }
                )
            }
            let result = try await Wine.runProgram(at: steamExe, bottle: bottle, request: request, onOutput: onOutput)
            return result.includingOutput(of: clientRun)
        }
    }

    /// Starts `steam.exe -silent` with the user's own overrides for it, the
    /// way the Programs tab would, so the client's entry matches the one a
    /// game launch writes for it.
    ///
    /// - Returns: The client run. It finishes once its `wine start` launcher
    ///   exits; its result's `outputCompletion` waits for the whole session.
    @MainActor
    @discardableResult
    static func startClient(steamExe: URL, bottle: Bottle) -> Task<Wine.ProgramRunResult, any Error> {
        let overrides = Program.persistedOverrides(for: steamExe, bottleURL: bottle.url)
        return Task {
            try await Wine.runProgram(
                at: steamExe, args: ["-silent"], bottle: bottle, programOverrides: overrides
            )
        }
    }

    /// The executable names a game launch scopes the game's plan to: what the
    /// install folder holds, then what the GameDB lists, each name once.
    ///
    /// A Chromium host below the first folder level is not among them: it
    /// keeps its own settings (see ``SteamExecutableScan/chromiumHosts``).
    static func gameExecutables(installURL: URL?, plan: LaunchPlan) -> [String] {
        gameExecutables(
            scanned: installURL.map { SteamLibrary.scanExecutables(under: $0).planExecutables } ?? [], plan: plan
        )
    }

    /// ``gameExecutables(installURL:plan:)`` from an install folder's scan.
    static func gameExecutables(scanned: [URL], plan: LaunchPlan) -> [String] {
        var seen = Set<String>()
        let names = scanned.map(\.lastPathComponent) + plan.gameExecutables
        return names.filter { seen.insert($0.lowercased()).inserted }
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
    ///   - hasStarted: Whether the client this started is up. Polled, so it
    ///     should not start a Wine process: one every few seconds, on a prefix
    ///     the start is still booting, is far more work than the `ps` this
    ///     needs and keeps the boot's services busy while the client comes up.
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
    ///
    /// A Chromium host below the first folder level never wins: what the user
    /// set on a front end such as 3DMark's is for the front end, not for the
    /// workloads it starts. The launch writes it into the host's own entry.
    @MainActor
    static func userOverrides(forInstallURL installURL: URL, bottle: Bottle) -> ProgramOverrides? {
        userOverrides(forExecutables: SteamLibrary.scanExecutables(under: installURL).planExecutables, bottle: bottle)
    }

    /// ``userOverrides(forInstallURL:bottle:)`` from an install folder's scan.
    @MainActor
    static func userOverrides(forExecutables executables: [URL], bottle: Bottle) -> ProgramOverrides? {
        let scanned = Dictionary(
            bottle.programs.compactMap { program in
                program.settings.overrides.map { (program.url.standardizedFileURL, $0) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        let candidates = executables.map { url in
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

extension Wine.ProgramRunResult {
    /// This result, with an `outputCompletion` that also waits for the output
    /// of `client` to close: the `steam.exe -silent` run a launch started, whose
    /// log is read by the same process for the whole session.
    ///
    /// A client run that failed to start has no output to wait for.
    func includingOutput(of client: Task<Wine.ProgramRunResult, any Error>?) -> Wine.ProgramRunResult {
        guard let client else { return self }
        let ownCompletion = outputCompletion
        let completion = ProcessOutputCompletion()
        Task {
            await ownCompletion.wait()
            if let clientResult = try? await client.value {
                await clientResult.outputCompletion.wait()
            }
            completion.complete()
        }
        return Wine.ProgramRunResult(
            exitCode: exitCode, logFileURL: logFileURL, runLogEntryId: runLogEntryId, outputCompletion: completion
        )
    }
}
