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
    func testProgramNameFromURL() throws {
        let bottle = Bottle(bottleUrl: bottleURL)
        let program = Program(url: programURL, bottle: bottle)

        XCTAssertEqual(program.name, "test_game.exe")
    }

    @MainActor
    func testProgramNameWithSpaces() throws {
        let spaceURL = bottleURL.appending(path: "drive_c/Program With Spaces.exe")
        try? Data("fake exe".utf8).write(to: spaceURL)

        let bottle = Bottle(bottleUrl: bottleURL)
        let program = Program(url: spaceURL, bottle: bottle)

        XCTAssertEqual(program.name, "Program With Spaces.exe")
    }

    // MARK: - ID Property Tests

    @MainActor
    func testProgramIdEqualsURL() throws {
        let bottle = Bottle(bottleUrl: bottleURL)
        let program = Program(url: programURL, bottle: bottle)

        XCTAssertEqual(program.id, programURL)
    }

    // MARK: - Equatable Tests

    @MainActor
    func testProgramEquatableWithSameURL() throws {
        let bottle = Bottle(bottleUrl: bottleURL)
        let program1 = Program(url: programURL, bottle: bottle)
        let program2 = Program(url: programURL, bottle: bottle)

        XCTAssertEqual(program1, program2)
    }

    @MainActor
    func testProgramEquatableWithDifferentURL() throws {
        let otherURL = bottleURL.appending(path: "drive_c/other.exe")
        try? Data("fake exe".utf8).write(to: otherURL)

        let bottle = Bottle(bottleUrl: bottleURL)
        let program1 = Program(url: programURL, bottle: bottle)
        let program2 = Program(url: otherURL, bottle: bottle)

        XCTAssertNotEqual(program1, program2)
    }

    // MARK: - Hashable Tests

    @MainActor
    func testProgramHashableConsistency() throws {
        let bottle = Bottle(bottleUrl: bottleURL)
        let program1 = Program(url: programURL, bottle: bottle)
        let program2 = Program(url: programURL, bottle: bottle)

        XCTAssertEqual(program1.hashValue, program2.hashValue)
    }

    @MainActor
    func testProgramHashableInSet() throws {
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
    func testProgramHashableDeduplication() throws {
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
    func testProgramSettingsURLLocation() throws {
        let bottle = Bottle(bottleUrl: bottleURL)
        let program = Program(url: programURL, bottle: bottle)

        XCTAssertTrue(program.settingsURL.path.contains("Program Settings"))
        XCTAssertTrue(program.settingsURL.path.contains("test_game.exe.plist"))
    }

    // MARK: - Pinned Property Tests

    @MainActor
    func testProgramInitiallyNotPinned() throws {
        let bottle = Bottle(bottleUrl: bottleURL)
        let program = Program(url: programURL, bottle: bottle)

        XCTAssertFalse(program.pinned)
    }

    @MainActor
    func testProgramPinAddsToBottlePins() throws {
        let bottle = Bottle(bottleUrl: bottleURL)
        let program = Program(url: programURL, bottle: bottle)

        program.pinned = true

        XCTAssertTrue(program.pinned)
        XCTAssertTrue(bottle.settings.pins.contains(where: { $0.url == programURL }))
    }

    @MainActor
    func testProgramUnpinRemovesFromBottlePins() throws {
        let bottle = Bottle(bottleUrl: bottleURL)
        let program = Program(url: programURL, bottle: bottle)

        program.pinned = true
        XCTAssertTrue(bottle.settings.pins.contains(where: { $0.url == programURL }))

        program.pinned = false
        XCTAssertFalse(bottle.settings.pins.contains(where: { $0.url == programURL }))
    }

    @MainActor
    func testProgramPinnedNameRemovesExeExtension() throws {
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
    func testProgramHasCorrectBottleReference() throws {
        let bottle = Bottle(bottleUrl: bottleURL)
        let program = Program(url: programURL, bottle: bottle)

        XCTAssertEqual(program.bottle.url, bottleURL)
    }
}
