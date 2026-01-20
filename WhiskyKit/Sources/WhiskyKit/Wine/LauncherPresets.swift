//
//  LauncherPresets.swift
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

/// Represents different game launcher platforms with optimized configurations.
///
/// This enum provides launcher-specific environment variable presets to address
/// compatibility issues documented in frankea/Whisky#41 and ~100 related upstream issues.
///
/// ## Overview
///
/// Game launchers (Steam, Rockstar, EA App, etc.) often have specific requirements
/// for locale settings, sandbox configuration, and graphics drivers. This system
/// applies optimized settings automatically based on launcher type.
///
/// ## Example
///
/// ```swift
/// let launcher = LauncherType.steam
/// let environment = launcher.environmentOverrides()
/// // Returns Steam-specific fixes for steamwebhelper and CEF sandbox
/// ```
///
/// ## Topics
///
/// ### Launcher Types
/// - ``steam``
/// - ``rockstar``
/// - ``eaApp``
/// - ``epicGames``
/// - ``ubisoft``
/// - ``battleNet``
/// - ``paradox``
///
/// ### Configuration
/// - ``environmentOverrides()``
/// - ``requiresDXVK``
/// - ``recommendedLocale``
public enum LauncherType: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Valve Steam platform
    case steam = "Steam"
    /// Rockstar Games Launcher
    case rockstar = "Rockstar Games Launcher"
    /// Electronic Arts App (formerly Origin)
    case eaApp = "EA App"
    /// Epic Games Store launcher
    case epicGames = "Epic Games Store"
    /// Ubisoft Connect (formerly Uplay)
    case ubisoft = "Ubisoft Connect"
    /// Blizzard Battle.net launcher
    case battleNet = "Battle.net"
    /// Paradox Launcher
    case paradox = "Paradox Launcher"

    public var id: String { rawValue }

    /// Display name for the launcher.
    public var displayName: String {
        switch self {
        case .steam:
            "Steam"
        case .rockstar:
            "Rockstar Games Launcher"
        case .eaApp:
            "EA App"
        case .epicGames:
            "Epic Games Store"
        case .ubisoft:
            "Ubisoft Connect"
        case .battleNet:
            "Battle.net"
        case .paradox:
            "Paradox Launcher"
        }
    }

    /// Whether this launcher is known to use the clipboard for multiplayer features.
    public var usesClipboard: Bool {
        switch self {
        case .steam, .epicGames, .battleNet:
            true
        default:
            false
        }
    }

    /// Returns optimized environment variables for this launcher.
    ///
    /// These overrides address specific compatibility issues:
    /// - **Steam**: Fixes steamwebhelper crashes (whisky-app/whisky#946, #1224, #1241) via locale and CEF sandbox
    /// - **Rockstar**: Requires DXVK for logo rendering (whisky-app/whisky#1335, #835)
    /// - **EA App/Epic**: Chromium-based, need sandbox and locale fixes
    /// - **Ubisoft**: Requires D3D11 mode for stability (whisky-app/whisky#1004)
    ///
    /// - Returns: Dictionary of environment variable key-value pairs
    public func environmentOverrides() -> [String: String] {
        var env: [String: String] = [:]

        switch self {
        case .steam:
            // Steam-specific fixes for steamwebhelper crashes
            // (whisky-app/whisky#946, #1224, #1241)
            // The Chromium Embedded Framework in Steam requires specific locale
            env["LC_ALL"] = "en_US.UTF-8"
            env["LANG"] = "en_US.UTF-8"
            // Force C locale for numeric/time to avoid ICU parsing errors
            env["LC_TIME"] = "C"
            env["LC_NUMERIC"] = "C"

            // Note: CEF_DISABLE_SANDBOX is set globally in MacOSCompatibility.swift
            // for all launchers. We only set Steam-specific variant here.
            env["STEAM_DISABLE_CEF_SANDBOX"] = "1"

            // Steam Runtime causes issues under Wine
            env["STEAM_RUNTIME"] = "0"

            // Reduce UI stuttering in Steam client
            env["DXVK_ASYNC"] = "1"

            // Note: Network timeouts for Steam are configured via bottle.settings.networkTimeout
            // which is set to 90000ms by LauncherDetection.applyLauncherFixes()
            // This allows users to customize timeouts via the UI slider

        case .rockstar:
            // Rockstar Launcher fixes (whisky-app/whisky#1335, #835, #1120)
            // DXVK is REQUIRED for logo screen to render
            env["DXVK_REQUIRED"] = "1"

            // Note: CEF_DISABLE_SANDBOX is set globally in MacOSCompatibility.swift

            // Force D3D11 mode for better compatibility
            env["D3DM_FORCE_D3D11"] = "1"

            // Launcher initialization improvements
            env["WINE_LARGE_ADDRESS_AWARE"] = "1"

            // Locale for launcher UI
            env["LC_ALL"] = "en_US.UTF-8"

        case .eaApp:
            // EA App (formerly Origin) fixes (whisky-app/whisky#1195, #1322)
            // Note: CEF_DISABLE_SANDBOX is set globally in MacOSCompatibility.swift
            env["LC_ALL"] = "en_US.UTF-8"
            env["LANG"] = "en_US.UTF-8"

            // GPU detection fixes for "GPU not supported" errors
            env["D3DM_FEATURE_LEVEL_12_1"] = "1"

            // Note: Network timeouts configured via bottle.settings.networkTimeout (default 60s)

        case .epicGames:
            // Epic Games Store launcher fixes
            // Note: CEF_DISABLE_SANDBOX is set globally in MacOSCompatibility.swift
            env["LC_ALL"] = "en_US.UTF-8"

            // Epic launcher stability improvements
            env["D3DM_FORCE_D3D11"] = "1"

            // Thread safety for Epic's web views
            env["WINE_DISABLE_NTDLL_THREAD_REGS"] = "1"

        case .ubisoft:
            // Ubisoft Connect fixes (whisky-app/whisky#1004)
            // Requires D3D11 mode
            env["D3DM_FORCE_D3D11"] = "1"

            // Anno 1800 and other Ubisoft games compatibility
            env["DXVK_ASYNC"] = "1"

            // Note: Network timeouts for Ubisoft are configured via bottle.settings.networkTimeout
            // which is set to 90000ms by LauncherDetection.applyLauncherFixes()

        case .battleNet:
            // Blizzard Battle.net launcher
            // Note: CEF_DISABLE_SANDBOX is set globally in MacOSCompatibility.swift
            env["LC_ALL"] = "en_US.UTF-8"

            // Battle.net requires specific threading
            env["WINE_CPU_TOPOLOGY"] = "8:8"

        case .paradox:
            // Paradox Launcher fixes (whisky-app/whisky#1091)
            // Resource lookup bug workaround
            env["WINE_DISABLE_FAST_PATH"] = "1"

            // Launcher initialization
            env["D3DM_FORCE_D3D11"] = "1"
        }

        return env
    }

    /// Indicates whether this launcher requires DXVK to function.
    ///
    /// Some launchers (notably Rockstar) will not render their UI without DXVK enabled.
    public var requiresDXVK: Bool {
        switch self {
        case .rockstar:
            true
        default:
            false
        }
    }

    /// The recommended locale for this launcher.
    ///
    /// Most launchers work best with US English locale to avoid
    /// date/time parsing issues in embedded web views.
    public var recommendedLocale: Locales {
        switch self {
        case .steam, .eaApp, .epicGames, .battleNet:
            .english
        default:
            .auto
        }
    }

    /// User-friendly description of common issues this preset fixes.
    public var fixesDescription: String {
        switch self {
        case .steam:
            "Fixes steamwebhelper crashes, download stalls, and connection issues"
        case .rockstar:
            "Fixes logo freeze and launcher initialization failures"
        case .eaApp:
            "Fixes black screen and GPU detection errors"
        case .epicGames:
            "Fixes launcher UI rendering and web view issues"
        case .ubisoft:
            "Improves launcher stability and game compatibility"
        case .battleNet:
            "Fixes authentication and launcher rendering issues"
        case .paradox:
            "Fixes recursive resource lookup bugs and initialization"
        }
    }
}
