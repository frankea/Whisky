//
//  BottleMostRecentDiagnosisTests.swift
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

/// Which program the bottle's diagnostics buttons open the diagnosis of.
@Suite("Bottle Most Recent Diagnosis Tests")
@MainActor
struct BottleMostRecentDiagnosisTests {
    /// A bottle in a temporary folder holding the named executables as programs.
    private func makeBottle(executables: [String]) throws -> Bottle {
        let bottleURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let bottle = Bottle(bottleUrl: bottleURL, inFlight: false, isAvailable: true)
        let folder = bottleURL.appending(path: "drive_c/Games")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        bottle.programs = try executables.map { name in
            let exe = folder.appending(path: name)
            try Data("MZ".utf8).write(to: exe)
            return Program(url: exe, bottle: bottle, peFile: nil)
        }
        return bottle
    }

    @Test("No program is picked when none has a diagnosis")
    func nilWhenNoneStamped() throws {
        let bottle = try makeBottle(executables: ["launcher.exe", "game.exe"])
        defer { try? FileManager.default.removeItem(at: bottle.url) }

        #expect(bottle.mostRecentlyDiagnosedProgram == nil)
    }

    @Test("No program is picked from an empty bottle")
    func nilWhenNoPrograms() throws {
        let bottle = try makeBottle(executables: [])
        defer { try? FileManager.default.removeItem(at: bottle.url) }

        #expect(bottle.mostRecentlyDiagnosedProgram == nil)
    }

    @Test("The only diagnosed program is picked over undiagnosed ones")
    func onlyStampedProgramWins() throws {
        let bottle = try makeBottle(executables: ["launcher.exe", "game.exe", "tool.exe"])
        defer { try? FileManager.default.removeItem(at: bottle.url) }
        bottle.programs[1].settings.lastDiagnosisDate = Date(timeIntervalSinceReferenceDate: 800_000_000)

        #expect(bottle.mostRecentlyDiagnosedProgram === bottle.programs[1])
    }

    @Test("The newest diagnosis wins, wherever it sits in the list")
    func newestWins() throws {
        let bottle = try makeBottle(executables: ["launcher.exe", "game.exe", "tool.exe"])
        defer { try? FileManager.default.removeItem(at: bottle.url) }
        bottle.programs[0].settings.lastDiagnosisDate = Date(timeIntervalSinceReferenceDate: 800_000_000)
        bottle.programs[1].settings.lastDiagnosisDate = Date(timeIntervalSinceReferenceDate: 800_000_600)
        bottle.programs[2].settings.lastDiagnosisDate = Date(timeIntervalSinceReferenceDate: 800_000_300)

        #expect(bottle.mostRecentlyDiagnosedProgram === bottle.programs[1])

        bottle.programs[2].settings.lastDiagnosisDate = Date(timeIntervalSinceReferenceDate: 800_001_000)

        #expect(bottle.mostRecentlyDiagnosedProgram === bottle.programs[2])
    }
}
