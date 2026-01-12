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

/// Utilities for detecting game launcher types and applying optimized configurations.
///
/// ## Overview
///
/// This system implements heuristic-based auto-detection of game launchers from
/// executable paths and names. When a launcher is detected, it can automatically
/// apply optimized settings to fix compatibility issues documented in Issue #41.
///
/// ## Detection Strategy
///
/// Detection uses multiple signals:
/// 1. Executable filename (e.g., "steam.exe", "Launcher.exe")
/// 2. Path components (e.g., "/Steam/", "/Rockstar Games/")
/// 3. Parent directory names
/// 4. Known installation patterns
///
/// ## Example
///
/// ```swift
/// let url = URL(fileURLWithPath: "C:/Program Files/Steam/steam.exe")
/// if let launcher = LauncherDetection.detectLauncher(from: url) {
///     print("Detected: \(launcher.rawValue)")
///     // Apply optimized settings
///     LauncherDetection.applyLauncherFixes(for: bottle, launcher: launcher)
/// }
/// ```
struct LauncherDetection {
    /// Detects launcher type from executable URL using heuristic analysis.
    ///
    /// This method examines both the executable filename and full path to identify
    /// known launcher patterns. Detection is case-insensitive for compatibility.
    ///
    /// - Parameter url: The URL to the Windows executable file
    /// - Returns: The detected launcher type, or `nil` if no launcher detected
    static func detectLauncher(from url: URL) -> LauncherType? {
        let filename = url.lastPathComponent.lowercased()
        let path = url.path.lowercased()

        // Steam detection
        // Common paths: steam.exe, steamservice.exe, steamwebhelper.exe
        if filename.contains("steam") || path.contains("/steam/") || path.contains("\\steam\\") {
            return .steam
        }

        // Rockstar Games Launcher detection
        // Common paths: Launcher.exe in Rockstar Games directory
        // LauncherPatcher.exe (workaround for #835)
        if filename.contains("rockstar") ||
            path.contains("/rockstar") ||
            path.contains("\\rockstar") ||
            (filename == "launcher.exe" && (path.contains("rockstar") || path.contains("social club"))) ||
            filename.contains("launcherpatcher") {
            return .rockstar
        }

        // EA App / Origin detection
        // EADesktop.exe (new EA App), Origin.exe (legacy)
        if filename.contains("eadesktop") ||
            filename.contains("eaapp") ||
            filename.contains("origin.exe") ||
            path.contains("/ea app/") ||
            path.contains("\\ea app\\") ||
            path.contains("/origin/") {
            return .eaApp
        }

        // Epic Games Store detection
        // EpicGamesLauncher.exe, EpicWebHelper.exe
        if filename.contains("epicgames") ||
            filename.contains("epiclauncher") ||
            filename.contains("epicwebhelper") ||
            path.contains("/epic games/") ||
            path.contains("\\epic games\\") {
            return .epicGames
        }

        // Ubisoft Connect detection
        // UbisoftConnect.exe, upc.exe (legacy Uplay)
        if filename.contains("ubisoft") ||
            filename.contains("uplay") ||
            filename.contains("upc.exe") ||
            path.contains("/ubisoft") {
            return .ubisoft
        }

        // Battle.net detection
        // Battle.net.exe, Battle.net Launcher.exe
        if filename.contains("battle.net") ||
            filename.contains("battlenet") ||
            path.contains("/battle.net/") ||
            path.contains("\\battle.net\\") {
            return .battleNet
        }

        // Paradox Launcher detection
        // Paradox Launcher.exe
        if filename.contains("paradox") ||
            path.contains("/paradox") ||
            (filename.contains("launcher") && path.contains("paradox")) {
            return .paradox
        }

        return nil
    }

    /// Applies launcher-specific fixes when running a program.
    ///
    /// This method configures bottle settings based on detected launcher type.
    /// Settings are applied automatically in auto-detection mode, or can be
    /// called explicitly after manual launcher selection.
    ///
    /// **Changes Applied:**
    /// - Enables launcher compatibility mode
    /// - Sets launcher-specific locale
    /// - Configures DXVK if required
    /// - Enables GPU spoofing for compatibility checks
    ///
    /// - Parameters:
    ///   - bottle: The bottle to configure
    ///   - launcher: The detected or manually selected launcher type
    ///   - force: If `true`, overrides existing settings; if `false`, only applies if not already configured
    @MainActor
    // swiftlint:disable:next cyclomatic_complexity
    static func applyLauncherFixes(for bottle: Bottle, launcher: LauncherType, force: Bool = false) {
        // Enable launcher compatibility mode
        if !bottle.settings.launcherCompatibilityMode || force {
            bottle.settings.launcherCompatibilityMode = true
        }

        // Set detected launcher
        bottle.settings.detectedLauncher = launcher

        // Apply launcher-specific configurations
        switch launcher {
        case .steam:
            // Steam requires en_US locale to avoid steamwebhelper crashes
            bottle.settings.launcherLocale = launcher.recommendedLocale

            // DXVK improves Steam UI performance
            if force || !bottle.settings.dxvk {
                bottle.settings.dxvk = true
                bottle.settings.dxvkAsync = true
            }

            // GPU spoofing helps with game compatibility checks
            bottle.settings.gpuSpoofing = true

            // Longer network timeout for downloads
            bottle.settings.networkTimeout = 90000  // 90 seconds

        case .rockstar:
            // Rockstar REQUIRES DXVK to display logo and UI
            if bottle.settings.autoEnableDXVK {
                bottle.settings.dxvk = true
            }

            // Force D3D11 mode for better compatibility
            bottle.settings.forceD3D11 = true

            // English locale recommended
            bottle.settings.launcherLocale = .english

        case .eaApp:
            // EA App needs GPU spoofing to pass checks
            bottle.settings.gpuSpoofing = true
            bottle.settings.gpuVendor = .nvidia

            // Locale fix for Chromium-based UI
            bottle.settings.launcherLocale = .english

        case .epicGames:
            // Epic Games launcher improvements
            bottle.settings.launcherLocale = .english
            bottle.settings.gpuSpoofing = true

            // D3D11 mode for stability
            if force {
                bottle.settings.forceD3D11 = true
            }

        case .ubisoft:
            // Ubisoft Connect requires D3D11
            bottle.settings.forceD3D11 = true

            // Enable DXVK async for Anno 1800 and other games
            if force || !bottle.settings.dxvk {
                bottle.settings.dxvk = true
                bottle.settings.dxvkAsync = true
            }

            // Longer timeout for Ubisoft's servers
            bottle.settings.networkTimeout = 90000

        case .battleNet:
            // Battle.net Chromium-based launcher
            bottle.settings.launcherLocale = .english
            bottle.settings.gpuSpoofing = true

            // DXVK recommended
            if force || !bottle.settings.dxvk {
                bottle.settings.dxvk = true
            }

        case .paradox:
            // Paradox Launcher requires D3D11 mode
            bottle.settings.forceD3D11 = true
        }

        // Save settings
        bottle.saveBottleSettings()
    }

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
            if bottle.settings.launcherLocale != .english && bottle.settings.launcherLocale != .auto {
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
