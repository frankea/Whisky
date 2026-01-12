//
//  MacOSCompatibility.swift
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

// MARK: - macOS Version Detection

/// Represents macOS version for compatibility checks
public struct MacOSVersion: Comparable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public static let current: MacOSVersion = {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return MacOSVersion(major: version.majorVersion, minor: version.minorVersion, patch: version.patchVersion)
    }()

    // swiftlint:disable identifier_name
    /// macOS 15.3 (Sequoia)
    public static let sequoia15_3 = MacOSVersion(major: 15, minor: 3, patch: 0)
    /// macOS 15.4 (Sequoia)
    public static let sequoia15_4 = MacOSVersion(major: 15, minor: 4, patch: 0)
    /// macOS 15.4.1 (Sequoia)
    public static let sequoia15_4_1 = MacOSVersion(major: 15, minor: 4, patch: 1)
    // swiftlint:enable identifier_name

    public static func < (lhs: MacOSVersion, rhs: MacOSVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }

    public var description: String {
        "\(major).\(minor).\(patch)"
    }
}

extension Wine {
    // MARK: - macOS Compatibility

    /// Apply environment variable fixes for macOS 15.x (Sequoia) compatibility
    /// These fixes address upstream issues whisky-app/whisky#1372, #1310, #1307
    /// and frankea/Whisky#41 (launcher compatibility tracking issue)
    static func applyMacOSCompatibilityFixes(to environment: inout [String: String]) {
        let currentVersion = MacOSVersion.current

        // Log macOS version for debugging
        Logger.wineKit.info("Running on macOS \(currentVersion.description)")

        // CEF (Chromium Embedded Framework) sandbox must be disabled under Wine
        // Applies to Steam, Epic Games, EA App, Rockstar Launcher (frankea/Whisky#41)
        //
        // SECURITY NOTE: This disables CEF's security sandbox, which normally isolates
        // embedded web content from the host process. However, the CEF sandbox fundamentally
        // cannot function under Wine because:
        // 1. Wine doesn't support all Linux/Windows kernel calls the sandbox requires
        // 2. The sandbox expects native OS security features that Wine cannot translate
        // 3. Without disabling it, launchers crash or hang completely (steamwebhelper, etc.)
        //
        // Security Implications:
        // - Embedded browser content runs with full process privileges
        // - A browser exploit could compromise the Wine process
        // - Users should only use trusted launchers (Steam, Epic, EA are reputable)
        //
        // Alternative Considered:
        // Making this opt-in would require users to enable "unsafe mode" for launchers to work,
        // which defeats the purpose of frankea/Whisky#41. The CEF sandbox provides minimal
        // protection under Wine anyway since Wine itself bypasses many OS security features.
        //
        // This is a necessary trade-off for Wine compatibility. Users running Windows apps
        // via Wine are already accepting compatibility layer security implications.
        environment["STEAM_DISABLE_CEF_SANDBOX"] = "1"
        environment["CEF_DISABLE_SANDBOX"] = "1"

        Logger.wineKit.debug("""
        CEF sandbox disabled for Wine compatibility. \
        This is required for Steam, Epic, EA App, and Rockstar launchers to function. \
        Security: Embedded browser content runs with process privileges.
        """)

        // macOS 15.3+ compatibility fixes
        if currentVersion >= .sequoia15_3 {
            // Fix for graphics issues on macOS 15.3 (whisky-app/whisky#1310)
            // Disable certain Metal validation that can cause rendering issues
            environment["MTL_DEBUG_LAYER"] = "0"

            // Improve D3DMetal stability on newer macOS
            environment["D3DM_VALIDATION"] = "0"

            // Workaround for Wine preloader issues on Sequoia
            // This helps with Steam and other launcher initialization
            environment["WINE_DISABLE_NTDLL_THREAD_REGS"] = "1"
        }

        // macOS 15.4+ specific fixes
        if currentVersion >= .sequoia15_4 {
            // Fix for Steam crashes on macOS 15.4.1 (whisky-app/whisky#1372)
            // The new security model in 15.4 changes how Wine handles certain syscalls
            environment["WINEFSYNC"] = "0"

            // Disable problematic features that conflict with 15.4 security changes
            environment["WINE_ENABLE_PIPE_SYNC_FOR_APP"] = "0"

            // Force synchronization mode that works better with macOS 15.4
            if environment["WINEMSYNC"] == nil, environment["WINEESYNC"] == nil {
                environment["WINEESYNC"] = "1"
            }

            // Additional fix for Steam web helper issues
            environment["STEAM_RUNTIME"] = "0"

            // Enhanced thread management for wine-preloader issues (whisky-app/whisky#1372)
            environment["WINE_CPU_TOPOLOGY"] = "8:8" // Match typical M-series config
            environment["WINE_THREAD_PRIORITY_PRESERVE"] = "1"

            // Signal handling improvements
            environment["WINE_ENABLE_POSIX_SIGNALS"] = "1"
            environment["WINE_SIGPIPE_IGNORE"] = "1"

            // Process creation reliability
            environment["WINE_PRELOADER_DEBUG"] = "0"
            environment["WINE_DISABLE_FAST_PATH"] = "1"
        }

        // macOS 15.4.1 specific fixes
        if currentVersion >= .sequoia15_4_1 {
            // Specific workaround for 15.4.1 regression (whisky-app/whisky#1372)
            // Apple changed mach port handling which affects Wine
            environment["WINE_MACH_PORT_TIMEOUT"] = "30000"

            // Additional thread affinity and mach port fixes
            environment["WINE_MACH_PORT_RETRY_COUNT"] = "5"
        }
    }
}
