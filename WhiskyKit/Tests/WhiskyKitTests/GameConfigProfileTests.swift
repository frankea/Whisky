//
//  GameConfigProfileTests.swift
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
import Testing
@testable import WhiskyKit

@Suite("Game configuration launch profile")
struct GameConfigProfileTests {
    @Test("A launch's profile adds the caller's variables, and the caller's win")
    func launchProfileMergesCaller() {
        var settings = BottleSettings()
        settings.gameConfigEnvironments = [
            GameConfigEnvironment(
                entryId: "game", title: "Game", executables: ["Game.exe"], variables: ["A": "1", "B": "1"]
            )
        ]
        let game = URL(filePath: "/bottle/drive_c/Game/Game.exe")

        let profile = settings.gameConfigProfile(launching: game, caller: ["B": "2", "C": "3"])
        #expect(profile == ["A": "1", "B": "2", "C": "3"])
    }

    @Test("A launch of another executable gets only the caller's variables")
    func launchProfileForOtherExecutable() {
        var settings = BottleSettings()
        settings.gameConfigEnvironments = [
            GameConfigEnvironment(entryId: "game", title: "Game", executables: ["Game.exe"], variables: ["A": "1"])
        ]

        let profile = settings.gameConfigProfile(launching: URL(filePath: "/x/Tool.exe"), caller: ["C": "3"])
        #expect(profile == ["C": "3"])
    }
}
