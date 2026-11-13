//
//  LauncherFixDetails.swift
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

// MARK: - Structured Fix Details

extension LauncherType {
    // swiftlint:disable function_body_length

    /// Returns structured fix metadata for this launcher's environment overrides.
    ///
    /// Each entry wraps the same key-value pair as ``environmentOverrides()`` but adds
    /// a human-readable reason and ``FixCategory`` for provenance display in the UI.
    ///
    /// - Returns: Array of ``LauncherFixDetail`` entries describing each fix.
    public func fixDetails() -> [LauncherFixDetail] {
        switch self {
        case .steam:
            [
                LauncherFixDetail(
                    key: "STEAM_DISABLE_CEF_SANDBOX", value: "1",
                    reason: LauncherFixReason.steamCefSandbox,
                    category: .sandbox
                ),
                LauncherFixDetail(
                    key: "STEAM_RUNTIME", value: "0",
                    reason: LauncherFixReason.steamRuntime,
                    category: .compatibility
                ),
                LauncherFixDetail(
                    key: "DXVK_ASYNC", value: "1",
                    reason: LauncherFixReason.steamDxvkAsync,
                    category: .graphics
                )
            ]

        case .rockstar:
            [
                LauncherFixDetail(
                    key: "WINE_LARGE_ADDRESS_AWARE", value: "1",
                    reason: LauncherFixReason.largeAddressAware,
                    category: .compatibility
                ),
                LauncherFixDetail(
                    key: "LC_ALL", value: "en_US.UTF-8",
                    reason: LauncherFixReason.rockstarLocale,
                    category: .locale
                )
            ]

        case .eaApp:
            [
                LauncherFixDetail(
                    key: "LC_ALL", value: "en_US.UTF-8",
                    reason: LauncherFixReason.chromiumLocale,
                    category: .locale
                ),
                LauncherFixDetail(
                    key: "LANG", value: "en_US.UTF-8",
                    reason: LauncherFixReason.chromiumLocale,
                    category: .locale
                )
            ]

        case .epicGames:
            [
                LauncherFixDetail(
                    key: "LC_ALL", value: "en_US.UTF-8",
                    reason: LauncherFixReason.chromiumLocale,
                    category: .locale
                )
            ]

        case .ubisoft:
            [
                LauncherFixDetail(
                    key: "DXVK_ASYNC", value: "1",
                    reason: LauncherFixReason.ubisoftDxvkAsync,
                    category: .graphics
                )
            ]

        case .battleNet:
            [
                LauncherFixDetail(
                    key: "LC_ALL", value: "en_US.UTF-8",
                    reason: LauncherFixReason.chromiumLocale,
                    category: .locale
                )
            ]

        case .paradox:
            []
        }
    }

    // swiftlint:enable function_body_length
}

// MARK: - Localized Reasons

/// English fix reasons. ``LauncherFixDetail/reason`` keeps these as the
/// provenance recorded in the environment; ``LauncherFixDetail/localizedReason``
/// maps each one to its catalog entry for display.
private enum LauncherFixReason {
    static let steamCefSandbox = "Disables Steam-specific CEF sandbox (crashes under Wine)"
    static let steamRuntime = "Disables Steam Runtime (incompatible with Wine)"
    static let steamDxvkAsync = "Reduces UI stuttering in Steam client"
    static let largeAddressAware = "Improves launcher initialization memory handling"
    static let rockstarLocale = "Sets locale for launcher UI rendering"
    static let chromiumLocale = "Fixes Chromium-based launcher locale issues"
    static let ubisoftDxvkAsync = "Improves rendering for Anno 1800 and other Ubisoft games"
}

extension LauncherFixDetail {
    /// ``reason`` for display in the app, from the string catalog.
    ///
    /// ``reason`` stays English, because it is the provenance recorded in the
    /// environment and diagnostics. A fix with no catalog entry shows ``reason``.
    public var localizedReason: String {
        switch reason {
        case LauncherFixReason.steamCefSandbox:
            String(localized: "launcher.fix.reason.steamCefSandbox")
        case LauncherFixReason.steamRuntime:
            String(localized: "launcher.fix.reason.steamRuntime")
        case LauncherFixReason.steamDxvkAsync:
            String(localized: "launcher.fix.reason.steamDxvkAsync")
        case LauncherFixReason.largeAddressAware:
            String(localized: "launcher.fix.reason.largeAddressAware")
        case LauncherFixReason.rockstarLocale:
            String(localized: "launcher.fix.reason.rockstarLocale")
        case LauncherFixReason.chromiumLocale:
            String(localized: "launcher.fix.reason.chromiumLocale")
        case LauncherFixReason.ubisoftDxvkAsync:
            String(localized: "launcher.fix.reason.ubisoftDxvkAsync")
        default:
            reason
        }
    }
}
