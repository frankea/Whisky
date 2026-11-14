//
//  ProgramSettingsSyncTests.swift
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

/// Two `Program`s for one executable, as when the Library, the Dock or the
/// menu bar builds its own for a pin the bottle's list doesn't have yet, must
/// not undo each other's settings: each saves its settings whole.
@Suite("Program Settings Sync Tests")
@MainActor
struct ProgramSettingsSyncTests {
    private let diagnosisDate = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let logURL = URL(fileURLWithPath: "/tmp/whisky-logs/2026-11-14T10:00:00.000Z.log")

    /// A bottle in a temporary folder with one executable in it.
    private struct Fixture {
        let bottle: Bottle
        let exe: URL

        @MainActor
        func remove() {
            try? FileManager.default.removeItem(at: bottle.url)
        }
    }

    private func makeFixture() throws -> Fixture {
        let bottleURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let exe = bottleURL.appending(path: "drive_c/Game/game.exe")
        try FileManager.default.createDirectory(at: exe.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("MZ".utf8).write(to: exe)
        return Fixture(bottle: Bottle(bottleUrl: bottleURL, inFlight: false, isAvailable: true), exe: exe)
    }

    @Test("A crash stamp on a launch path's copy survives the bottle list's copy saving")
    func diagnosisStampSurvivesTheOtherCopySaving() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let listed = Program(url: fixture.exe, bottle: fixture.bottle, peFile: nil)
        let launched = Program(url: fixture.exe, bottle: fixture.bottle, peFile: nil)

        // The crash classification of a launch from the Library stamps its copy...
        launched.settings.lastDiagnosisDate = diagnosisDate
        // ...then the next launch, from the bottle's own list, records its log.
        listed.settings.lastLogFileURL = logURL

        #expect(listed.settings.lastDiagnosisDate == diagnosisDate, "the diagnostics buttons read this copy")
        #expect(launched.settings.lastLogFileURL == logURL)
        let saved = try #require(try ProgramSettings.decodeIfPresent(from: listed.settingsURL))
        #expect(saved.lastDiagnosisDate == diagnosisDate)
        #expect(saved.lastLogFileURL == logURL)
    }

    @Test("A log recorded by one copy survives a stamp from the other")
    func logSurvivesTheOtherCopyStamping() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let listed = Program(url: fixture.exe, bottle: fixture.bottle, peFile: nil)
        let launched = Program(url: fixture.exe, bottle: fixture.bottle, peFile: nil)

        listed.settings.lastLogFileURL = logURL
        launched.settings.lastDiagnosisDate = diagnosisDate

        let reloaded = Program(url: fixture.exe, bottle: fixture.bottle, peFile: nil)
        #expect(reloaded.settings.lastLogFileURL == logURL)
        #expect(reloaded.settings.lastDiagnosisDate == diagnosisDate)
        #expect(listed.settings.lastDiagnosisDate == diagnosisDate)
    }

    @Test("Copies made from two loads of the same bottle stay in step")
    func copiesFromReloadedBottlesStayInStep() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        // Reloading the bottle list builds new Bottle objects for the same folder.
        let reloadedBottle = Bottle(bottleUrl: fixture.bottle.url, inFlight: false, isAvailable: true)
        let old = Program(url: fixture.exe, bottle: fixture.bottle, peFile: nil)
        let new = Program(url: fixture.exe, bottle: reloadedBottle, peFile: nil)

        new.settings.arguments = "-windowed"
        old.settings.lastDiagnosisDate = diagnosisDate

        #expect(old.settings.arguments == "-windowed")
        #expect(new.settings.lastDiagnosisDate == diagnosisDate)
    }

    @Test("A change leaves other programs' settings alone")
    func otherProgramsAreUntouched() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let otherExe = fixture.exe.deletingLastPathComponent().appending(path: "launcher.exe")
        try Data("MZ".utf8).write(to: otherExe)
        let program = Program(url: fixture.exe, bottle: fixture.bottle, peFile: nil)
        let other = Program(url: otherExe, bottle: fixture.bottle, peFile: nil)

        program.settings.lastDiagnosisDate = diagnosisDate

        #expect(other.settings.lastDiagnosisDate == nil)
    }
}
