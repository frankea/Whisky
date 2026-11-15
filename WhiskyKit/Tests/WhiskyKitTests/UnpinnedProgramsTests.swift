//
//  UnpinnedProgramsTests.swift
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

// MARK: - BottleSettings unpin records

final class UnpinnedProgramsSettingsTests: XCTestCase {
    private let game = URL(filePath: "/Bottles/A/drive_c/Program Files/Game/game.exe")
    private let tool = URL(filePath: "/Bottles/A/drive_c/Program Files/Tool/tool.exe")

    func testMissingKeyDecodesAsEmpty() throws {
        // A Metadata.plist written before the field existed.
        var legacy = BottleSettings()
        legacy.pins = [PinnedProgram(name: "Game", url: game)]
        let data = try PropertyListEncoder().encode(legacy)
        guard var plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              var info = plist["info"] as? [String: Any]
        else {
            XCTFail("Settings did not encode as a dictionary with an info section")
            return
        }
        info.removeValue(forKey: "unpinnedPrograms")
        plist["info"] = info
        let stripped = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)

        let decoded = try PropertyListDecoder().decode(BottleSettings.self, from: stripped)

        XCTAssertEqual(decoded.unpinnedPrograms, [])
        XCTAssertEqual(decoded.pins.count, 1)
    }

    func testUnpinRecordsRoundTrip() throws {
        var settings = BottleSettings()
        settings.unpinnedPrograms = [game]

        let data = try PropertyListEncoder().encode(settings)
        let decoded = try PropertyListDecoder().decode(BottleSettings.self, from: data)

        XCTAssertEqual(decoded.unpinnedPrograms, [game])
    }

    func testStartMenuPinsToAddSkipsPinnedAndUnpinned() {
        var settings = BottleSettings()
        settings.pins = [PinnedProgram(name: "Game", url: game)]
        let other = URL(filePath: "/Bottles/A/drive_c/Program Files/Other/other.exe")
        settings.unpinnedPrograms = [tool]

        XCTAssertEqual(settings.startMenuPinsToAdd(candidates: [game, tool, other]), [other])
    }

    func testStartMenuPinsToAddSkipsBlocklistedPrograms() {
        var settings = BottleSettings()
        settings.blocklist = [tool]
        let upperTool = URL(filePath: "/Bottles/A/drive_c/PROGRAM FILES/Tool/TOOL.EXE")

        XCTAssertEqual(settings.startMenuPinsToAdd(candidates: [upperTool, game]), [game])
    }

    func testStartMenuPinsToAddComparesCaseInsensitivelyAndDropsDuplicates() {
        var settings = BottleSettings()
        settings.unpinnedPrograms = [tool]
        let upperTool = URL(filePath: "/Bottles/A/drive_c/PROGRAM FILES/Tool/TOOL.EXE")
        let upperGame = URL(filePath: "/Bottles/A/drive_c/Program Files/Game/GAME.exe")

        XCTAssertEqual(settings.startMenuPinsToAdd(candidates: [upperTool, game, upperGame]), [game])
    }

    func testUnpinRemovesPinAndRecordsOnce() {
        var settings = BottleSettings()
        settings.pins = [PinnedProgram(name: "Game", url: game)]

        settings.unpin(game)
        settings.unpin(game)

        XCTAssertTrue(settings.pins.isEmpty)
        XCTAssertEqual(settings.unpinnedPrograms, [game])
    }

    func testClearUnpinForgetsEveryCaseVariant() {
        var settings = BottleSettings()
        settings.unpinnedPrograms = [game, tool]

        settings.clearUnpin(URL(filePath: "/Bottles/A/drive_c/Program Files/Game/GAME.EXE"))

        XCTAssertEqual(settings.unpinnedPrograms, [tool])
    }

    func testPruneDropsMissingFilesAndDuplicates() {
        var settings = BottleSettings()
        settings.unpinnedPrograms = [game, tool, game]
        let existing: Set<String> = [game.path(percentEncoded: false)]

        let pruned = settings.prunedUnpinnedPrograms { existing.contains($0) }

        XCTAssertEqual(pruned, [game])
    }

    func testRewriteAndRestoreCoverUnpinRecords() {
        var settings = BottleSettings()
        settings.pins = [PinnedProgram(name: "Game", url: game)]
        settings.blocklist = [tool]
        settings.unpinnedPrograms = [game]
        let snapshot = settings

        settings.rewriteProgramURLs(from: URL(filePath: "/Bottles/A"), to: URL(filePath: "/Bottles/B"))

        let moved = "/Bottles/B/drive_c/Program Files/Game/game.exe"
        XCTAssertEqual(settings.pins.first?.url?.path(percentEncoded: false), moved)
        XCTAssertEqual(
            settings.blocklist.map { $0.path(percentEncoded: false) },
            ["/Bottles/B/drive_c/Program Files/Tool/tool.exe"]
        )
        XCTAssertEqual(settings.unpinnedPrograms.map { $0.path(percentEncoded: false) }, [moved])

        settings.restoreProgramURLs(from: snapshot)

        XCTAssertEqual(settings.pins, snapshot.pins)
        XCTAssertEqual(settings.blocklist, snapshot.blocklist)
        XCTAssertEqual(settings.unpinnedPrograms, snapshot.unpinnedPrograms)
    }
}

