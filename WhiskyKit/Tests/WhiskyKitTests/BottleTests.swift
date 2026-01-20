//
//  BottleTests.swift
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

// MARK: - Bottle Core Tests

final class BottleCoreTests: XCTestCase {
    var tempDir: URL!
    var bottleURL: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appending(path: "bottle_test_\(UUID().uuidString)")
        bottleURL = tempDir.appending(path: "TestBottle")

        let driveCURL = bottleURL.appending(path: "drive_c")
        try? FileManager.default.createDirectory(at: driveCURL, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Initialization Tests

    @MainActor
    func testBottleInitializationWithURL() {
        let bottle = Bottle(bottleUrl: bottleURL)

        XCTAssertEqual(bottle.url, bottleURL)
    }

    @MainActor
    func testBottleInitializationWithInFlight() {
        let bottle = Bottle(bottleUrl: bottleURL, inFlight: true)

        XCTAssertTrue(bottle.inFlight)
    }

    @MainActor
    func testBottleInitializationWithIsAvailable() {
        let bottle = Bottle(bottleUrl: bottleURL, isAvailable: true)

        XCTAssertTrue(bottle.isAvailable)
    }

    @MainActor
    func testBottleInitializationCreatesDefaultSettings() {
        let bottle = Bottle(bottleUrl: bottleURL)

        XCTAssertNotNil(bottle.settings)
    }

    // MARK: - ID Property Tests

    @MainActor
    func testBottleIdEqualsURL() {
        let bottle = Bottle(bottleUrl: bottleURL)

        XCTAssertEqual(bottle.id, bottleURL)
    }

    // MARK: - Equatable Tests

    @MainActor
    func testBottleEquatableWithSameURL() {
        let bottle1 = Bottle(bottleUrl: bottleURL)
        let bottle2 = Bottle(bottleUrl: bottleURL)

        XCTAssertEqual(bottle1, bottle2)
    }

    @MainActor
    func testBottleEquatableWithDifferentURL() {
        let otherURL = tempDir.appending(path: "OtherBottle")
        try? FileManager.default.createDirectory(
            at: otherURL.appending(path: "drive_c"),
            withIntermediateDirectories: true
        )

        let bottle1 = Bottle(bottleUrl: bottleURL)
        let bottle2 = Bottle(bottleUrl: otherURL)

        XCTAssertNotEqual(bottle1, bottle2)
    }

    // MARK: - Hashable Tests

    @MainActor
    func testBottleHashableConsistency() {
        let bottle1 = Bottle(bottleUrl: bottleURL)
        let bottle2 = Bottle(bottleUrl: bottleURL)

        XCTAssertEqual(bottle1.hashValue, bottle2.hashValue)
    }

    @MainActor
    func testBottleHashableInSet() {
        let otherURL = tempDir.appending(path: "OtherBottle")
        try? FileManager.default.createDirectory(
            at: otherURL.appending(path: "drive_c"),
            withIntermediateDirectories: true
        )

        let bottle1 = Bottle(bottleUrl: bottleURL)
        let bottle2 = Bottle(bottleUrl: otherURL)

        var bottleSet: Set<Bottle> = []
        bottleSet.insert(bottle1)
        bottleSet.insert(bottle2)

        XCTAssertEqual(bottleSet.count, 2)
        XCTAssertTrue(bottleSet.contains(bottle1))
        XCTAssertTrue(bottleSet.contains(bottle2))
    }

    // MARK: - Comparable Tests

    @MainActor
    func testBottleComparableByName() {
        let bottle1URL = tempDir.appending(path: "BottleA")
        let bottle2URL = tempDir.appending(path: "BottleZ")
        try? FileManager.default.createDirectory(
            at: bottle1URL.appending(path: "drive_c"),
            withIntermediateDirectories: true
        )
        try? FileManager.default.createDirectory(
            at: bottle2URL.appending(path: "drive_c"),
            withIntermediateDirectories: true
        )

        let bottle1 = Bottle(bottleUrl: bottle1URL)
        bottle1.settings.name = "Alpha"

        let bottle2 = Bottle(bottleUrl: bottle2URL)
        bottle2.settings.name = "Zulu"

        XCTAssertTrue(bottle1 < bottle2)
        XCTAssertFalse(bottle2 < bottle1)
    }

    @MainActor
    func testBottleComparableCaseInsensitive() {
        let bottle1URL = tempDir.appending(path: "Bottle1")
        let bottle2URL = tempDir.appending(path: "Bottle2")
        try? FileManager.default.createDirectory(
            at: bottle1URL.appending(path: "drive_c"),
            withIntermediateDirectories: true
        )
        try? FileManager.default.createDirectory(
            at: bottle2URL.appending(path: "drive_c"),
            withIntermediateDirectories: true
        )

        let bottle1 = Bottle(bottleUrl: bottle1URL)
        bottle1.settings.name = "alpha"

        let bottle2 = Bottle(bottleUrl: bottle2URL)
        bottle2.settings.name = "BETA"

        XCTAssertTrue(bottle1 < bottle2)
    }

    @MainActor
    func testBottleSortingByName() {
        let urls = (0 ..< 3).map { tempDir.appending(path: "Bottle\($0)") }
        for url in urls {
            try? FileManager.default.createDirectory(
                at: url.appending(path: "drive_c"),
                withIntermediateDirectories: true
            )
        }

        let bottle1 = Bottle(bottleUrl: urls[0])
        bottle1.settings.name = "Charlie"

        let bottle2 = Bottle(bottleUrl: urls[1])
        bottle2.settings.name = "Alpha"

        let bottle3 = Bottle(bottleUrl: urls[2])
        bottle3.settings.name = "Bravo"

        let bottles = [bottle1, bottle2, bottle3].sorted()

        XCTAssertEqual(bottles[0].settings.name, "Alpha")
        XCTAssertEqual(bottles[1].settings.name, "Bravo")
        XCTAssertEqual(bottles[2].settings.name, "Charlie")
    }

    // MARK: - Programs Array Tests

    @MainActor
    func testBottleProgramsInitiallyEmpty() {
        let bottle = Bottle(bottleUrl: bottleURL)

        XCTAssertTrue(bottle.programs.isEmpty)
    }

    // MARK: - Pinned Programs Tests

    @MainActor
    func testBottlePinnedProgramsInitiallyEmpty() {
        let bottle = Bottle(bottleUrl: bottleURL)

        XCTAssertTrue(bottle.pinnedPrograms.isEmpty)
    }

    @MainActor
    func testBottlePinnedProgramsFiltersNonexistentPrograms() {
        let bottle = Bottle(bottleUrl: bottleURL)

        // Add a pin for a non-existent program
        let fakeURL = bottleURL.appending(path: "drive_c/nonexistent.exe")
        bottle.settings.pins.append(PinnedProgram(name: "Fake", url: fakeURL))

        // pinnedPrograms should be empty since the program doesn't exist
        XCTAssertTrue(bottle.pinnedPrograms.isEmpty)
    }

    // MARK: - Settings Persistence Tests

    @MainActor
    func testBottleSettingsArePersisted() {
        let bottle = Bottle(bottleUrl: bottleURL)
        bottle.settings.name = "Test Bottle Name"

        // Create a new bottle instance from the same URL
        let reloadedBottle = Bottle(bottleUrl: bottleURL)

        XCTAssertEqual(reloadedBottle.settings.name, "Test Bottle Name")
    }

    @MainActor
    func testBottleSaveBottleSettingsMethod() {
        let bottle = Bottle(bottleUrl: bottleURL)
        bottle.settings.name = "Manual Save Test"

        // Call the public save method
        bottle.saveBottleSettings()

        // Verify by reloading
        let reloadedBottle = Bottle(bottleUrl: bottleURL)
        XCTAssertEqual(reloadedBottle.settings.name, "Manual Save Test")
    }
}

// MARK: - Program Sequence Extension Tests

final class ProgramSequenceExtensionTests: XCTestCase {
    var tempDir: URL!
    var bottleURL: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appending(path: "progseq_\(UUID().uuidString)")
        bottleURL = tempDir.appending(path: "TestBottle")

