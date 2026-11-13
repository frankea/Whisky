//
//  GameConfigApplicator+Components.swift
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

// MARK: - Environment Variables

extension GameConfigApplicator {
    /// The programs in the bottle a configuration's environment variables go to.
    ///
    /// The program the configuration is applied from wins when it is in the
    /// bottle; otherwise every program whose file name is one of the entry's
    /// `exeNames`, ignoring case.
    ///
    /// - Parameters:
    ///   - entry: The game database entry being applied.
    ///   - bottle: The bottle the configuration is applied to.
    ///   - programURL: The program the configuration is applied from, if any.
    /// - Returns: The programs to write the variables into; empty when the
    ///   game isn't among the bottle's programs.
    @MainActor
    public static func environmentTargets(
        entry: GameDBEntry,
        bottle: Bottle,
        programURL: URL?
    ) -> [Program] {
        if let programURL, let program = bottle.programs.first(where: { $0.url == programURL }) {
            return [program]
        }
        let names = (entry.exeNames ?? []).map { $0.lowercased() }
        guard !names.isEmpty else { return [] }
        return bottle.programs.filter { names.contains($0.url.lastPathComponent.lowercased()) }
    }

    /// The executable names a bottle-level ``GameConfigEnvironment`` is scoped to.
    static func environmentExecutables(entry: GameDBEntry, programURL: URL?) -> [String] {
        var names = entry.exeNames ?? []
        if let name = programURL?.lastPathComponent,
           !names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            names.append(name)
        }
        return names
    }

    /// Records in `snapshot` the environment variables applying `variables`
    /// replaces in each of `programs`, so a revert can put back just those.
    ///
    /// Programs are not recorded when the variant sets no variables, since the
    /// apply leaves them unchanged.
    @MainActor
    static func snapshotEnvironment(
        _ variables: [String: String],
        of programs: [Program],
        into snapshot: inout GameConfigSnapshot
    ) {
        guard !variables.isEmpty, !programs.isEmpty else { return }
        var records = snapshot.programEnvironments ?? [:]
        for program in programs {
            records[program.url.absoluteString] = GameConfigProgramEnvironment(
                applying: variables, to: program.settings.environment
            )
        }
        snapshot.programEnvironments = records
    }

    /// Makes a variant's environment variables part of every launch of the game.
    ///
    /// They go into the environment of each of ``environmentTargets(entry:bottle:programURL:)``,
    /// where the program's settings show them and the user can edit them, a
    /// variant value replacing the program's own for the same variable. When
    /// the game isn't in the bottle they are kept as a ``GameConfigEnvironment``
    /// in the bottle settings, scoped to the game's executables, replacing any
    /// earlier record for the same entry.
    @MainActor
    static func applyEnvironment(
        _ variables: [String: String],
        entry: GameDBEntry,
        to bottle: Bottle,
        targets: [Program],
        programURL: URL?
    ) {
        guard !variables.isEmpty else { return }
        if !targets.isEmpty {
            for program in targets {
                program.settings.environment.merge(variables) { _, new in new }
            }
            return
        }
        var records = bottle.settings.gameConfigEnvironments.filter { $0.entryId != entry.id }
        records.append(GameConfigEnvironment(
            entryId: entry.id,
            title: entry.title,
            executables: environmentExecutables(entry: entry, programURL: programURL),
            variables: variables
        ))
        bottle.settings.gameConfigEnvironments = records
    }

    /// Preview rows for the variant's environment variables.
    ///
    /// With an `entry`, each row compares against where
    /// ``apply(entry:variant:to:programURL:isBackendAvailable:)`` will put the
    /// variable, and variables already set to the variant's value are left
    /// out. Without one, every variable is listed as not set.
    @MainActor
    static func environmentChanges(
        variant: GameConfigVariant,
        entry: GameDBEntry?,
        bottle: Bottle,
        programURL: URL?
    ) -> [ConfigChange] {
        guard let variables = variant.environmentVariables, !variables.isEmpty else { return [] }
        let notSet = String(localized: "gameConfig.preview.value.notSet")
        let current: (String) -> [String?]
        if let entry {
            let targets = environmentTargets(entry: entry, bottle: bottle, programURL: programURL)
            if targets.isEmpty {
                let record = bottle.settings.gameConfigEnvironments.first { $0.entryId == entry.id }
                current = { [record?.variables[$0]] }
            } else {
                current = { key in targets.map { $0.settings.environment[key] } }
            }
        } else {
            current = { _ in [nil] }
        }

        return variables.sorted(by: { $0.key < $1.key }).compactMap { key, value in
            let values = current(key)
            guard values.contains(where: { $0 != value }) else { return nil }
            return ConfigChange(
                kind: .environmentVariable,
                category: String(localized: "program.env"),
                settingName: key,
                currentValue: values.first { $0 != value }.flatMap { $0 } ?? notSet,
                newValue: value
            )
        }
    }

    /// Puts back the program environment variables a snapshot recorded,
    /// leaving the rest of each program's settings alone.
    ///
    /// Programs the bottle no longer lists are restored through a fresh
    /// ``Program`` as long as their executable still exists, so the settings
    /// file is right when the program shows up again.
    @MainActor
    static func restoreProgramEnvironments(from snapshot: GameConfigSnapshot, in bottle: Bottle) {
        guard let records = snapshot.programEnvironments else { return }
        for (urlString, record) in records {
            guard let url = URL(string: urlString) else { continue }
            let program: Program
            if let listed = bottle.programs.first(where: { $0.url == url }) {
                program = listed
            } else if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                program = Program(url: url, bottle: bottle)
            } else {
                continue
            }
            let restored = record.reverting(program.settings.environment)
            if restored != program.settings.environment {
                program.settings.environment = restored
            }
        }
    }
}

