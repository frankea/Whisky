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
    /// Starts the client too when it isn't running, since `-applaunch` on a
    /// cold client brings it up first. The returned task is the client
    /// invocation, which lives as long as the session, so callers should not
    /// await it.
    ///
    /// - Parameters:
    ///   - appId: The Steam App ID to launch.
    ///   - bottle: The bottle whose Steam client to use.
    ///   - installURL: The game's install folder, to save a library rescan when
    ///     the caller already knows it.
    ///   - record: Whether to remember this bottle for the App ID.
    /// - Throws: ``SteamLaunchError/steamNotInstalled`` if the bottle has no client.
    @MainActor
    @discardableResult
    public static func launch(
        appId: Int, bottle: Bottle, installURL: URL? = nil, record: Bool = true
    ) throws -> Task<Void, Never> {
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

        return Task {
            await Wine.syncAudioRegistry(bottle: bottle)
            _ = try? await Wine.runProgram(
                at: steamExe, args: ["-applaunch", String(appId)], bottle: bottle,
                programOverrides: plan.overrides,
                gameProfileEnvironment: plan.gameProfileEnvironment,
                // the plan is the game's; steam.exe is only the vehicle
                overridesApplyToDescendants: true
            )
        }
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
