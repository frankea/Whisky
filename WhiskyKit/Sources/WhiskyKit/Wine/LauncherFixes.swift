//
//  LauncherFixes.swift
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

/// Applies launcher-specific bottle configuration when a known launcher runs.
///
/// ## Overview
///
/// Detection itself lives in ``LauncherType/detect(from:)``; this type owns the
/// per-launcher settings profile and the rules for when it may be applied
/// automatically, addressing compatibility issues documented in
/// frankea/Whisky#41.
///
/// There are two entry points with deliberately different gating:
///
/// - ``detectAndApply(from:for:)`` is the detection-driven path used when a
///   program is launched. It only *refines* a bottle whose compatibility mode
///   is already enabled, never touches manual mode, and short-circuits when the
///   detected launcher is already configured.
/// - ``apply(to:launcher:force:)`` applies a launcher's profile directly,
///   enabling compatibility mode if it is off. Callers own any mode gating
///   (the Steam orchestrator, for example, only calls it in auto mode).
///
/// ## Example
///
/// ```swift
/// let url = URL(fileURLWithPath: "C:/Program Files/Steam/steam.exe")
/// LauncherFixes.detectAndApply(from: url, for: bottle)
/// ```
public enum LauncherFixes {
    /// Detects and applies launcher fixes if compatibility mode is enabled.
    ///
    /// This is the primary entry point for launcher detection and configuration.
    /// It handles both auto-detection and manual modes, applying appropriate
    /// settings and ensuring they're persisted before program execution.
    ///
    /// **Thread Safety:** This method must be called on the MainActor since it
    /// accesses and modifies bottle settings.
    ///
    /// - Parameters:
    ///   - url: The URL to the Windows executable file
    ///   - bottle: The bottle context for launcher configuration
    /// - Returns: `true` if launcher was detected and fixes applied, `false` otherwise
    @MainActor
    @discardableResult
    public static func detectAndApply(from url: URL, for bottle: Bottle) -> Bool {
        // Check if launcher compatibility mode is enabled
        guard bottle.settings.launcherCompatibilityMode,
              bottle.settings.launcherMode == .auto
        else {
            return false
        }

        // Attempt to detect launcher type
        guard let detectedLauncher = LauncherType.detect(from: url) else {
            return false
        }

        // Only apply if not already detected or different launcher
        guard bottle.settings.detectedLauncher != detectedLauncher else {
            Logger.wineKit.debug("Launcher \(detectedLauncher.rawValue) already configured for bottle")
            return false
        }

        // Apply launcher-specific fixes and save synchronously
        apply(to: bottle, launcher: detectedLauncher)

        return true
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
    /// **Important:** This method saves settings synchronously to disk via
    /// `bottle.saveBottleSettings()`, blocking until the write completes.
    /// This ensures settings are persisted before Wine reads them for
    /// environment variable configuration.
    ///
    /// - Parameters:
    ///   - bottle: The bottle to configure
    ///   - launcher: The detected or manually selected launcher type
    ///   - force: If `true`, overrides existing settings; if `false`, only applies if not already configured
    @MainActor
    // swiftlint:disable:next cyclomatic_complexity
    public static func apply(to bottle: Bottle, launcher: LauncherType, force: Bool = false) {
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
            bottle.settings.networkTimeout = 90_000 // 90 seconds

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
            bottle.settings.networkTimeout = 90_000

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

        // Save settings synchronously to disk
        // This ensures persistence before Wine.runProgram() reads settings
        bottle.saveBottleSettings()

        Logger.wineKit.info("""
        Applied launcher fixes for \(launcher.rawValue) to bottle '\(bottle.settings.name)'. \
        Settings persisted successfully.
        """)
    }
}