// MARK: - Program Match

extension GameConfigApplicator {
    /// The GameDB entry a program matches confidently, with the variant the
    /// troubleshooter's `apply-game-config` fix applies: the entry's default.
    ///
    /// - Parameters:
    ///   - program: The program to match.
    ///   - entries: The entries to match against. Defaults to the bundled database.
    /// - Returns: The entry and its default variant, or `nil` without a confident match.
    @MainActor
    public static func recommendedConfiguration(
        for program: Program,
        entries: [GameDBEntry]? = nil
    ) -> (entry: GameDBEntry, variant: GameConfigVariant)? {
        guard let match = GameMatcher.bestMatch(
            metadata: ProgramMetadata(exeName: program.url.lastPathComponent, exeURL: program.url),
            against: entries ?? GameDBLoader.loadDefaults()
        ),
            let variant = match.entry.defaultVariant
        else {
            return nil
        }
        return (match.entry, variant)
    }
}

// MARK: - Winetricks Verbs

extension GameConfigApplicator {
    /// Preview rows for the verbs the variant needs that aren't installed.
    static func winetricksChanges(
        variant: GameConfigVariant,
        installedVerbs: Set<String>
    ) -> [ConfigChange] {
        pendingWinetricksVerbs(variant: variant, installedVerbs: installedVerbs).map { verb in
            ConfigChange(
                kind: .winetricksVerb,
                category: String(localized: "gameConfig.detail.winetricks"),
                settingName: verb,
                currentValue: String(localized: "gameConfig.preview.value.notInstalled"),
                newValue: String(localized: "gameConfig.preview.value.willInstall")
            )
        }
    }

    /// Adds verbs an apply installed to the bottle's saved snapshot, so the
    /// revert UI can say which components stay behind.
    ///
    /// Does nothing when the bottle has no snapshot or `verbs` is empty.
    ///
    /// - Parameters:
    ///   - verbs: The verbs that installed successfully.
    ///   - bottleURL: The bottle the configuration was applied to.
    /// - Throws: An error if the updated snapshot cannot be saved.
    public static func recordInstalledVerbs(_ verbs: [String], bottleURL: URL) throws {
        guard !verbs.isEmpty, var snapshot = GameConfigSnapshot.load(from: bottleURL) else { return }
        var recorded = snapshot.installedVerbs ?? []
        for verb in verbs where !recorded.contains(verb) {
            recorded.append(verb)
        }
        snapshot.installedVerbs = recorded
        try GameConfigSnapshot.save(snapshot, to: bottleURL)
    }
}
