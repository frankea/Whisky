//
//  ProgramTests.swift
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
@testable import WhiskyKit
import XCTest

// MARK: - Program Core Functionality Tests

final class ProgramCoreTests: XCTestCase {
    var tempDir: URL!
    var bottleURL: URL!
    var programURL: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appending(path: "program_core_\(UUID().uuidString)")
        bottleURL = tempDir.appending(path: "TestBottle")

        let driveCURL = bottleURL.appending(path: "drive_c")
        try? FileManager.default.createDirectory(at: driveCURL, withIntermediateDirectories: true)

        programURL = driveCURL.appending(path: "test_game.exe")
        try? Data("fake exe".utf8).write(to: programURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Name Property Tests

    @MainActor
    func testProgramNameFromURL() {
        let bottle = Bottle(bottleUrl: bottleURL)
        let program = Program(url: programURL, bottle: bottle)

        XCTAssertEqual(program.name, "test_game.exe")
    }

    @MainActor
    func testProgramNameWithSpaces() {
        let spaceURL = bottleURL.appending(path: "drive_c/Program With Spaces.exe")
        try? Data("fake exe".utf8).write(to: spaceURL)

        let bottle = Bottle(bottleUrl: bottleURL)
        let program = Program(url: spaceURL, bottle: bottle)

        XCTAssertEqual(program.name, "Program With Spaces.exe")
    }

    // MARK: - ID Property Tests

    @MainActor
    func testProgramIdEqualsURL() {
        let bottle = Bottle(bottleUrl: bottleURL)
        let program = Program(url: programURL, bottle: bottle)

        XCTAssertEqual(program.id, programURL)
    }

    // MARK: - Equatable Tests

    @MainActor
    func testProgramEquatableWithSameURL() {
        let bottle = Bottle(bottleUrl: bottleURL)
        let program1 = Program(url: programURL, bottle: bottle)
        let program2 = Program(url: programURL, bottle: bottle)

        XCTAssertEqual(program1, program2)
    }

    @MainActor
    func testProgramEquatableWithDifferentURL() {
        let otherURL = bottleURL.appending(path: "drive_c/other.exe")
        try? Data("fake exe".utf8).write(to: otherURL)

        let bottle = Bottle(bottleUrl: bottleURL)
        let program1 = Program(url: programURL, bottle: bottle)
        let program2 = Program(url: otherURL, bottle: bottle)

        XCTAssertNotEqual(program1, program2)
    }

    // MARK: - Hashable Tests

    @MainActor
    func testProgramHashableConsistency() {
        let bottle = Bottle(bottleUrl: bottleURL)
        let program1 = Program(url: programURL, bottle: bottle)
        let program2 = Program(url: programURL, bottle: bottle)

        XCTAssertEqual(program1.hashValue, program2.hashValue)
    }

    @MainActor
    func testProgramHashableInSet() {
        let otherURL = bottleURL.appending(path: "drive_c/other.exe")
        try? Data("fake exe".utf8).write(to: otherURL)

        let bottle = Bottle(bottleUrl: bottleURL)
        let program1 = Program(url: programURL, bottle: bottle)
        let program2 = Program(url: otherURL, bottle: bottle)

        var programSet: Set<Program> = []
        programSet.insert(program1)
        programSet.insert(program2)

        XCTAssertEqual(programSet.count, 2)
        XCTAssertTrue(programSet.contains(program1))
        XCTAssertTrue(programSet.contains(program2))
    }

    @MainActor
    func testProgramHashableDeduplication() {
        let bottle = Bottle(bottleUrl: bottleURL)
        let program1 = Program(url: programURL, bottle: bottle)
        let program2 = Program(url: programURL, bottle: bottle)

        var programSet: Set<Program> = []
        programSet.insert(program1)
        programSet.insert(program2)

        // Same URL should dedupe to 1 entry
        XCTAssertEqual(programSet.count, 1)
    }

    // MARK: - Settings URL Tests

    @MainActor
    func testProgramSettingsURLLocation() {
        let bottle = Bottle(bottleUrl: bottleURL)
        let program = Program(url: programURL, bottle: bottle)

        XCTAssertTrue(program.settingsURL.path.contains("Program Settings"))
        // Identity-keyed: exe stem plus a short path hash, not the bare filename
        XCTAssertTrue(program.settingsURL.lastPathComponent.hasPrefix("test_game-"))
        XCTAssertTrue(program.settingsURL.pathExtension == "plist")
    }

    // MARK: - Pinned Property Tests

    @MainActor
    func testProgramInitiallyNotPinned() {
        let bottle = Bottle(bottleUrl: bottleURL)
        let program = Program(url: programURL, bottle: bottle)

        XCTAssertFalse(program.pinned)
    }

    @MainActor
    func testProgramPinAddsToBottlePins() {
        let bottle = Bottle(bottleUrl: bottleURL)
        let program = Program(url: programURL, bottle: bottle)

        program.pinned = true

        XCTAssertTrue(program.pinned)
        XCTAssertTrue(bottle.settings.pins.contains(where: { $0.url == programURL }))
    }

    @MainActor
    func testProgramUnpinRemovesFromBottlePins() {
        let bottle = Bottle(bottleUrl: bottleURL)
        let program = Program(url: programURL, bottle: bottle)

        program.pinned = true
        XCTAssertTrue(bottle.settings.pins.contains(where: { $0.url == programURL }))

        program.pinned = false
        XCTAssertFalse(bottle.settings.pins.contains(where: { $0.url == programURL }))
    }

    @MainActor
    func testRepinningPinnedProgramKeepsOnePin() {
        let bottle = Bottle(bottleUrl: bottleURL)
        let program = Program(url: programURL, bottle: bottle)

        program.pinned = true
        program.pinned = true

        XCTAssertEqual(bottle.settings.pins.filter { $0.url == programURL }.count, 1)
    }

    @MainActor
    func testRepinningProgramPinnedOnLoadKeepsOnePin() {
        let bottle = Bottle(bottleUrl: bottleURL)
        Program(url: programURL, bottle: bottle).pinned = true

        // A fresh instance reads its pin state from the bottle, as after a reload.
        let reloaded = Program(url: programURL, bottle: bottle)
        XCTAssertTrue(reloaded.pinned)
        reloaded.pinned = true

        XCTAssertEqual(bottle.settings.pins.filter { $0.url == programURL }.count, 1)
    }

    @MainActor
    func testSettingsSaveAfterRepinPersistsOnePin() throws {
        let bottle = Bottle(bottleUrl: bottleURL)
        let program = Program(url: programURL, bottle: bottle)
        program.pinned = true
        program.pinned = true

        // Any later settings change saves the whole pin list.
        bottle.settings.windowsVersion = .win7

        let persisted = try BottleSettings.decode(from: bottleURL.appending(path: "Metadata.plist"))
        XCTAssertEqual(persisted.pins.filter { $0.url == programURL }.count, 1)
    }

    @MainActor
    func testProgramPinnedNameRemovesExeExtension() {
        let bottle = Bottle(bottleUrl: bottleURL)
        let program = Program(url: programURL, bottle: bottle)

        program.pinned = true

        guard let pinnedProgram = bottle.settings.pins.first(where: { $0.url == programURL }) else {
            XCTFail("Pinned program not found")
            return
        }

        XCTAssertEqual(pinnedProgram.name, "test_game")
    }

    // MARK: - Bottle Reference Tests

    @MainActor
    func testProgramHasCorrectBottleReference() {
        let bottle = Bottle(bottleUrl: bottleURL)
        let program = Program(url: programURL, bottle: bottle)

        XCTAssertEqual(program.bottle.url, bottleURL)
    }
}
