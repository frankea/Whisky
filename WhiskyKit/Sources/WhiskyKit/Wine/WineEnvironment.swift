// swiftlint:disable function_body_length
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

// swiftlint:disable cyclomatic_complexity
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
    ///
    /// - Parameters:
    ///   - bottle: The bottle whose settings configure the environment.
    ///   - environment: Caller-provided environment variables (typically from `Program.generateEnvironment()`).
    ///   - programOverrides: Optional per-program setting overrides. `nil` fields inherit from bottle.
    /// - Returns: The fully resolved environment dictionary for passing to a Wine process.
    @MainActor
    public static func constructWineEnvironment(
        for bottle: Bottle,
        environment: [String: String] = [:],
        programOverrides: ProgramOverrides? = nil,
        programSettings: ProgramSettings? = nil
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

        // Apply per-program overrides to the programUser layer
        if let overrides = programOverrides {
            applyProgramOverrides(overrides, builder: &builder, dllResolver: &dllResolver)
        }

        // Layer 7: featureRuntime -- diagnostic WINEDEBUG preset override
        if let preset = programSettings?.activeWineDebugPreset, preset != .normal {
            builder.set("WINEDEBUG", preset.winedebugValue, layer: .featureRuntime)
        }

        // Layer 8: callsiteOverride is left empty (populated by direct callers)

        // Collect bottle custom DLL overrides for the resolver
        dllResolver.bottleCustom = bottle.settings.dllOverrides

        // Resolve the builder and capture provenance for launch logging
        let (resolved, provenance) = builder.resolve()
        var result = resolved

        // Compose WINEDLLOVERRIDES from DLLOverrideResolver (outside the builder)
        let (overrideString, _) = dllResolver.resolve()
        if !overrideString.isEmpty {
            result["WINEDLLOVERRIDES"] = overrideString
        }

        // Launch logging: safe summary of bottle, active layers, and whitelisted keys
        logLaunchSummary(bottleName: bottle.settings.name, provenance: provenance, environment: result)

        return result
    }

    /// Applies per-program overrides to the programUser layer of the builder.
    ///
    /// Each non-nil field in the overrides sets the corresponding environment variable(s)
    /// in the ``EnvironmentLayer/programUser`` layer, which has higher priority than
    /// bottleManaged and launcherManaged layers.
    private static func applyProgramOverrides(
        _ overrides: ProgramOverrides,
        builder: inout EnvironmentBuilder,
        dllResolver: inout DLLOverrideResolver
    ) {
        // Graphics backend override: replaces bottle-level backend entirely
        if let backend = overrides.graphicsBackend {
            let resolved = if backend == .recommended {
                GraphicsBackendResolver.resolve()
            } else {
                backend
            }
            switch resolved {
            case .d3dMetal, .recommended:
                // Undo any bottle-level DXVK by overriding DLLs to builtin
                for entry in DLLOverrideResolver.dxvkPreset {
                    dllResolver.programCustom.append(
                        DLLOverrideEntry(dllName: entry.dllName, mode: .builtin)
                    )
                }
                // Remove DXVK and wined3d env vars at program layer
                builder.remove("DXVK_HUD", layer: .programUser)
                builder.remove("DXVK_ASYNC", layer: .programUser)
                builder.remove("WINED3DMETAL", layer: .programUser)

            case .dxvk:
                // Enable DXVK DLLs at program level
                dllResolver.programCustom.append(contentsOf: DLLOverrideResolver.dxvkPreset)
                builder.remove("WINED3DMETAL", layer: .programUser)

            case .wined3d:
                // Force wined3d: disable D3DMetal + undo DXVK DLLs
                builder.set("WINED3DMETAL", "0", layer: .programUser)
                for entry in DLLOverrideResolver.dxvkPreset {
                    dllResolver.programCustom.append(
                        DLLOverrideEntry(dllName: entry.dllName, mode: .builtin)
                    )
                }
            }
        }

        // DXVK override: affects DLL composition via resolver
        if let dxvk = overrides.dxvk {
            if dxvk {
                // Program forces DXVK on -- add DXVK preset to program custom DLLs
                dllResolver.programCustom.append(contentsOf: DLLOverrideResolver.dxvkPreset)
            } else {
                // Program forces DXVK off -- override each DXVK DLL to builtin
                for entry in DLLOverrideResolver.dxvkPreset {
                    dllResolver.programCustom.append(
                        DLLOverrideEntry(dllName: entry.dllName, mode: .builtin)
                    )
                }
            }
        }

        // DXVK HUD override
        if let dxvkHud = overrides.dxvkHud {
            switch dxvkHud {
            case .full:
                builder.set("DXVK_HUD", "full", layer: .programUser)
            case .partial:
                builder.set("DXVK_HUD", "devinfo,fps,frametimes", layer: .programUser)
            case .fps:
                builder.set("DXVK_HUD", "fps", layer: .programUser)
            case .off:
                builder.remove("DXVK_HUD", layer: .programUser)
            }
        }

        // DXVK async override
        if let dxvkAsync = overrides.dxvkAsync {
            builder.set("DXVK_ASYNC", dxvkAsync ? "1" : "0", layer: .programUser)
        }

        // Enhanced sync override
        if let enhancedSync = overrides.enhancedSync {
            switch enhancedSync {
            case .none:
                if MacOSVersion.current < .sequoia15_4 {
                    builder.remove("WINEESYNC", layer: .programUser)
                    builder.remove("WINEMSYNC", layer: .programUser)
                } else {
                    // On 15.4+ ESYNC is required for stability
                    builder.set("WINEESYNC", "1", layer: .programUser)
                    builder.remove("WINEMSYNC", layer: .programUser)
                }
            case .esync:
                builder.set("WINEESYNC", "1", layer: .programUser)
                builder.remove("WINEMSYNC", layer: .programUser)
            case .msync:
                builder.set("WINEMSYNC", "1", layer: .programUser)
                builder.set("WINEESYNC", "1", layer: .programUser)
            }
        }

        // Force D3D11 override
        if let forceD3D11 = overrides.forceD3D11 {
            if forceD3D11 {
                builder.set("D3DM_FORCE_D3D11", "1", layer: .programUser)
                builder.set("D3DM_FEATURE_LEVEL_12_0", "0", layer: .programUser)
            } else {
                builder.remove("D3DM_FORCE_D3D11", layer: .programUser)
                builder.remove("D3DM_FEATURE_LEVEL_12_0", layer: .programUser)
            }
        }

        // Shader cache override
        if let shaderCache = overrides.shaderCacheEnabled {
            if !shaderCache {
                builder.set("DXVK_SHADER_COMPILE_THREADS", "1", layer: .programUser)
                builder.set("__GL_SHADER_DISK_CACHE", "0", layer: .programUser)
            } else {
                builder.remove("DXVK_SHADER_COMPILE_THREADS", layer: .programUser)
                builder.remove("__GL_SHADER_DISK_CACHE", layer: .programUser)
            }
        }

        // Program-specific DLL overrides (structured entries)
        if let dllOverrides = overrides.dllOverrides {
            dllResolver.programCustom.append(contentsOf: dllOverrides)
        }
    }

    /// Logs a safe launch summary at info level.
    ///
    /// Only logs the bottle name, active layers, and whitelisted non-sensitive keys.
    /// Does NOT log full environment dict, WINEPREFIX paths, or user-set custom env vars.
    private static func logLaunchSummary(
        bottleName: String,
        provenance: EnvironmentProvenance,
        environment: [String: String]
    ) {
        let layerNames = provenance.activeLayers.sorted().map { layer -> String in
            switch layer {
            case .base: "base"
            case .platform: "platform"
            case .bottleManaged: "bottleManaged"
            case .launcherManaged: "launcherManaged"
            case .bottleUser: "bottleUser"
            case .programUser: "programUser"
            case .featureRuntime: "featureRuntime"
            case .callsiteOverride: "callsiteOverride"
            }
        }

        // Non-sensitive keys allowed in the launch summary
        let allowedKeys = [
            "DXVK_ASYNC", "DXVK_HUD", "WINEESYNC", "WINEMSYNC",
            "D3DM_FORCE_D3D11", "MTL_HUD_ENABLED", "WINED3DMETAL"
        ]
        let safeEntries = allowedKeys.compactMap { key -> String? in
            guard let value = environment[key] else { return nil }
            return "\(key)=\(value)"
        }

        let safeValues = safeEntries.isEmpty ? "defaults" : safeEntries.joined(separator: ", ")
        envLogger.info(
            "Launch: bottle=\(bottleName), layers=[\(layerNames.joined(separator: ","))], \(safeValues)"
        )
    }
}

// swiftlint:enable cyclomatic_complexity
// swiftlint:enable function_body_length
