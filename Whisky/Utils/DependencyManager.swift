//
//  DependencyManager.swift
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

import Foundation
import os
import WhiskyKit

private let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "DependencyManager")

/// Static utility methods for checking and recommending Windows dependencies.
///
/// Follows the ``GPUDetection`` / ``GameMatcher`` caseless-enum pattern.
/// Checks dependency status by querying installed winetricks verbs through
/// the existing ``Winetricks.loadInstalledVerbs(for:)`` infrastructure.
///
/// ## Example
///
/// ```swift
/// let statuses = await DependencyManager.checkDependencies(for: bottle)
/// for status in statuses where status.status == .notInstalled {
///     print("\(status.definition.displayName) is not installed")
/// }
/// ```
enum DependencyManager {

    // MARK: - Status Checking

    /// Checks the installation status of dependencies for a bottle.
    ///
    /// Uses ``Winetricks/loadInstalledVerbs(for:)`` to get the current set
    /// of installed verbs, then maps each definition's required verbs against
    /// the installed set.
    ///
    /// - Parameters:
    ///   - bottle: The bottle to check.
    ///   - definitions: The dependency definitions to check. Defaults to
    ///     ``DependencyDefinition/standardDependencies``.
    /// - Returns: An array of ``DependencyStatus`` values, one per definition.
    static func checkDependencies(
        for bottle: Bottle,
        definitions: [DependencyDefinition] = DependencyDefinition.standardDependencies
    ) async -> [DependencyStatus] {
        let (installedVerbs, fromCache) = await Winetricks.loadInstalledVerbs(for: bottle)
        let confidence: DependencyConfidence = fromCache ? .cached : .authoritative
        let now = Date()

        return definitions.map { definition in
            let requiredVerbs = definition.winetricksVerbs
            let installed = requiredVerbs.filter { installedVerbs.contains($0) }
            let missing = requiredVerbs.filter { !installedVerbs.contains($0) }

            let installStatus: DependencyInstallStatus
            if missing.isEmpty {
                installStatus = .installed
            } else if installed.isEmpty {
                installStatus = .notInstalled
            } else {
                installStatus = .partiallyInstalled(installed: installed, missing: missing)
            }

            return DependencyStatus(
                id: definition.id,
                definition: definition,
                status: installStatus,
                lastChecked: now,
                confidence: confidence
            )
        }
    }

    // MARK: - Recommendations

    /// Suggests dependencies that a program likely needs based on evidence.
    ///
    /// Evidence sources (checked in order):
    /// 1. ClickOnce programs always need .NET Framework
    /// 2. Crash diagnosis history with ``CrashCategory/dependenciesLoading`` matches
    /// 3. Game database entries with required winetricks verbs
    ///
    /// Only returns recommendations backed by concrete evidence. Never
    /// recommends speculatively, per project decision.
    ///
    /// - Parameters:
    ///   - program: The program to generate recommendations for.
    ///   - bottle: The bottle containing the program.
    /// - Returns: Definitions that should be recommended for installation.
    static func recommendedDependencies(
        for program: Program,
        bottle: Bottle
    ) async -> [DependencyDefinition] {
        let programURL = await MainActor.run { program.url }
        let programName = await MainActor.run { program.name }
        let isClickOnce = await MainActor.run { program.isClickOnce }
        let dismissed = await MainActor.run {
            program.settings.dismissedDependencyRecommendations ?? []
        }

        var recommended: [String: DependencyDefinition] = [:]
        let definitions = DependencyDefinition.standardDependencies

        // 1. ClickOnce programs need .NET
        if isClickOnce {
            if let dotnet = definitions.first(where: { $0.id == "dotnet48" }) {
                recommended[dotnet.id] = dotnet
            }
        }

        // 2. Check crash diagnosis history for DLL-not-found patterns
        let bottleURL = await MainActor.run { bottle.url }
        let historyURL = bottleURL
            .appending(path: "Program Settings")
            .appending(path: programName)
            .appendingPathExtension("diagnosis-history.plist")
        let history = DiagnosisHistory.load(from: historyURL)

        let hasDependencyIssues = history.entries.contains { entry in
            entry.primaryCategory == .dependenciesLoading
        }

        if hasDependencyIssues {
            // Recommend vcruntime and directx as the most common missing dependencies
            if let vcRuntime = definitions.first(where: { $0.id == "vcruntime" }) {
                recommended[vcRuntime.id] = vcRuntime
            }
            if let directx = definitions.first(where: { $0.id == "directx" }) {
                recommended[directx.id] = directx
            }
        }

        // 3. Check game database for required verbs
        addGameDBRecommendations(programURL: programURL, definitions: definitions, into: &recommended)

        // Filter out dismissed recommendations
        return recommended.values
            .filter { !dismissed.contains($0.id) }
            .sorted { $0.id < $1.id }
    }

    /// Checks the game database for matching entries and adds recommended dependencies.
    private static func addGameDBRecommendations(
        programURL: URL,
        definitions: [DependencyDefinition],
        into recommended: inout [String: DependencyDefinition]
    ) {
        let metadata = ProgramMetadata(
            exeName: programURL.lastPathComponent,
            exeURL: programURL,
            installPath: programURL.deletingLastPathComponent().path(percentEncoded: false)
        )
        let gameDBEntries = GameDBLoader.loadDefaults()
        guard let match = GameMatcher.bestMatch(metadata: metadata, against: gameDBEntries) else { return }

        let variant = match.recommendedVariant ?? match.entry.variants.first(where: { $0.isDefault == true })
        guard let requiredVerbs = variant?.winetricksVerbs, !requiredVerbs.isEmpty else { return }

        for definition in definitions {
            let hasOverlap = definition.winetricksVerbs.contains { requiredVerbs.contains($0) }
            if hasOverlap {
                recommended[definition.id] = definition
            }
        }
    }

    // MARK: - Dismiss Tracking

    /// Records that a user has dismissed a dependency recommendation for a program.
    ///
    /// The recommendation will not reappear unless new evidence is found
    /// (e.g., a new crash diagnosis entry).
    ///
    /// - Parameters:
    ///   - definitionId: The ``DependencyDefinition/id`` to dismiss.
    ///   - program: The program whose recommendation is being dismissed.
    @MainActor
    static func dismissRecommendation(_ definitionId: String, for program: Program) {
        var dismissed = program.settings.dismissedDependencyRecommendations ?? []
        dismissed.insert(definitionId)
        program.settings.dismissedDependencyRecommendations = dismissed
        logger.debug("Dismissed dependency recommendation '\(definitionId)' for \(program.name)")
    }
}
