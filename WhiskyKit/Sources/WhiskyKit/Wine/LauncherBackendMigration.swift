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

/// Puts a bottle that a Steam profile switched to DXVK back on Recommended,
/// once D3DMetal is there to serve its games.
///
/// Up to 3.7.0, the Steam profile Play applies set the whole bottle to DXVK so
/// the client could draw. That turned `d3d12` off for every game Steam
/// started, so a DirectX 12 game with no D3D11 path never came up (#276). The
/// profile now leaves a bottle on Recommended and scopes DXVK to Steam's own
/// processes, but only over D3DMetal: on a runtime without the payload it
/// still switches the bottle, and bottles it switched before still say DXVK
/// on disk.
///
/// Two kinds of bottle qualify:
///
/// - One the profile switched from Recommended since this version, which says
///   so (`launcherSwitchedBackend`). Any later change of backend clears that,
///   so a DXVK picked by the user is never undone.
/// - One an older version switched. From the settings alone that looks the
///   same as a DXVK the user picked, so only a narrow shape counts: launcher
///   mode auto, Steam as the detected launcher, DXVK as the backend. The first
///   look at such a bottle marks it as switched by the profile, and every
///   bottle is stamped then, so the guess is made once.
/// - A Steam bottle the Rockstar profile took over. From 3.8.0 to 3.10.1,
///   starting Rockstar's launcher from the Programs tab, or forcing Apply
///   Launcher Fixes for it, applied Rockstar's profile to a bottle with Steam:
///   Rockstar became the detected launcher and, with Auto-enable DXVK on, the
///   bottle went to DXVK. Since the backend changed, nothing marked that
///   switch. Such a bottle, in launcher mode auto with Rockstar detected and
///   Steam installed, gets Steam back as its launcher, and its DXVK is marked
///   as the profile's, once.
///
/// A qualifying bottle goes back to Recommended as soon as D3DMetal is
/// installed: on load, or right after the payload is imported or deployed. A
/// bottle first looked at without the payload waits for it. The graphics
/// settings then show a one-line notice.
public enum LauncherBackendMigration {
    /// The migration this version performs. A bottle stamped below it has not
    /// been through it yet. 2 marks old-profile bottles instead of skipping
    /// them when the payload is missing; 3 gives Steam back the bottles the
    /// Rockstar profile took over.
    ///
    /// Each step runs only on bottles stamped below its own version, so a
    /// bottle stamped 2 never has its DXVK guessed at again.
    public static let current = 3

    /// The version that marks bottles an older Steam profile switched.
    static let steamProfileVersion = 2

    /// The version that gives Steam back the bottles the Rockstar profile took over.
    static let rockstarRepairVersion = 3

    /// Runs the migration on `bottle`: runs the steps it has not been through
    /// and stamps it, then puts it back on Recommended if it qualifies and
    /// D3DMetal is installed.
    ///
    /// Saves the bottle's settings once when anything changed, and not at all
    /// otherwise, so it is cheap to run on every load and after every import.
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
        var settings = bottle.settings
        var changed = false
        let stamp = settings.launcherBackendMigration
        if stamp < current {
            if stamp < steamProfileVersion, wasSwitchedBySteamProfile(settings) {
                settings.launcherSwitchedBackend = true
            }
            if stamp < rockstarRepairVersion, wasTakenOverByRockstarProfile(settings, bottleURL: bottle.url) {
                giveBackToSteam(&settings)
                Logger.wineKit.info(
                    "Gave '\(settings.name, privacy: .public)' back to Steam from the Rockstar profile"
                )
            }
            settings.launcherBackendMigration = current
            changed = true
        }

        let reset = d3dMetalInstalled && isRestorable(settings)
        if reset {
            restore(&settings)
            Logger.wineKit.info(
                "Put '\(settings.name, privacy: .public)' back on Recommended; Steam keeps DXVK per executable"
            )
            changed = true
        }
        if changed {
            // One assignment, so one save.
            bottle.settings = settings
        }
        return reset
    }

    /// Whether the settings are on DXVK only because a Steam profile put them there.
    static func isRestorable(_ settings: BottleSettings) -> Bool {
        settings.launcherSwitchedBackend
            && settings.graphicsBackend == .dxvk
            && settings.detectedLauncher == .steam
    }

    /// Puts the settings back on Recommended and raises the notice that says so.
    static func restore(_ settings: inout BottleSettings) {
        // Clears launcherSwitchedBackend too.
        settings.graphicsBackend = .recommended
        settings.launcherBackendResetNotice = true
    }

    /// Whether the settings look like the result of an older Steam profile.
    static func wasSwitchedBySteamProfile(_ settings: BottleSettings) -> Bool {
        settings.launcherMode == .auto
            && settings.detectedLauncher == .steam
            && settings.graphicsBackend == .dxvk
    }

    /// Whether the bottle is a Steam bottle the Rockstar profile took over:
    /// launcher mode auto, Rockstar detected, and Steam installed. A bottle
    /// with only Rockstar's launcher keeps Rockstar's profile.
    static func wasTakenOverByRockstarProfile(_ settings: BottleSettings, bottleURL: URL) -> Bool {
        settings.launcherMode == .auto
            && settings.detectedLauncher == .rockstar
            && SteamLibrary.detectInstall(bottleURL: bottleURL) != nil
    }

    /// Makes Steam the detected launcher again and, when the Rockstar profile
    /// can have put the bottle on DXVK, marks that DXVK as the profile's, so
    /// ``isRestorable(_:)`` puts it back on Recommended over D3DMetal.
    static func giveBackToSteam(_ settings: inout BottleSettings) {
        settings.detectedLauncher = .steam
        if settings.graphicsBackend == .dxvk, settings.autoEnableDXVK {
            settings.launcherSwitchedBackend = true
        }
    }
}