        let driveCURL = bottleURL.appending(path: "drive_c")
        try? FileManager.default.createDirectory(at: driveCURL, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    @MainActor
    func testPinnedFilterReturnsOnlyPinnedPrograms() {
        let bottle = Bottle(bottleUrl: bottleURL)

        let program1URL = bottleURL.appending(path: "drive_c/program1.exe")
        let program2URL = bottleURL.appending(path: "drive_c/program2.exe")
        try? Data("fake".utf8).write(to: program1URL)
        try? Data("fake".utf8).write(to: program2URL)

        let program1 = Program(url: program1URL, bottle: bottle)
        let program2 = Program(url: program2URL, bottle: bottle)

        program1.pinned = true
        program2.pinned = false

        let programs = [program1, program2]
        let pinned = programs.pinned

        XCTAssertEqual(pinned.count, 1)
        XCTAssertTrue(pinned.contains(program1))
        XCTAssertFalse(pinned.contains(program2))
    }

    @MainActor
    func testUnpinnedFilterReturnsOnlyUnpinnedPrograms() {
        let bottle = Bottle(bottleUrl: bottleURL)

        let program1URL = bottleURL.appending(path: "drive_c/program1.exe")
        let program2URL = bottleURL.appending(path: "drive_c/program2.exe")
        try? Data("fake".utf8).write(to: program1URL)
        try? Data("fake".utf8).write(to: program2URL)

        let program1 = Program(url: program1URL, bottle: bottle)
        let program2 = Program(url: program2URL, bottle: bottle)

        program1.pinned = true
        program2.pinned = false

        let programs = [program1, program2]
        let unpinned = programs.unpinned

        XCTAssertEqual(unpinned.count, 1)
        XCTAssertFalse(unpinned.contains(program1))
        XCTAssertTrue(unpinned.contains(program2))
    }

    @MainActor
    func testPinnedAndUnpinnedAreComplementary() {
        let bottle = Bottle(bottleUrl: bottleURL)

        let urls = (0 ..< 5).map { bottleURL.appending(path: "drive_c/program\($0).exe") }
        for url in urls {
            try? Data("fake".utf8).write(to: url)
        }

        let programs = urls.map { Program(url: $0, bottle: bottle) }

        // Pin some programs
        programs[0].pinned = true
        programs[2].pinned = true
        programs[4].pinned = true

        let pinned = programs.pinned
        let unpinned = programs.unpinned

        XCTAssertEqual(pinned.count, 3)
        XCTAssertEqual(unpinned.count, 2)
        XCTAssertEqual(pinned.count + unpinned.count, programs.count)
    }

    @MainActor
    func testEmptyArrayReturnsEmptyPinnedAndUnpinned() {
        let programs: [Program] = []

        XCTAssertTrue(programs.pinned.isEmpty)
        XCTAssertTrue(programs.unpinned.isEmpty)
    }
}
