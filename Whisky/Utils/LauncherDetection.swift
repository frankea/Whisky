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
/// A configuration problem the launcher section points out for a bottle.
///
/// The settings UI shows ``localizedMessage``; the diagnostics export keeps
/// ``diagnosticMessage``, in English, so reports read the same whatever the
/// reporter's language.
enum LauncherConfigWarning: Hashable {
    case steamLocale
    case steamGPUSpoofing
    case rockstarDXVK
    case eaGPUSpoofing
    case eaLocale
    case epicLocale
    case battleNetLocale
    case compatibilityModeOff

    /// The severity marker shown in front of the message.
    var symbol: String {
        switch self {
        case .rockstarDXVK, .eaGPUSpoofing: "❌"
        case .compatibilityModeOff: "💡"
        default: "⚠️"
        }
    }

    /// The warning for the settings UI, in the app's language.
    var localizedMessage: String {
        let message = switch self {
        case .steamLocale: String(localized: "launcher.warning.steamLocale")
        case .steamGPUSpoofing: String(localized: "launcher.warning.steamGPUSpoofing")
        case .rockstarDXVK: String(localized: "launcher.warning.rockstarDXVK")
        case .eaGPUSpoofing: String(localized: "launcher.warning.eaGPUSpoofing")
        case .eaLocale: String(localized: "launcher.warning.eaLocale")
        case .epicLocale: String(localized: "launcher.warning.epicLocale")
        case .battleNetLocale: String(localized: "launcher.warning.battleNetLocale")
        case .compatibilityModeOff: String(localized: "launcher.warning.compatibilityModeOff")
        }
        return "\(symbol) \(message)"
    }

    /// The warning for diagnostics exports, always in English.
    var diagnosticMessage: String {
        let message = switch self {
        case .steamLocale: "Steam may crash without en_US locale (steamwebhelper issue)"
        case .steamGPUSpoofing: "GPU spoofing helps with game compatibility checks"
        case .rockstarDXVK: "DXVK REQUIRED for Rockstar Launcher (logo won't display without it)"
        case .eaGPUSpoofing: "GPU spoofing REQUIRED for EA App (will show 'GPU not supported')"
        case .eaLocale: "en_US locale recommended for EA App launcher UI"
        case .epicLocale: "en_US locale recommended for Epic Games launcher"
        case .battleNetLocale: "en_US locale recommended for Battle.net"
        case .compatibilityModeOff: "Launcher Compatibility Mode is disabled. Enable it for automatic fixes."
        }
        return "\(symbol) \(message)"
    }
}

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
    /// - Returns: The warnings that apply (empty if configuration is optimal)
    @MainActor
    // swiftlint:disable:next cyclomatic_complexity
    static func validateBottleForLauncher(_ bottle: Bottle, launcher: LauncherType) -> [LauncherConfigWarning] {
        var warnings: [LauncherConfigWarning] = []
        let nonEnglishLocale = bottle.settings.launcherLocale != .english

        switch launcher {
        case .steam:
            // No DXVK check: Steam's own processes get DXVK through their own
            // overrides, so a bottle on D3DMetal is the intended setup (#276).
            if nonEnglishLocale, bottle.settings.launcherLocale != .auto {
                warnings.append(.steamLocale)
            }
            if !bottle.settings.gpuSpoofing {
                warnings.append(.steamGPUSpoofing)
            }

        case .rockstar:
            if !bottle.settings.dxvk {
                warnings.append(.rockstarDXVK)
            }

        case .eaApp:
            if !bottle.settings.gpuSpoofing {
                warnings.append(.eaGPUSpoofing)
            }
            if nonEnglishLocale {
                warnings.append(.eaLocale)
            }

        case .epicGames:
            if nonEnglishLocale {
                warnings.append(.epicLocale)
            }

        case .battleNet:
            if nonEnglishLocale {
                warnings.append(.battleNetLocale)
            }

        case .ubisoft, .paradox:
            break
        }

        // General warnings
        if !bottle.settings.launcherCompatibilityMode {
            warnings.append(.compatibilityModeOff)
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
        summary += "Network Timeout: \(bottle.settings.networkTimeout)ms\n\n"

        summary += "Fixes Applied:\n\(launcher.fixesDescription)\n\n"

        let warnings = validateBottleForLauncher(bottle, launcher: launcher)
        if !warnings.isEmpty {
            summary += "⚠️ Warnings:\n"
            for warning in warnings {
                summary += "  \(warning.diagnosticMessage)\n"
            }
        } else {
            summary += "✅ Configuration is optimal for this launcher\n"
        }

        return summary
    }
}
