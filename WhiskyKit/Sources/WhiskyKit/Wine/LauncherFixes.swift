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
    /// **Steam and the bottle's backend:** a bottle left on Recommended over
    /// D3DMetal keeps that backend. Steam's own processes get DXVK per
    /// executable instead: the resolver steers the client to DXVK and the launch
    /// writes it into their `AppDefaults` entries, so the games Steam starts stay
    /// on D3DMetal. Switching the whole bottle to DXVK turned `d3d12` off for
    /// every one of them, and a DirectX 12 game with no D3D11 path never started
    /// (#276). A forced apply (Apply Launcher Fixes in troubleshooting) does the
    /// same, or it would undo the fix it is meant to apply. Anywhere else the
    /// bottle still goes to DXVK as before: an explicit backend is never
    /// steered, and without the payload the bottle's games resolve to DXMT,
    /// whose files share the prefix's `d3d11.dll` with DXVK's. A switch from
    /// Recommended is recorded as the profile's, so the bottle goes back to
    /// Recommended once the payload is installed (``LauncherBackendMigration``).
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
    ///   - recommendedBackend: What `.recommended` resolves to for the bottle's
    ///     games. Defaults to the resolver's answer for the installed runtime.
    @MainActor
    // swiftlint:disable:next cyclomatic_complexity
    public static func apply(
        to bottle: Bottle, launcher: LauncherType, force: Bool = false,
        recommendedBackend: GraphicsBackend = GraphicsBackendResolver.resolve()
    ) {
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

            applySteamBackend(to: bottle, force: force, recommendedBackend: recommendedBackend)

            // GPU spoofing helps with game compatibility checks
            bottle.settings.gpuSpoofing = true

            // Longer network timeout for downloads
            bottle.settings.networkTimeout = 90_000 // 90 seconds

        case .rockstar:
            // Rockstar REQUIRES DXVK to display logo and UI. Still bottle-wide
            // (the launcher layer adds the preset too): only Launcher.exe and
            // SocialClubHelper.exe get entries of their own, and the rest of the
            // standalone launcher's processes have not been mapped.
            if bottle.settings.autoEnableDXVK {
                bottle.settings.dxvk = true
            }

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

        case .ubisoft:
            // Enable DXVK async for Anno 1800 and other games. Still bottle-wide:
            // Ubisoft Connect's Chromium helper has no AppDefaults entry yet
            // (see `helperExecutables`), so scoping would leave it on D3DMetal.
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

            // DXVK recommended. Still bottle-wide: Battle.net Launcher.exe starts
            // Battle.net.exe, which no launch writes an AppDefaults entry for.
            if force || !bottle.settings.dxvk {
                bottle.settings.dxvk = true
            }

        case .paradox:
            // Paradox's fix is environment-only (see LauncherPresets)
            break
        }

        // Save settings synchronously to disk
        // This ensures persistence before Wine.runProgram() reads settings
        bottle.saveBottleSettings()

        Logger.wineKit.info("""
        Applied launcher fixes for \(launcher.rawValue) to bottle '\(bottle.settings.name)'. \
        Settings persisted successfully.
        """)
    }

    /// The Steam profile's part in the bottle's backend.
    ///
    /// Over D3DMetal, a bottle on Recommended stays there, and one the profile
    /// switched to DXVK before goes back (with the same notice the migration
    /// shows), forced or not. Otherwise the bottle goes to DXVK, and a switch
    /// from Recommended is marked as the profile's. A DXVK the user picked is
    /// left alone either way.
    @MainActor
    private static func applySteamBackend(
        to bottle: Bottle, force: Bool, recommendedBackend: GraphicsBackend
    ) {
        if recommendedBackend == .d3dMetal {
            if bottle.settings.graphicsBackend == .recommended {
                return
            }
            if LauncherBackendMigration.isRestorable(bottle.settings) {
                LauncherBackendMigration.restore(&bottle.settings)
                return
            }
        }
        guard force || !bottle.settings.dxvk else { return }
        let fromRecommended = bottle.settings.graphicsBackend == .recommended
        bottle.settings.dxvk = true
        bottle.settings.dxvkAsync = true
        if fromRecommended {
            // After the switch: changing the backend clears the mark.
            bottle.settings.launcherSwitchedBackend = true
        }
    }
}
