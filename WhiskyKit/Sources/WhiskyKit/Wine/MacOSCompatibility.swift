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

// MARK: - macOS Compatibility Fix Registry

/// Structured metadata for a single macOS compatibility environment variable fix.
///
/// Each fix carries a human-readable reason and the minimum macOS version where it
/// activates, enabling the UI to display provenance like "Applied because macOS >= 15.4".
///
/// ## Example
///
/// ```swift
/// let active = MacOSCompatibilityFixes.activeFixes()
/// for fix in active {
///     print("\(fix.key)=\(fix.value) (from macOS \(fix.appliesFrom.description): \(fix.reason))")
/// }
/// ```
public struct MacOSFix: Sendable {
    /// The environment variable name.
    public let key: String
    /// The environment variable value.
    public let value: String
    /// Human-readable explanation of why this fix is applied.
    public let reason: String
    /// The minimum macOS version where this fix activates.
    public let appliesFrom: MacOSVersion
    /// The category of issue this fix addresses.
    public let category: FixCategory
}

/// Registry of macOS compatibility fixes for Wine.
///
/// This caseless enum provides the static fix registry and methods for querying
/// active fixes. The registry pattern replaces inline assignments, enabling
/// provenance display and structured metadata for each fix.
///
/// ## Security Note on CEF Sandbox
///
/// The CEF (Chromium Embedded Framework) sandbox must be disabled under Wine.
/// Wine doesn't support the kernel calls the sandbox requires, and without disabling
/// it, launchers crash or hang completely. This is a necessary trade-off: users
/// running Windows apps via Wine are already accepting compatibility layer security
/// implications.
public enum MacOSCompatibilityFixes {
    /// The minimum macOS version (effectively "all versions") for universal fixes.
    private static let allVersions = MacOSVersion(major: 0, minor: 0, patch: 0)

    /// All known macOS compatibility fixes for Wine.
    ///
    /// Fixes are ordered by the macOS version they apply from, with universal fixes first.
    /// Each fix carries a reason string and category for provenance display.
    public static let allFixes: [MacOSFix] = [
        // Universal fixes (all macOS versions)
        MacOSFix(
            key: "STEAM_DISABLE_CEF_SANDBOX", value: "1",
            reason: "CEF sandbox cannot function under Wine; required for launcher startup",
            appliesFrom: allVersions, category: .sandbox
        ),
        MacOSFix(
            key: "CEF_DISABLE_SANDBOX", value: "1",
            reason: "CEF sandbox cannot function under Wine; required for launcher startup",
            appliesFrom: allVersions, category: .sandbox
        ),

        // macOS 15.3+ fixes
        MacOSFix(
            key: "MTL_DEBUG_LAYER", value: "0",
            reason: "Disables Metal validation that causes rendering issues on macOS 15.3+",
            appliesFrom: .sequoia15_3, category: .graphics
        ),
        MacOSFix(
            key: "D3DM_VALIDATION", value: "0",
            reason: "Improves D3DMetal stability on macOS 15.3+",
            appliesFrom: .sequoia15_3, category: .graphics
        ),
        MacOSFix(
            key: "WINE_DISABLE_NTDLL_THREAD_REGS", value: "1",
            reason: "Fixes Wine preloader issues on Sequoia 15.3+",
            appliesFrom: .sequoia15_3, category: .threading
        ),

        // macOS 15.4+ fixes
        MacOSFix(
            key: "WINEFSYNC", value: "0",
            reason: "Disables fsync due to 15.4 security model changes",
            appliesFrom: .sequoia15_4, category: .threading
        ),
        MacOSFix(
            key: "WINE_ENABLE_PIPE_SYNC_FOR_APP", value: "0",
            reason: "Disables pipe sync that conflicts with 15.4 security changes",
            appliesFrom: .sequoia15_4, category: .threading
        ),
        MacOSFix(
            key: "STEAM_RUNTIME", value: "0",
            reason: "Disables Steam Runtime (incompatible with Wine on macOS 15.4+)",
            appliesFrom: .sequoia15_4, category: .compatibility
        ),
        MacOSFix(
            key: "WINE_CPU_TOPOLOGY", value: "8:8",
            reason: "Configures thread topology for M-series compatibility on macOS 15.4+",
            appliesFrom: .sequoia15_4, category: .threading
        ),
        MacOSFix(
            key: "WINE_THREAD_PRIORITY_PRESERVE", value: "1",
            reason: "Preserves thread priorities for wine-preloader stability",
            appliesFrom: .sequoia15_4, category: .threading
        ),
        MacOSFix(
            key: "WINE_ENABLE_POSIX_SIGNALS", value: "1",
            reason: "Improves signal handling on macOS 15.4+",
            appliesFrom: .sequoia15_4, category: .threading
        ),
        MacOSFix(
            key: "WINE_SIGPIPE_IGNORE", value: "1",
            reason: "Prevents SIGPIPE crashes on macOS 15.4+",
            appliesFrom: .sequoia15_4, category: .threading
        ),
        MacOSFix(
            key: "WINE_PRELOADER_DEBUG", value: "0",
            reason: "Disables preloader debug for process creation reliability on 15.4+",
            appliesFrom: .sequoia15_4, category: .compatibility
        ),
        MacOSFix(
            key: "WINE_DISABLE_FAST_PATH", value: "1",
            reason: "Disables fast path for process creation reliability on macOS 15.4+",
            appliesFrom: .sequoia15_4, category: .compatibility
        ),

        // macOS 15.4.1+ fixes
        MacOSFix(
            key: "WINE_MACH_PORT_TIMEOUT", value: "30000",
            reason: "Compensates for changed mach port handling in macOS 15.4.1",
            appliesFrom: .sequoia15_4_1, category: .threading
        ),
        MacOSFix(
            key: "WINE_MACH_PORT_RETRY_COUNT", value: "5",
            reason: "Adds mach port retry resilience for macOS 15.4.1 regression",
            appliesFrom: .sequoia15_4_1, category: .threading
        )
    ]

