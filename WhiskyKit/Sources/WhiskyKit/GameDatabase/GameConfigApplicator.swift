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
/// with before/after values and an impact indicator. The text fields are
/// localized for display; match on ``kind`` instead of comparing them.
public struct ConfigChange: Sendable, Equatable {
    /// What a change sets, independent of the display language.
    public enum Kind: String, Sendable {
        case graphicsBackend
        case dxvk
        case dxvkAsync
        case enhancedSync
        case shaderCache
        case avx
        case dllOverride
        case environmentVariable
        case winetricksVerb
    }

    /// What this change sets.
    public let kind: Kind
    /// The localized category of the setting (e.g., "Graphics", "Performance").
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
        kind: Kind,
        category: String,
        settingName: String,
        currentValue: String,
        newValue: String,
        isHighImpact: Bool = false
    ) {
        self.kind = kind
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
    /// 1. Snapshots the current ``BottleSettings`` and the program environment
    ///    variables it replaces
    /// 2. Mutates the bottle's settings based on the variant
    /// 3. Applies the variant's environment variables to the game's launches
    ///    (see ``applyEnvironment(_:entry:to:targets:programURL:)``)
    /// 4. Saves the snapshot to the bottle directory
    /// 5. Returns the snapshot for display and future revert
    ///
    /// Winetricks verbs are not installed here: installing runs winetricks for
    /// minutes, so the app does it afterwards with progress, using
    /// ``pendingWinetricksVerbs(variant:installedVerbs:)``, and records what
    /// landed with ``recordInstalledVerbs(_:bottleURL:)``.
    ///
    /// - Parameters:
    ///   - entry: The game database entry being applied.
    ///   - variant: The specific variant to apply.
    ///   - bottle: The target bottle whose settings will be mutated.
    ///   - programURL: The program the configuration is applied from, if any. It
    ///     receives the environment variables.
    ///   - isBackendAvailable: Whether this machine can run a backend; see
    ///     ``effectiveBackend(_:isBackendAvailable:)``. Defaults to the installed runtime.
    /// - Returns: The snapshot created before applying changes.
    /// - Throws: An error if the snapshot cannot be encoded or saved.
    @MainActor
    public static func apply(
        entry: GameDBEntry,
        variant: GameConfigVariant,
        to bottle: Bottle,
        programURL: URL? = nil,
        isBackendAvailable: (GraphicsBackend) -> Bool = WhiskyWineInstaller.isBackendAvailable
    ) throws -> GameConfigSnapshot {
        // 1. Snapshot current state
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let bottleSettingsData = try encoder.encode(bottle.settings)

        // 2. Create snapshot. No verbs are installed yet; the app records the
        // ones that install with recordInstalledVerbs.
        var snapshot = GameConfigSnapshot(
            bottleSettingsData: bottleSettingsData,
            appliedEntryId: entry.id,
            appliedVariantId: variant.id,
            timestamp: Date()
        )

        // Record the program environment variables this apply replaces
        let environmentTargets = environmentTargets(entry: entry, bottle: bottle, programURL: programURL)
        snapshotEnvironment(variant.environmentVariables ?? [:], of: environmentTargets, into: &snapshot)

        // 3. Apply variant settings to bottle
        applyVariantSettings(variant.settings, to: bottle, isBackendAvailable: isBackendAvailable)

        // 4. Apply DLL overrides (deduplicate by DLL name, prefer variant value)
        if let overrides = variant.dllOverrides, !overrides.isEmpty {
            applyDLLOverrides(overrides, to: bottle)
        }

        // 5. Apply custom environment variables to the game's launches
        if let variables = variant.environmentVariables {
            applyEnvironment(
                variables, entry: entry, to: bottle, targets: environmentTargets, programURL: programURL
            )
        }

        // 6. Save snapshot to bottle directory
        try GameConfigSnapshot.save(snapshot, to: bottle.url)

        return snapshot
    }

    // MARK: - Revert

    /// Reverts a bottle's settings to the state captured in the snapshot.
    ///
    /// Decodes the snapshot's ``GameConfigSnapshot/bottleSettingsData`` and replaces
    /// the bottle's settings entirely, then puts back the program environment
    /// variables in ``GameConfigSnapshot/programEnvironments``. The `didSet`
    /// observers handle automatic persistence.
    ///
    /// - Parameters:
    ///   - bottle: The bottle whose settings will be restored.
    ///   - snapshot: The snapshot from a previous ``apply(entry:variant:to:programURL:)`` call.
    /// - Returns: A list of winetricks verbs that were installed after the original apply
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
        restoreProgramEnvironments(from: snapshot, in: bottle)

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

    // swiftlint:disable function_body_length
    /// Generates a preview of what settings would change if a variant were applied.
    ///
    /// Compares each non-nil field in the variant's settings against the current
    /// bottle settings and returns an array of ``ConfigChange`` values grouped
    /// by category.
    ///
    /// - Parameters:
    ///   - variant: The variant to preview.
    ///   - bottle: The bottle whose current settings are compared.
    ///   - entry: The entry the variant belongs to. With it, environment variables
    ///     are compared against where the apply puts them; without it they are
    ///     all listed as not set.
    ///   - programURL: The program the configuration is applied from, if any.
    ///   - installedVerbs: The winetricks verbs the bottle already has, which are
    ///     left out of the verbs to install.
    ///   - isBackendAvailable: Whether this machine can run a backend, so the
    ///     preview shows the backend ``apply(entry:variant:to:programURL:isBackendAvailable:)``
    ///     will actually set. Defaults to the installed runtime.
    /// - Returns: An array of changes, with high-impact changes flagged.
    @MainActor
    public static func previewChanges(
        variant: GameConfigVariant,
        bottle: Bottle,
        entry: GameDBEntry? = nil,
        programURL: URL? = nil,
        installedVerbs: Set<String> = [],
        isBackendAvailable: (GraphicsBackend) -> Bool = WhiskyWineInstaller.isBackendAvailable
    ) -> [ConfigChange] {
        var changes: [ConfigChange] = []
        let settings = variant.settings
        let graphics = String(localized: "gameConfig.detail.graphics")
        let performance = String(localized: "gameConfig.detail.performance")
        let notSet = String(localized: "gameConfig.preview.value.notSet")

        // Graphics settings
        if let wanted = settings.graphicsBackend,
           case let backend = effectiveBackend(wanted, isBackendAvailable: isBackendAvailable),
           backend != bottle.settings.graphicsBackend {
            changes.append(ConfigChange(
                kind: .graphicsBackend,
                category: graphics,
                settingName: String(localized: "config.graphics.backend"),
                currentValue: bottle.settings.graphicsBackend.displayName,
                newValue: backend.displayName,
                isHighImpact: true
            ))
        }

        if settings.graphicsBackend == nil, let dxvk = settings.dxvk, dxvk != bottle.settings.dxvk {
            changes.append(ConfigChange(
                kind: .dxvk,
                category: graphics,
                settingName: "DXVK",
                currentValue: describeEnabled(bottle.settings.dxvk),
                newValue: describeEnabled(dxvk),
                isHighImpact: true
            ))
        }

        if let dxvkAsync = settings.dxvkAsync, dxvkAsync != bottle.settings.dxvkAsync {
            changes.append(ConfigChange(
                kind: .dxvkAsync,
                category: graphics,
                settingName: String(localized: "config.dxvk.async"),
                currentValue: describeEnabled(bottle.settings.dxvkAsync),
                newValue: describeEnabled(dxvkAsync)
            ))
        }

        // Performance settings
        if let enhancedSync = settings.enhancedSync, enhancedSync != bottle.settings.enhancedSync {
            changes.append(ConfigChange(
                kind: .enhancedSync,
                category: performance,
                settingName: String(localized: "config.enhancedSync"),
                currentValue: describeEnhancedSync(bottle.settings.enhancedSync),
                newValue: describeEnhancedSync(enhancedSync)
            ))
        }

        if let shaderCache = settings.shaderCacheEnabled, shaderCache != bottle.settings.shaderCacheEnabled {
            changes.append(ConfigChange(
                kind: .shaderCache,
                category: performance,
                settingName: String(localized: "config.shaderCache"),
                currentValue: describeEnabled(bottle.settings.shaderCacheEnabled),
                newValue: describeEnabled(shaderCache)
            ))
        }

        if let avx = settings.avxEnabled, avx != bottle.settings.avxEnabled {
            changes.append(ConfigChange(
                kind: .avx,
                category: performance,
                settingName: String(localized: "gameConfig.preview.setting.avx"),
                currentValue: describeEnabled(bottle.settings.avxEnabled),
                newValue: describeEnabled(avx)
            ))
        }

        // DLL overrides
        if let overrides = variant.dllOverrides, !overrides.isEmpty {
            let existingNames = Set(bottle.settings.dllOverrides.map(\.dllName))
            let newOverrides = overrides.filter { !existingNames.contains($0.dllName) }
            let updatedOverrides = overrides.filter { existingNames.contains($0.dllName) }

            for override in newOverrides {
                changes.append(ConfigChange(
                    kind: .dllOverride,
                    category: String(localized: "gameConfig.detail.dllOverrides"),
                    settingName: override.dllName,
                    currentValue: notSet,
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
                        kind: .dllOverride,
                        category: String(localized: "gameConfig.detail.dllOverrides"),
                        settingName: override.dllName,
                        currentValue: existing.mode.displayName,
                        newValue: override.mode.displayName,
                        isHighImpact: true
                    ))
                }
            }
        }

        // Environment variables
        changes += environmentChanges(variant: variant, entry: entry, bottle: bottle, programURL: programURL)

        // Winetricks verbs
        changes += winetricksChanges(variant: variant, installedVerbs: installedVerbs)

        return changes
    }

    // swiftlint:enable function_body_length

    // MARK: - Backend Availability

    /// The backend a variant's `graphicsBackend` puts the bottle on.
    ///
    /// A backend this machine can't run becomes ``GraphicsBackend/recommended``:
    /// D3DMetal without the GPTK payload, or DXMT without the runtime's native
    /// payload. Set as written, such a bottle falls back to WineD3D at launch,
    /// which can't bring up D3D11 on current macOS (#146). Recommended resolves to
    /// the best backend that is installed, which is D3DMetal itself whenever its
    /// payload is present.
    ///
    /// - Parameters:
    ///   - backend: The backend the variant asks for.
    ///   - isBackendAvailable: Whether this machine can run a backend.
    /// - Returns: `backend`, or `.recommended` when it isn't available.
    public static func effectiveBackend(
        _ backend: GraphicsBackend,
        isBackendAvailable: (GraphicsBackend) -> Bool = WhiskyWineInstaller.isBackendAvailable
    ) -> GraphicsBackend {
        isBackendAvailable(backend) ? backend : .recommended
    }

    // MARK: - Private Helpers

    /// Applies variant settings to the bottle's settings.
    @MainActor
    private static func applyVariantSettings(
        _ settings: GameConfigVariantSettings,
        to bottle: Bottle,
        isBackendAvailable: (GraphicsBackend) -> Bool
    ) {
        // `dxvk` is the legacy backend switch: its setter maps `false` back to
        // Recommended, so applying it after an explicit backend undid the
        // backend. An explicit backend wins; `dxvk` only speaks when there is
        // none.
        if let graphicsBackend = settings.graphicsBackend {
            bottle.settings.graphicsBackend = effectiveBackend(
                graphicsBackend, isBackendAvailable: isBackendAvailable
            )
        } else if let dxvk = settings.dxvk {
            bottle.settings.dxvk = dxvk
        }

        if let dxvkAsync = settings.dxvkAsync {
            bottle.settings.dxvkAsync = dxvkAsync
        }

        if let enhancedSync = settings.enhancedSync {
            bottle.settings.enhancedSync = enhancedSync
        }

        if let shaderCacheEnabled = settings.shaderCacheEnabled {
            bottle.settings.shaderCacheEnabled = shaderCacheEnabled
        }

        if let avxEnabled = settings.avxEnabled {
            bottle.settings.avxEnabled = avxEnabled
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

    /// Returns a localized description of an EnhancedSync value.
    private static func describeEnhancedSync(_ sync: EnhancedSync) -> String {
        switch sync {
        case .none:
            String(localized: "config.enhancedSync.none")
        case .esync:
            String(localized: "config.enhancedSync.esync")
        case .msync:
            String(localized: "config.enhancedSync.msync")
        }
    }

    /// Returns a localized description of an on/off setting.
    private static func describeEnabled(_ isEnabled: Bool) -> String {
        isEnabled ? String(localized: "config.retinaMode.on") : String(localized: "config.retinaMode.off")
    }
}

// swiftlint:enable file_length
