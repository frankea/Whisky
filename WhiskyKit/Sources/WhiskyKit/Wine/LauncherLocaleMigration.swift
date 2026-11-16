//
//  LauncherLocaleMigration.swift
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

/// Puts a launcher bottle's Locale Override back on Auto, where older
/// versions set it to English without asking.
///
/// Up to 3.8.0, configuring a bottle for Steam, EA App, Epic Games,
/// Battle.net, or Rockstar (the first launch in auto mode, a change of
/// launcher, or Reapply Launcher Fixes) wrote `launcherLocale = .english`.
/// 3.9.0 stopped writing it. The Steam preset now sets no locale, so on Auto
/// the games Steam starts get the Mac's language and region (#330); a saved
/// English keeps them on en_US. Until now English and Auto meant the same for
/// Steam, so a saved English is taken for the old default.
///
/// A bottle can hold more than one launcher, and the detected one changes
/// with the last one configured, so English counts for any of the five: an
/// English written for Steam may sit under EA App when the migration runs,
/// and come back to Steam afterwards. For the other four, Auto still gives
/// en_US through their presets.
///
/// From the settings alone, that English looks the same as one the user
/// picked, so only bottles that have not been through this migration count,
/// and the first look stamps every bottle: an English picked afterwards stays.
public enum LauncherLocaleMigration {
    /// The migration this version performs. A bottle stamped below it has not
    /// been through it yet.
    public static let current = 1

    /// Runs the migration on `bottle`: stamps it if it has not been through
    /// it, and puts a launcher bottle's English back on Auto.
    ///
    /// Saves the bottle's settings once when anything changed, and not at all
    /// otherwise, so it is cheap to run on every load.
    ///
    /// - Parameter bottle: The bottle to look at.
    /// - Returns: Whether the locale was put back on Auto.
    @MainActor
    @discardableResult
    public static func migrateIfNeeded(_ bottle: Bottle) -> Bool {
        var settings = bottle.settings
        guard settings.launcherLocaleMigration < current else { return false }

        let reset = wasSetByOldLauncherFixes(settings)
        if reset {
            settings.launcherLocale = .auto
            Logger.wineKit.info(
                "Put '\(settings.name, privacy: .public)' back on Auto locale; older launcher fixes set English"
            )
        }
        settings.launcherLocaleMigration = current
        // One assignment, so one save.
        bottle.settings = settings
        return reset
    }

    /// The launchers whose fixes wrote English up to 3.8.0.
    static let launchersThatWroteEnglish: Set<LauncherType> = [.steam, .eaApp, .epicGames, .battleNet, .rockstar]

    /// Whether the settings look like the English older launcher fixes wrote.
    static func wasSetByOldLauncherFixes(_ settings: BottleSettings) -> Bool {
        guard let launcher = settings.detectedLauncher else { return false }
        return launchersThatWroteEnglish.contains(launcher) && settings.launcherLocale == .english
    }
}
