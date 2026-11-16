//
//  WhiskyWineInstaller+UpdateCheck.swift
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

extension WhiskyWineInstaller {
    /// The defaults key behind Settings' "Automatically check for WhiskyWine updates".
    public static let automaticUpdateCheckDefaultsKey = "checkWhiskyWineUpdates"

    /// Whether the runtime update check may run on its own at launch.
    ///
    /// The setting defaults to on, matching the Settings toggle, so a user who
    /// never opened Settings keeps getting the check. Only the automatic check
    /// reads it; an update the user asks for runs regardless.
    ///
    /// - Parameter defaults: The defaults to read. Defaults to `.standard`.
    /// - Returns: `false` only when the user turned the setting off.
    public static func automaticUpdateChecksEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: automaticUpdateCheckDefaultsKey) as? Bool ?? true
    }
}
