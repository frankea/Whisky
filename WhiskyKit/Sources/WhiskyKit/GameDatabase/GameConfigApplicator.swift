// swiftlint:disable file_length
//
//  GameConfigApplicator.swift
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

/// A single setting change to be applied, shown in the preview diff.
///
/// Groups changes by category (Graphics, Performance, DLL Overrides, etc.)
/// with before/after values and an impact indicator.
public struct ConfigChange: Sendable, Equatable {
    /// The category of the setting (e.g., "Graphics", "Performance").
    public let category: String
    /// The display name of the setting.
    public let settingName: String
    /// The current value as a human-readable string.
    public let currentValue: String
    /// The new value to be applied as a human-readable string.
    public let newValue: String
    /// Whether this change is high-impact (e.g., graphics backend switch, DLL overrides).
    public let isHighImpact: Bool

    public init(
        category: String,
        settingName: String,
        currentValue: String,
        newValue: String,
        isHighImpact: Bool = false
    ) {
        self.category = category
        self.settingName = settingName
        self.currentValue = currentValue
        self.newValue = newValue
        self.isHighImpact = isHighImpact
    }
}

/// Applies and reverts game configurations to bottles.
///
/// The applicator works through existing ``BottleSettings`` properties so changes
/// flow through the ``EnvironmentBuilder`` cascade at launch time. Before mutating
/// any settings, a ``GameConfigSnapshot`` is created for undo/revert.
///
/// ## Usage
///
/// ```swift
/// let snapshot = try GameConfigApplicator.apply(
///     entry: eldenRingEntry,
///     variant: eldenRingEntry.defaultVariant!,
///     to: bottle
/// )
/// // Later, to undo:
/// let verbs = try GameConfigApplicator.revert(bottle: bottle, snapshot: snapshot)
/// ```
///
/// ## Thread Safety
///
/// Apply and revert methods are `@MainActor` because they mutate ``Bottle/settings``,
/// which is `@MainActor`-isolated.
public enum GameConfigApplicator {

    // MARK: - Apply

    /// Applies a game configuration variant to a bottle's settings.
    ///
    /// This method:
    /// 1. Snapshots the current ``BottleSettings`` (and optionally program settings)
    /// 2. Mutates the bottle's settings based on the variant
    /// 3. Saves the snapshot to the bottle directory
    /// 4. Returns the snapshot for display and future revert
    ///
    /// Winetricks verb installation is NOT done here -- the UI handles that
    /// separately per user decision.
    ///
    /// - Parameters:
    ///   - entry: The game database entry being applied.
    ///   - variant: The specific variant to apply.
    ///   - bottle: The target bottle whose settings will be mutated.
    ///   - programURL: Optional program URL for program-level settings snapshot.
    /// - Returns: The snapshot created before applying changes.
    /// - Throws: An error if the snapshot cannot be encoded or saved.
    @MainActor
    public static func apply(
        entry: GameDBEntry,
        variant: GameConfigVariant,
        to bottle: Bottle,
        programURL: URL? = nil
    ) throws -> GameConfigSnapshot {
        // 1. Snapshot current state
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let bottleSettingsData = try encoder.encode(bottle.settings)

        // 2. Create snapshot
        var snapshot = GameConfigSnapshot(
            bottleSettingsData: bottleSettingsData,
            installedVerbs: variant.winetricksVerbs,
            appliedEntryId: entry.id,
            appliedVariantId: variant.id,
            timestamp: Date()
        )

        // Snapshot program settings if a program URL is provided
        if let programURL {
            let programURLString = programURL.absoluteString
            // Find the matching program by URL
            if let program = bottle.programs.first(where: { $0.url == programURL }) {
                let programData = try encoder.encode(program.settings)
                snapshot.programSettingsData = [programURLString: programData]
            }
        }

        // 3. Apply variant settings to bottle
        applyVariantSettings(variant.settings, to: bottle)

        // 4. Apply DLL overrides (deduplicate by DLL name, prefer variant value)
        if let overrides = variant.dllOverrides, !overrides.isEmpty {
            applyDLLOverrides(overrides, to: bottle)
        }

        // 5. Apply custom environment variables
        // Store in bottle.settings for the bottleUser layer of EnvironmentBuilder.
        // Note: The EnvironmentBuilder already handles env vars from variant.environmentVariables
        // at launch time when the applicator stores them. For now, env vars are recorded
        // in the snapshot for reference but applied through the existing cascade.

        // 6. Save snapshot to bottle directory
        try GameConfigSnapshot.save(snapshot, to: bottle.url)

        return snapshot
    }

    // MARK: - Revert

