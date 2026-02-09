//
//  WineEnvironment.swift
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

private let envLogger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "WineEnvironment")

extension Wine {
    /// Construct an environment merging the bottle values with the given values
    /// using EnvironmentBuilder with 8-layer resolution.
    ///
    /// Each Wine process launch resolves through this method, which populates
    /// an ``EnvironmentBuilder`` with base, platform, bottleManaged, launcherManaged,
    /// bottleUser, programUser, featureRuntime, and callsiteOverride layers.
    /// WINEDLLOVERRIDES is composed per-DLL via ``DLLOverrideResolver``.
    ///
    /// Invalid environment variable keys (those not matching `[A-Za-z_][A-Za-z0-9_]*`)
    /// are filtered out with a debug log message, as macOS silently ignores them.
    @MainActor
    public static func constructWineEnvironment(
        for bottle: Bottle, environment: [String: String] = [:]
    ) -> [String: String] {
        var builder = EnvironmentBuilder()
        var dllResolver = DLLOverrideResolver(managed: [], bottleCustom: [], programCustom: [])

        // Layer 1: Base -- WINEPREFIX, default WINEDEBUG, GST_DEBUG
        builder.set("WINEPREFIX", bottle.url.path, layer: .base)
        builder.set("WINEDEBUG", "fixme-all", layer: .base)
        builder.set("GST_DEBUG", "1", layer: .base)

        // Layer 2: Platform -- macOS compatibility fixes
        // Collect fixes into a temp dict, then apply to the platform layer.
        // MacOSCompatibility.swift is not modified; we adapt the call pattern.
        var platformFixes: [String: String] = [:]
        applyMacOSCompatibilityFixes(to: &platformFixes)
        builder.setAll(platformFixes, layer: .platform)

        // Layer 3: Bottle managed -- settings-derived env vars (DXVK, sync, Metal, perf)
        let managedOverrides = bottle.settings.populateBottleManagedLayer(builder: &builder)
        dllResolver.managed.append(contentsOf: managedOverrides)

        // Layer 4: Launcher managed -- launcher compatibility overrides
        let launcherOverrides = bottle.settings.populateLauncherManagedLayer(builder: &builder)
        dllResolver.managed.append(contentsOf: launcherOverrides)

        // Input compatibility (bottleManaged layer -- input settings are bottle-managed toggles)
        bottle.settings.populateInputCompatibilityLayer(builder: &builder)

        // Layer 5: Bottle user (empty for now -- no bottle-level custom env vars UI yet)

        // Layer 6: Program user (caller-provided environment dict, typically from Program.generateEnvironment())
        if !environment.isEmpty {
            for (key, value) in environment {
                if isValidEnvKey(key) {
                    builder.set(key, value, layer: .programUser)
                } else {
                    envLogger.debug("Skipping invalid environment key '\(key)' in constructWineEnvironment")
                }
            }
        }

        // Layers 7-8: featureRuntime and callsiteOverride are left empty
        // (populated by future phases or direct callers)

        // Collect bottle custom DLL overrides for the resolver
        dllResolver.bottleCustom = bottle.settings.dllOverrides

        // Resolve the builder and store provenance (used by Phase 5 diagnostics)
        let (resolved, _) = builder.resolve()
        var result = resolved

        // Compose WINEDLLOVERRIDES from DLLOverrideResolver (outside the builder)
        let (overrideString, _) = dllResolver.resolve()
        if !overrideString.isEmpty {
            result["WINEDLLOVERRIDES"] = overrideString
        }

        return result
    }
}
