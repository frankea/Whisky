//
//  LauncherBackendMigration.swift
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

/// Puts a bottle that an older Steam profile switched to DXVK back on Recommended, once.
///
/// Up to 3.7.0, the Steam profile Play applies set the whole bottle to DXVK so
/// the client could draw. That turned `d3d12` off for every game Steam
/// started, so a DirectX 12 game with no D3D11 path never came up (#276). The
/// profile now leaves a bottle on Recommended and scopes DXVK to Steam's own
/// processes, but bottles it already switched still say DXVK on disk.
///
/// From the settings alone such a bottle looks the same as one where the user
/// picked DXVK, so the migration is narrow: launcher mode auto, Steam as the
/// detected launcher, DXVK as the backend, and D3DMetal installed, so that
/// Recommended means D3DMetal for the games and the scoped layout applies.
/// It runs once per bottle. Every bottle is stamped the first time it is
/// looked at, whether it changed or not, so a backend picked after the update
/// is never undone. Manual mode is never touched.
public enum LauncherBackendMigration {
    /// The migration this version performs. A bottle stamped below it has not
    /// been through it yet.
    public static let current = 1

    /// Runs the migration on `bottle` if it has not been through it.
    ///
    /// Saves the bottle's settings once when it stamps them, and not at all
    /// when the bottle is already stamped.
    ///
    /// - Parameters:
    ///   - bottle: The bottle to look at.
    ///   - d3dMetalInstalled: Whether the D3DMetal payload is installed, which
    ///     is what makes Recommended resolve to it. Defaults to checking the
    ///     installed runtime.
    /// - Returns: Whether the bottle was put back on Recommended.
    @MainActor
    @discardableResult
    public static func migrateIfNeeded(
        _ bottle: Bottle, d3dMetalInstalled: Bool = WhiskyWineInstaller.isD3DMetalInstalled()
    ) -> Bool {
        guard bottle.settings.launcherBackendMigration < current else { return false }

        var settings = bottle.settings
        let reset = wasSwitchedBySteamProfile(settings) && d3dMetalInstalled
        if reset {
            settings.graphicsBackend = .recommended
            settings.launcherBackendResetNotice = true
            Logger.wineKit.info(
                "Put '\(settings.name, privacy: .public)' back on Recommended; Steam keeps DXVK per executable"
            )
        }
        settings.launcherBackendMigration = current
        // One assignment, so one save.
        bottle.settings = settings
        return reset
    }

    /// Whether the settings look like the result of the old Steam profile.
    static func wasSwitchedBySteamProfile(_ settings: BottleSettings) -> Bool {
        settings.launcherMode == .auto
            && settings.detectedLauncher == .steam
            && settings.graphicsBackend == .dxvk
    }
}