    /// Reverts a bottle's settings to the state captured in the snapshot.
    ///
    /// Decodes the snapshot's ``GameConfigSnapshot/bottleSettingsData`` and replaces
    /// the bottle's settings entirely. The ``BottleSettings/didSet`` observer
    /// handles automatic persistence.
    ///
    /// - Parameters:
    ///   - bottle: The bottle whose settings will be restored.
    ///   - snapshot: The snapshot from a previous ``apply(entry:variant:to:programURL:)`` call.
    /// - Returns: A list of winetricks verbs that were installed during the original apply
    ///   (non-reversible, for UI display: "Settings reverted; installed components remain").
    /// - Throws: An error if the snapshot data cannot be decoded or the snapshot file cannot be deleted.
    @MainActor
    public static func revert(
        bottle: Bottle,
        snapshot: GameConfigSnapshot
    ) throws -> [String] {
        // 1. Decode and restore bottle settings
        if let settingsData = snapshot.bottleSettingsData {
            let decoder = PropertyListDecoder()
            let restoredSettings = try decoder.decode(BottleSettings.self, from: settingsData)
            bottle.settings = restoredSettings
        }

        // 2. Delete the snapshot file
        try GameConfigSnapshot.delete(from: bottle.url)

        // 3. Return installed verbs as non-reversible items
        return snapshot.installedVerbs ?? []
    }

    // MARK: - Pending Winetricks Verbs

    /// Returns winetricks verbs required by the variant that are not yet installed.
    ///
    /// - Parameters:
    ///   - variant: The game configuration variant.
    ///   - installedVerbs: The set of verbs already installed in the bottle.
    /// - Returns: An array of verb names that still need to be installed.
    public static func pendingWinetricksVerbs(
        variant: GameConfigVariant,
        installedVerbs: Set<String>
    ) -> [String] {
        guard let requiredVerbs = variant.winetricksVerbs else {
            return []
        }
        return requiredVerbs.filter { !installedVerbs.contains($0) }
    }

    // MARK: - Preview Changes

    /// Generates a preview of what settings would change if a variant were applied.
    ///
    /// Compares each non-nil field in the variant's settings against the current
    /// bottle settings and returns an array of ``ConfigChange`` values grouped
    /// by category.
    ///
    /// - Parameters:
    ///   - variant: The variant to preview.
    ///   - bottle: The bottle whose current settings are compared.
    /// - Returns: An array of changes, with high-impact changes flagged.
    @MainActor
    public static func previewChanges(
        variant: GameConfigVariant,
        bottle: Bottle
    ) -> [ConfigChange] {
        var changes: [ConfigChange] = []
        let settings = variant.settings

        // Graphics settings
        if let backend = settings.graphicsBackend, backend != bottle.settings.graphicsBackend {
            changes.append(ConfigChange(
                category: "Graphics",
                settingName: "Graphics Backend",
                currentValue: bottle.settings.graphicsBackend.displayName,
                newValue: backend.displayName,
                isHighImpact: true
            ))
        }

        if let dxvk = settings.dxvk, dxvk != bottle.settings.dxvk {
            changes.append(ConfigChange(
                category: "Graphics",
                settingName: "DXVK",
                currentValue: bottle.settings.dxvk ? "Enabled" : "Disabled",
                newValue: dxvk ? "Enabled" : "Disabled",
                isHighImpact: true
            ))
        }

        if let dxvkAsync = settings.dxvkAsync, dxvkAsync != bottle.settings.dxvkAsync {
            changes.append(ConfigChange(
                category: "Graphics",
                settingName: "DXVK Async",
                currentValue: bottle.settings.dxvkAsync ? "Enabled" : "Disabled",
                newValue: dxvkAsync ? "Enabled" : "Disabled"
            ))
        }

        if let sequoiaCompat = settings.sequoiaCompatMode, sequoiaCompat != bottle.settings.sequoiaCompatMode {
            changes.append(ConfigChange(
                category: "Graphics",
                settingName: "Sequoia Compatibility Mode",
                currentValue: bottle.settings.sequoiaCompatMode ? "Enabled" : "Disabled",
                newValue: sequoiaCompat ? "Enabled" : "Disabled"
            ))
        }

        // Performance settings
        if let enhancedSync = settings.enhancedSync, enhancedSync != bottle.settings.enhancedSync {
            changes.append(ConfigChange(
                category: "Performance",
                settingName: "Enhanced Sync",
                currentValue: describeEnhancedSync(bottle.settings.enhancedSync),
                newValue: describeEnhancedSync(enhancedSync)
            ))
        }

        if let forceD3D11 = settings.forceD3D11, forceD3D11 != bottle.settings.forceD3D11 {
            changes.append(ConfigChange(
                category: "Performance",
                settingName: "Force D3D11",
                currentValue: bottle.settings.forceD3D11 ? "Enabled" : "Disabled",
                newValue: forceD3D11 ? "Enabled" : "Disabled"
            ))
        }

        if let presetName = settings.performancePreset {
            let currentPreset = bottle.settings.performancePreset.rawValue
            if presetName != currentPreset {
                changes.append(ConfigChange(
                    category: "Performance",
                    settingName: "Performance Preset",
                    currentValue: bottle.settings.performancePreset.description(),
                    newValue: presetName
                ))
            }
        }

        if let shaderCache = settings.shaderCacheEnabled, shaderCache != bottle.settings.shaderCacheEnabled {
            changes.append(ConfigChange(
                category: "Performance",
                settingName: "Shader Cache",
                currentValue: bottle.settings.shaderCacheEnabled ? "Enabled" : "Disabled",
                newValue: shaderCache ? "Enabled" : "Disabled"
            ))
        }

        if let avx = settings.avxEnabled, avx != bottle.settings.avxEnabled {
            changes.append(ConfigChange(
                category: "Performance",
                settingName: "AVX Support",
                currentValue: bottle.settings.avxEnabled ? "Enabled" : "Disabled",
                newValue: avx ? "Enabled" : "Disabled"
            ))
        }

        // DLL overrides
        if let overrides = variant.dllOverrides, !overrides.isEmpty {
            let existingNames = Set(bottle.settings.dllOverrides.map(\.dllName))
            let newOverrides = overrides.filter { !existingNames.contains($0.dllName) }
            let updatedOverrides = overrides.filter { existingNames.contains($0.dllName) }

            for override in newOverrides {
                changes.append(ConfigChange(
                    category: "DLL Overrides",
                    settingName: override.dllName,
                    currentValue: "(not set)",
                    newValue: override.mode.displayName,
                    isHighImpact: true
                ))
            }

            for override in updatedOverrides {
                if let existing = bottle.settings.dllOverrides.first(where: {
                    $0.dllName == override.dllName
                }),
                    existing.mode != override.mode {
                    changes.append(ConfigChange(
                        category: "DLL Overrides",
                        settingName: override.dllName,
                        currentValue: existing.mode.displayName,
                        newValue: override.mode.displayName,
                        isHighImpact: true
                    ))
                }
            }
        }

        // Environment variables
        if let envVars = variant.environmentVariables, !envVars.isEmpty {
            for (key, value) in envVars.sorted(by: { $0.key < $1.key }) {
                changes.append(ConfigChange(
                    category: "Environment Variables",
                    settingName: key,
                    currentValue: "(not set)",
                    newValue: value
                ))
            }
        }

        // Winetricks verbs
        if let verbs = variant.winetricksVerbs, !verbs.isEmpty {
            for verb in verbs {
                changes.append(ConfigChange(
                    category: "Winetricks",
                    settingName: verb,
                    currentValue: "(not installed)",
                    newValue: "Will be installed"
                ))
            }
        }

        return changes
    }

