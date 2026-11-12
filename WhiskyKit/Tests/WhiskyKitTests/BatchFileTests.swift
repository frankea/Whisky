//
//  BatchFileTests.swift
//  WhiskyKitTests
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

@Suite("Batch file detection")
struct BatchFileTests {
    @Test("A .bat or .cmd script runs as a batch file, whatever its case", arguments: [
        "setup.bat", "setup.cmd", "SETUP.BAT", "Setup.Cmd", "C:/Games/run game.cmd"
    ])
    func batchScripts(_ name: String) {
        #expect(Wine.isBatchFile(URL(filePath: "/bottle/drive_c/\(name)")))
    }

    @Test("Programs, installers and other files are not batch files", arguments: [
        "game.exe", "setup.msi", "notes.txt", "script.ps1", "batch", "cmd", "archive.cmd.zip"
    ])
    func otherFiles(_ name: String) {
        #expect(!Wine.isBatchFile(URL(filePath: "/bottle/drive_c/\(name)")))
    }
}
