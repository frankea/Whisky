//
//  LaunchResolver.swift
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

/// The resolved configuration for launching one game once.
///
/// Nothing in a plan is persisted: GameDB recommendations are applied
/// per launch, so two games in the same bottle never fight over
/// bottle-wide settings.
public struct LaunchPlan {
    /// Per-launch program overrides: the user's persisted overrides with
    /// GameDB variant settings filling any field the user left unset.
    public let overrides: ProgramOverrides
    /// Extra environment for the ``EnvironmentLayer/gameProfile`` layer.
    public let gameProfileEnvironment: [String: String]
    /// Human-readable notes on where the configuration came from, for
    /// logging and provenance UI.
    public let provenance: [String]
    /// The game's executable names as the GameDB lists them, to scope the
    /// overrides to alongside the ones found in the install folder.
    public var gameExecutables: [String] = []
    /// Launchers the game starts on its own inside the Steam session, whose
    /// processes then need their `AppDefaults` entries ahead of time.
    public var startsLaunchers: [LauncherType] = []
    /// Arguments for the game's own command line, from the GameDB variant.
    public var launchArguments: [String] = []
}

/// Turns a Steam App ID into a ``LaunchPlan`` by matching the GameDB and
/// merging the variant the user applied, or else the recommended one, under
/// the user's own overrides.
public enum LaunchResolver {
    /// Builds the launch plan for a game.
    ///
    /// - Parameters:
    ///   - steamAppId: The game's Steam App ID (a hard identifier for
    ///     ``GameMatcher``, so no fuzzy-match risk).
    ///   - exeName: Optional executable name hint for matching.
    ///   - userOverrides: The user's persisted per-program overrides. Every
    ///     non-nil field wins over the GameDB recommendation.
    ///   - appliedConfiguration: The configuration applied to the bottle from
    ///     the Game Configs view. Its variant is used when the snapshot names
    ///     this game's entry and that entry still has the variant; otherwise
    ///     the recommended variant is.
    ///   - entries: The GameDB entries to match against. Defaults to the
    ///     bundled database.
    ///   - isBackendAvailable: Whether this machine can run a backend. A
    ///     variant backend it can't run becomes Recommended, as it does when
    ///     the configuration is applied to the bottle.
    /// - Returns: A plan; without a GameDB match it simply carries the user
    ///   overrides and empty profile environment.
    public static func plan(
        steamAppId: Int,
        exeName: String? = nil,
        userOverrides: ProgramOverrides? = nil,
        appliedConfiguration: GameConfigSnapshot? = nil,
        entries: [GameDBEntry]? = nil,
        isBackendAvailable: (GraphicsBackend) -> Bool = WhiskyWineInstaller.isBackendAvailable
    ) -> LaunchPlan {
        let database = entries ?? GameDBLoader.loadDefaults()
        let metadata = ProgramMetadata(exeName: exeName ?? "", steamAppId: steamAppId)

        let match = GameMatcher.bestMatch(metadata: metadata, against: database)
        let rockstar = LauncherType.rockstarSteamAppIds.contains(steamAppId)
            || match?.entry.subtitle?.localizedCaseInsensitiveContains("Rockstar Games") == true
        let startsLaunchers: [LauncherType] = rockstar ? [.rockstar] : []

        guard let match, let variant = variant(for: match, applied: appliedConfiguration) else {
            var plan = LaunchPlan(
                overrides: userOverrides ?? ProgramOverrides(),
                gameProfileEnvironment: [:],
                provenance: []
            )
            plan.gameExecutables = match?.entry.exeNames ?? []
            plan.startsLaunchers = startsLaunchers
            return plan
        }

        let overrides = merge(
            variant: variant.settings, dllOverrides: variant.dllOverrides, under: userOverrides,
            isBackendAvailable: isBackendAvailable
        )

        var plan = LaunchPlan(
            overrides: overrides,
            gameProfileEnvironment: variant.environmentVariables ?? [:],
            provenance: [
                "gamedb: \(match.entry.title) — \(variant.label) (\(match.explanation))"
            ]
        )
        plan.gameExecutables = match.entry.exeNames ?? []
        plan.startsLaunchers = startsLaunchers
        plan.launchArguments = variant.launchArguments ?? []
        return plan
    }

    /// The variant a launch uses: the one applied to the bottle when the
    /// snapshot belongs to this game and the entry still has it, otherwise the
    /// recommended one.
    ///
    /// Without this, a launch merged the recommended variant's backend and
    /// environment under the game even after the user applied another, so the
    /// bottle ran one variant's settings and the game another's.
    static func variant(for match: MatchResult, applied: GameConfigSnapshot?) -> GameConfigVariant? {
        if let applied, applied.appliedEntryId == match.entry.id,
           let variant = match.entry.variants.first(where: { $0.id == applied.appliedVariantId }) {
            return variant
        }
        return match.recommendedVariant
    }

    /// Fills GameDB variant settings into every field the user left unset.
    ///
    /// Bottle-level variant settings (`avxEnabled`, `sequoiaCompatMode`) and
    /// `winetricksVerbs` are not mapped: the first two have no per-program
    /// equivalent and verbs are an install-time action, not launch config.
    ///
    /// The variant's backend goes through
    /// ``GameConfigApplicator/effectiveBackend(_:isBackendAvailable:)``, so a
    /// backend this machine can't run becomes Recommended instead of falling
    /// back to WineD3D at launch. The user's own backend is left as chosen.
    static func merge(
        variant: GameConfigVariantSettings,
        dllOverrides: [DLLOverrideEntry]?,
        under userOverrides: ProgramOverrides?,
        isBackendAvailable: (GraphicsBackend) -> Bool = WhiskyWineInstaller.isBackendAvailable
    ) -> ProgramOverrides {
        var merged = userOverrides ?? ProgramOverrides()

        if merged.graphicsBackend == nil, let backend = variant.graphicsBackend {
            merged.graphicsBackend = GameConfigApplicator.effectiveBackend(
                backend, isBackendAvailable: isBackendAvailable
            )
        }
        merged.dxvk = merged.dxvk ?? variant.dxvk
        merged.dxvkAsync = merged.dxvkAsync ?? variant.dxvkAsync
        merged.enhancedSync = merged.enhancedSync ?? variant.enhancedSync
        merged.shaderCacheEnabled = merged.shaderCacheEnabled ?? variant.shaderCacheEnabled
        merged.dllOverrides = merged.dllOverrides ?? dllOverrides

        return merged
    }
}
