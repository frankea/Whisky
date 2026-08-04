//
//  LauncherDetection.swift
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
import WhiskyKit

/// Launcher configuration diagnostics for the UI and support snapshots.
///
/// ## Overview
///
/// Detection lives in `LauncherType.detect(from:)` and fix application in
/// `LauncherFixes` (both WhiskyKit); this type only inspects a bottle's
/// settings against a launcher's expectations to surface warnings and
/// human-readable summaries.
enum LauncherDetection {
    /// Validates bottle configuration for a specific launcher.
    ///
    /// Returns a list of warnings about potential misconfigurations that could
    /// cause launcher failures. Useful for diagnostics and troubleshooting.
    ///
    /// - Parameters:
    ///   - bottle: The bottle to validate
    ///   - launcher: The launcher type to validate against
    /// - Returns: Array of warning messages (empty if configuration is optimal)
    @MainActor
    // swiftlint:disable:next cyclomatic_complexity
    static func validateBottleForLauncher(_ bottle: Bottle, launcher: LauncherType) -> [String] {
        var warnings: [String] = []

        switch launcher {
        case .steam:
            if !bottle.settings.dxvk {
                warnings.append("⚠️ DXVK should be enabled for best Steam performance")
            }
            if bottle.settings.launcherLocale != .english, bottle.settings.launcherLocale != .auto {
                warnings.append("⚠️ Steam may crash without en_US locale (steamwebhelper issue)")
            }
            if !bottle.settings.gpuSpoofing {
                warnings.append("⚠️ GPU spoofing helps with game compatibility checks")
            }

        case .rockstar:
            if !bottle.settings.dxvk {
                warnings.append("❌ DXVK REQUIRED for Rockstar Launcher (logo won't display without it)")
            }
            if !bottle.settings.forceD3D11 {
                warnings.append("⚠️ D3D11 mode recommended for Rockstar games (GTA V, RDR2)")
            }

        case .eaApp:
            if !bottle.settings.gpuSpoofing {
                warnings.append("❌ GPU spoofing REQUIRED for EA App (will show 'GPU not supported')")
            }
            if bottle.settings.launcherLocale != .english {
                warnings.append("⚠️ en_US locale recommended for EA App launcher UI")
            }

        case .epicGames:
            if bottle.settings.launcherLocale != .english {
                warnings.append("⚠️ en_US locale recommended for Epic Games launcher")
            }

        case .ubisoft:
            if !bottle.settings.forceD3D11 {
                warnings.append("⚠️ D3D11 mode required for Ubisoft Connect stability")
            }

        case .battleNet:
            if bottle.settings.launcherLocale != .english {
                warnings.append("⚠️ en_US locale recommended for Battle.net")
            }

        case .paradox:
            if !bottle.settings.forceD3D11 {
                warnings.append("⚠️ D3D11 mode recommended for Paradox Launcher")
            }
        }

        // General warnings
        if !bottle.settings.launcherCompatibilityMode {
            warnings.append("💡 Launcher Compatibility Mode is disabled. Enable it for automatic fixes.")
        }

        return warnings
    }

    /// Generates a user-friendly configuration summary for a launcher.
    ///
    /// - Parameters:
    ///   - bottle: The bottle to summarize
    ///   - launcher: The launcher type
    /// - Returns: Multi-line string describing the current configuration
    @MainActor
    static func generateConfigSummary(for bottle: Bottle, launcher: LauncherType) -> String {
        var summary = "Configuration for \(launcher.rawValue):\n\n"

        summary += "Compatibility Mode: \(bottle.settings.launcherCompatibilityMode ? "✅ Enabled" : "❌ Disabled")\n"
        summary += "Locale: \(bottle.settings.launcherLocale.pretty())\n"
        summary += "DXVK: \(bottle.settings.dxvk ? "✅ Enabled" : "❌ Disabled")\n"
        let gpuStatus = bottle.settings.gpuSpoofing
            ? "✅ Enabled (\(bottle.settings.gpuVendor.rawValue))"
            : "❌ Disabled"
        summary += "GPU Spoofing: \(gpuStatus)\n"
        summary += "D3D11 Mode: \(bottle.settings.forceD3D11 ? "✅ Enabled" : "❌ Disabled")\n"
        summary += "Network Timeout: \(bottle.settings.networkTimeout)ms\n\n"

        summary += "Fixes Applied:\n\(launcher.fixesDescription)\n\n"

        let warnings = validateBottleForLauncher(bottle, launcher: launcher)
        if !warnings.isEmpty {
            summary += "⚠️ Warnings:\n"
            for warning in warnings {
                summary += "  \(warning)\n"
            }
        } else {
            summary += "✅ Configuration is optimal for this launcher\n"
        }

        return summary
    }
}