// MARK: - Program pin setter and bottle integration

final class UnpinnedProgramsBottleTests: BottleOperationsTestCase {
    @MainActor
    func testUnpinningProgramRecordsTheDecision() {
        let bottle = Bottle(bottleUrl: bottleURL)
        let program = Program(url: exeURL, bottle: bottle)
        program.pinned = true

        program.pinned = false

        XCTAssertFalse(bottle.settings.pins.contains { $0.url == exeURL })
        XCTAssertEqual(bottle.settings.unpinnedPrograms, [exeURL])
        XCTAssertEqual(bottle.settings.startMenuPinsToAdd(candidates: [exeURL]), [])
    }

    @MainActor
    func testPinningAgainClearsTheRecordEvenWhenAlreadyPinned() {
        let bottle = Bottle(bottleUrl: bottleURL)
        // Pinned by hand while an older unpin record is still present.
        bottle.settings.pins = [PinnedProgram(name: "Game", url: exeURL)]
        bottle.settings.unpinnedPrograms = [exeURL]
        let program = Program(url: exeURL, bottle: bottle)
        XCTAssertTrue(program.pinned)

        program.pinned = true

        XCTAssertEqual(bottle.settings.unpinnedPrograms, [])
        XCTAssertEqual(bottle.settings.pins.filter { $0.url == exeURL }.count, 1)
    }

    @MainActor
    func testBottleLoadPrunesRecordsForRemovedPrograms() throws {
        let gone = bottleURL.appending(path: "drive_c/Program Files/Game/removed.exe")
        let bottle = Bottle(bottleUrl: bottleURL)
        bottle.settings.unpinnedPrograms = [exeURL, gone]

        let reloaded = Bottle(bottleUrl: bottleURL)

        XCTAssertEqual(reloaded.settings.unpinnedPrograms, [exeURL])
        XCTAssertEqual(try persistedSettings(at: bottleURL).unpinnedPrograms, [exeURL])
    }

    @MainActor
    func testMoveRewritesUnpinRecords() throws {
        let registry = RegistryFixture()
        let bottle = makeRegisteredBottle(in: registry)
        bottle.settings.unpinnedPrograms = [exeURL]
        let destination = tempDir.appending(path: "Moved")

        try BottleOperations.move(bottleAt: bottleURL, to: destination, registry: registry)

        XCTAssertEqual(
            try persistedSettings(at: destination).unpinnedPrograms.map { $0.path(percentEncoded: false) },
            [destination.appending(path: "drive_c/Program Files/Game/game.exe").path(percentEncoded: false)]
        )
    }

    @MainActor
    func testFailedMoveRestoresUnpinRecords() throws {
        let registry = RegistryFixture()
        let bottle = makeRegisteredBottle(in: registry)
        bottle.settings.unpinnedPrograms = [exeURL]

        XCTAssertThrowsError(
            try BottleOperations.move(
                bottleAt: bottleURL, to: tempDir.appending(path: "missing/Moved"), registry: registry
            )
        )

        XCTAssertEqual(bottle.settings.unpinnedPrograms, [exeURL])
        XCTAssertEqual(try persistedSettings(at: bottleURL).unpinnedPrograms, [exeURL])
    }
}