    /// Returns only fixes applicable to the current macOS version.
    ///
    /// Use this for UI display of active platform-level fixes with their reasons.
    ///
    /// - Returns: Array of ``MacOSFix`` entries that apply to the running macOS version.
    public static func activeFixes() -> [MacOSFix] {
        let currentVersion = MacOSVersion.current
        return allFixes.filter { currentVersion >= $0.appliesFrom }
    }

    /// Returns fixes applicable to a specific macOS version.
    ///
    /// - Parameter version: The macOS version to filter against.
    /// - Returns: Array of ``MacOSFix`` entries that apply to the given version.
    public static func activeFixes(for version: MacOSVersion) -> [MacOSFix] {
        allFixes.filter { version >= $0.appliesFrom }
    }
}

extension Wine {
    // MARK: - macOS Compatibility

    /// Apply environment variable fixes for macOS 15.x (Sequoia) compatibility.
    ///
    /// These fixes address upstream issues whisky-app/whisky#1372, #1310, #1307
    /// and frankea/Whisky#41 (launcher compatibility tracking issue).
    ///
    /// This method iterates the ``MacOSCompatibilityFixes/allFixes`` registry, filtering
    /// by the current macOS version. The WINEESYNC conditional logic is preserved as a
    /// special case since it depends on existing environment state.
    static func applyMacOSCompatibilityFixes(to environment: inout [String: String]) {
        let currentVersion = MacOSVersion.current

        // Log macOS version for debugging
        Logger.wineKit.info("Running on macOS \(currentVersion.description)")

        // Apply all version-gated fixes from the registry
        for fix in MacOSCompatibilityFixes.allFixes where currentVersion >= fix.appliesFrom {
            environment[fix.key] = fix.value
        }

        // Special case: WINEESYNC is conditional on other sync settings not being set.
        // This cannot be expressed as a simple registry entry because it depends on state.
        if currentVersion >= .sequoia15_4 {
            if environment["WINEMSYNC"] == nil, environment["WINEESYNC"] == nil {
                environment["WINEESYNC"] = "1"
            }
        }

        Logger.wineKit.debug("""
        CEF sandbox disabled for Wine compatibility. \
        This is required for Steam, Epic, EA App, and Rockstar launchers to function. \
        Security: Embedded browser content runs with process privileges.
        """)
    }
}
