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
                    key: "LC_ALL", value: "en_US.UTF-8",
                    reason: "Fixes steamwebhelper CEF locale crashes",
                    category: .locale
                ),
                LauncherFixDetail(
                    key: "LANG", value: "en_US.UTF-8",
                    reason: "Fixes steamwebhelper CEF locale crashes",
                    category: .locale
                ),
                LauncherFixDetail(
                    key: "LC_TIME", value: "C",
                    reason: "Avoids ICU date/time parsing errors",
                    category: .locale
                ),
                LauncherFixDetail(
                    key: "LC_NUMERIC", value: "C",
                    reason: "Avoids ICU numeric parsing errors",
                    category: .locale
                ),
                LauncherFixDetail(
                    key: "STEAM_DISABLE_CEF_SANDBOX", value: "1",
                    reason: "Disables Steam-specific CEF sandbox (crashes under Wine)",
                    category: .sandbox
                ),
                LauncherFixDetail(
                    key: "STEAM_RUNTIME", value: "0",
                    reason: "Disables Steam Runtime (incompatible with Wine)",
                    category: .compatibility
                ),
                LauncherFixDetail(
                    key: "DXVK_ASYNC", value: "1",
                    reason: "Reduces UI stuttering in Steam client",
                    category: .graphics
                )
            ]

        case .rockstar:
            [
                LauncherFixDetail(
                    key: "DXVK_REQUIRED", value: "1",
                    reason: "DXVK required for logo screen rendering",
                    category: .graphics
                ),
                LauncherFixDetail(
                    key: "D3DM_FORCE_D3D11", value: "1",
                    reason: "Forces D3D11 mode for launcher compatibility",
                    category: .graphics
                ),
                LauncherFixDetail(
                    key: "WINE_LARGE_ADDRESS_AWARE", value: "1",
                    reason: "Improves launcher initialization memory handling",
                    category: .compatibility
                ),
                LauncherFixDetail(
                    key: "LC_ALL", value: "en_US.UTF-8",
                    reason: "Sets locale for launcher UI rendering",
                    category: .locale
                )
            ]

        case .eaApp:
            [
                LauncherFixDetail(
                    key: "LC_ALL", value: "en_US.UTF-8",
                    reason: "Fixes Chromium-based launcher locale issues",
                    category: .locale
                ),
                LauncherFixDetail(
                    key: "LANG", value: "en_US.UTF-8",
                    reason: "Fixes Chromium-based launcher locale issues",
                    category: .locale
                ),
                LauncherFixDetail(
                    key: "D3DM_FEATURE_LEVEL_12_1", value: "1",
                    reason: "Fixes GPU not supported detection errors",
                    category: .graphics
                )
            ]

        case .epicGames:
            [
                LauncherFixDetail(
                    key: "LC_ALL", value: "en_US.UTF-8",
                    reason: "Fixes Chromium-based launcher locale issues",
                    category: .locale
                ),
                LauncherFixDetail(
                    key: "D3DM_FORCE_D3D11", value: "1",
                    reason: "Improves launcher UI rendering stability",
                    category: .graphics
                ),
                LauncherFixDetail(
                    key: "WINE_DISABLE_NTDLL_THREAD_REGS", value: "1",
                    reason: "Fixes thread safety for Epic web views",
                    category: .threading
                )
            ]

        case .ubisoft:
            [
                LauncherFixDetail(
                    key: "D3DM_FORCE_D3D11", value: "1",
                    reason: "Required D3D11 mode for Ubisoft Connect stability",
                    category: .graphics
                ),
                LauncherFixDetail(
                    key: "DXVK_ASYNC", value: "1",
                    reason: "Improves rendering for Anno 1800 and other Ubisoft games",
                    category: .graphics
                )
            ]

        case .battleNet:
            [
                LauncherFixDetail(
                    key: "LC_ALL", value: "en_US.UTF-8",
                    reason: "Fixes Chromium-based launcher locale issues",
                    category: .locale
                ),
                LauncherFixDetail(
                    key: "WINE_CPU_TOPOLOGY", value: "8:8",
                    reason: "Configures threading for Battle.net authentication",
                    category: .threading
                )
            ]

        case .paradox:
            [
                LauncherFixDetail(
                    key: "WINE_DISABLE_FAST_PATH", value: "1",
                    reason: "Fixes recursive resource lookup bug",
                    category: .compatibility
                ),
                LauncherFixDetail(
                    key: "D3DM_FORCE_D3D11", value: "1",
                    reason: "Improves launcher initialization",
                    category: .graphics
                )
            ]
        }
    }

    // swiftlint:enable function_body_length
}
