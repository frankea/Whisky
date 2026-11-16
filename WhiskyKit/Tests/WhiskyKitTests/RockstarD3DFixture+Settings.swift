//
//  RockstarD3DFixture+Settings.swift
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
@testable import WhiskyKit

extension RockstarD3DFixture {
    /// Persists `overrides` as the program settings of `executable`.
    func setOverrides(_ overrides: ProgramOverrides, for executable: URL) throws {
        let settingsURL = Program.settingsLocations(
            for: executable, bottleURL: bottle.url, legacyName: executable.lastPathComponent
        ).identity
        var settings = ProgramSettings()
        settings.overrides = overrides
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try settings.encode(to: settingsURL)
    }

    /// Writes the bottle's `user.reg` with `sections` after Wine's header.
    func writeUserReg(_ sections: String) throws {
        try ("WINE REGISTRY Version 2\n\n" + sections)
            .write(to: bottle.url.appending(path: "user.reg"), atomically: true, encoding: .utf8)
    }

    /// Rockstar's own files gone the way its uninstaller takes them: the
    /// launcher, and Social Club's own files, leaving whatever else is there.
    func uninstallRockstar() throws {
        try FileManager.default.removeItem(at: rockstarLauncher.deletingLastPathComponent())
        let helper = socialClub.appending(path: "SocialClubHelper.exe")
        if Self.exists(helper) {
            try FileManager.default.removeItem(at: helper)
        }
    }
}