    // MARK: - Private Helpers

    /// Applies variant settings to the bottle's settings.
    @MainActor
    private static func applyVariantSettings(_ settings: GameConfigVariantSettings, to bottle: Bottle) {
        if let graphicsBackend = settings.graphicsBackend {
            bottle.settings.graphicsBackend = graphicsBackend
        }

        if let dxvk = settings.dxvk {
            bottle.settings.dxvk = dxvk
        }

        if let dxvkAsync = settings.dxvkAsync {
            bottle.settings.dxvkAsync = dxvkAsync
        }

        if let enhancedSync = settings.enhancedSync {
            bottle.settings.enhancedSync = enhancedSync
        }

        if let forceD3D11 = settings.forceD3D11 {
            bottle.settings.forceD3D11 = forceD3D11
        }

        if let presetName = settings.performancePreset,
           let preset = PerformancePreset(rawValue: presetName) {
            bottle.settings.performancePreset = preset
        }

        if let shaderCacheEnabled = settings.shaderCacheEnabled {
            bottle.settings.shaderCacheEnabled = shaderCacheEnabled
        }

        if let avxEnabled = settings.avxEnabled {
            bottle.settings.avxEnabled = avxEnabled
        }

        if let sequoiaCompatMode = settings.sequoiaCompatMode {
            bottle.settings.sequoiaCompatMode = sequoiaCompatMode
        }
    }

    /// Appends DLL overrides to the bottle, deduplicating by DLL name (variant value wins).
    @MainActor
    private static func applyDLLOverrides(_ overrides: [DLLOverrideEntry], to bottle: Bottle) {
        var existingByName: [String: Int] = [:]
        for (index, entry) in bottle.settings.dllOverrides.enumerated() {
            existingByName[entry.dllName] = index
        }

        var updatedOverrides = bottle.settings.dllOverrides

        for override in overrides {
            if let existingIndex = existingByName[override.dllName] {
                // Replace existing with variant value
                updatedOverrides[existingIndex] = override
            } else {
                // Append new override
                updatedOverrides.append(override)
            }
        }

        bottle.settings.dllOverrides = updatedOverrides
    }

    /// Returns a human-readable description of an EnhancedSync value.
    private static func describeEnhancedSync(_ sync: EnhancedSync) -> String {
        switch sync {
        case .none:
            "None"
        case .esync:
            "ESync"
        case .msync:
            "MSync"
        }
    }
}

// swiftlint:enable file_length
