//
//  StartMenuShortcutSyncTests.swift
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

@MainActor
final class StartMenuShortcutSyncTests: XCTestCase {
    private var tempDir: URL!
    private var bottleURL: URL!
    private var startMenu: URL!
    private var desktop: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appending(path: "shortcut_sync_\(UUID().uuidString)")
        bottleURL = tempDir.appending(path: "Bottle")
        let folders = WindowsShortcuts.folders(driveC: bottleURL.appending(path: "drive_c"), wineUsername: "crossover")
        for folder in folders {
            try FileManager.default.createDirectory(at: folder.url, withIntermediateDirectories: true)
        }
        startMenu = folders[0].url.appending(path: "Programs")
        desktop = folders[2].url
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    // MARK: - Fixtures

    /// Writes a minimal `.lnk` whose LinkInfo names `windowsPath` as its
    /// ANSI local base path, the layout ``ShellLinkHeader`` reads.
    private func writeShortcut(_ link: URL, to windowsPath: String) throws {
        func le32(_ value: UInt32) -> [UInt8] {
            withUnsafeBytes(of: value.littleEndian) { Array($0) }
        }
        var data = Data(le32(0x4C))
        data.append(Data(count: 16)) // LinkCLSID
        data.append(contentsOf: le32(1 << 1)) // HasLinkInfo
        data.append(Data(count: 0x4C - data.count))

        let path = Array(windowsPath.utf8) + [0]
        let headerSize: UInt32 = 0x1C
        data.append(contentsOf: le32(headerSize + UInt32(path.count))) // LinkInfoSize
        data.append(contentsOf: le32(headerSize))
        data.append(contentsOf: le32(1)) // VolumeIDAndLocalBasePath
        data.append(contentsOf: le32(0)) // VolumeIDOffset
        data.append(contentsOf: le32(headerSize)) // LocalBasePathOffset
        data.append(contentsOf: le32(0)) // CommonNetworkRelativeLinkOffset
        data.append(contentsOf: le32(0)) // CommonPathSuffixOffset
        data.append(contentsOf: path)

        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: link)
    }

    /// Creates an executable at `relativePath` under `drive_c`.
    @discardableResult
    private func makeExe(_ relativePath: String) throws -> URL {
        let url = bottleURL.appending(path: "drive_c").appending(path: relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("MZ".utf8).write(to: url)
        return url
    }

    private func sync(_ bottle: Bottle) -> Bool {
        StartMenuShortcutSync.sync(bottle: bottle, wineUsername: "crossover")
    }

    // MARK: - Tests

    func testPinsScannedProgramAndKeepsTheShortcut() throws {
        let exe = try makeExe("Program Files/Game/game.exe")
        let link = startMenu.appending(path: "Game.lnk")
        try writeShortcut(link, to: #"C:\Program Files\Game\game.exe"#)
        let bottle = Bottle(bottleUrl: bottleURL)
        bottle.programs = [Program(url: exe, bottle: bottle)]

        XCTAssertFalse(sync(bottle))

        XCTAssertEqual(bottle.settings.pins.compactMap(\.url), [exe])
        XCTAssertTrue(bottle.programs[0].pinned)
        XCTAssertTrue(FileManager.default.fileExists(atPath: link.path(percentEncoded: false)))
        XCTAssertTrue(HandledShortcuts.load(from: bottleURL).contains(
            link,
            driveC: bottleURL.appending(path: "drive_c")
        ))
    }

    func testPinsTargetOutsideTheScanUnderTheShortcutName() throws {
        let exe = try makeExe("Games/Racer/racer_x64.exe")
        try writeShortcut(desktop.appending(path: "Racer.lnk"), to: #"C:\Games\Racer\racer_x64.exe"#)
        let bottle = Bottle(bottleUrl: bottleURL)

        XCTAssertTrue(sync(bottle))

        XCTAssertEqual(bottle.settings.pins.map(\.name), ["Racer"])
        XCTAssertEqual(
            bottle.settings.pins.compactMap { $0.url?.path(percentEncoded: false) },
            [exe.path(percentEncoded: false)]
        )
    }

    func testShortcutIsRetriedUntilItsTargetExists() throws {
        try writeShortcut(startMenu.appending(path: "Tool.lnk"), to: #"C:\Tools\tool.exe"#)
        let bottle = Bottle(bottleUrl: bottleURL)

        XCTAssertFalse(sync(bottle))
        XCTAssertTrue(bottle.settings.pins.isEmpty)
        XCTAssertEqual(HandledShortcuts.load(from: bottleURL), HandledShortcuts())

        try makeExe("Tools/tool.exe")
        XCTAssertTrue(sync(bottle))
        XCTAssertEqual(bottle.settings.pins.map(\.name), ["Tool"])
    }

    func testUnreadableShortcutIsNotRecorded() throws {
        // A shortcut the installer has only started writing.
        let link = startMenu.appending(path: "Broken.lnk")
        try FileManager.default.createDirectory(at: startMenu, withIntermediateDirectories: true)
        try Data([0x4C, 0x00]).write(to: link)
        let bottle = Bottle(bottleUrl: bottleURL)

        XCTAssertFalse(sync(bottle))
        XCTAssertEqual(HandledShortcuts.load(from: bottleURL), HandledShortcuts())
    }

    func testHandledShortcutDoesNotPinAgainAfterAnUnpin() throws {
        try makeExe("Games/Racer/racer.exe")
        try writeShortcut(desktop.appending(path: "Racer.lnk"), to: #"C:\Games\Racer\racer.exe"#)
        let bottle = Bottle(bottleUrl: bottleURL)
        XCTAssertTrue(sync(bottle))

        // Even without the unpin record, the shortcut is not handled twice.
        bottle.settings.pins = []
        XCTAssertFalse(sync(bottle))
        XCTAssertTrue(bottle.settings.pins.isEmpty)
    }

    func testNewShortcutLeavesAnUnpinnedProgramAlone() throws {
        let exe = try makeExe("Games/Racer/racer.exe")
        let bottle = Bottle(bottleUrl: bottleURL)
        bottle.settings.unpinnedPrograms = [exe]
        // An updater rewrote the shortcut under a new name.
        try writeShortcut(startMenu.appending(path: "Racer 2.lnk"), to: #"C:\Games\Racer\racer.exe"#)

        XCTAssertFalse(sync(bottle))
        XCTAssertTrue(bottle.settings.pins.isEmpty)
    }

    func testUninstallerIsRecordedButNotPinned() throws {
        try makeExe("Program Files/Game/unins000.exe")
        let link = startMenu.appending(path: "Uninstall Game.lnk")
        try writeShortcut(link, to: #"C:\Program Files\Game\unins000.exe"#)
        let bottle = Bottle(bottleUrl: bottleURL)

        XCTAssertFalse(sync(bottle))
        XCTAssertTrue(bottle.settings.pins.isEmpty)
        XCTAssertTrue(HandledShortcuts.load(from: bottleURL).contains(
            link,
            driveC: bottleURL.appending(path: "drive_c")
        ))
    }

    func testTwoShortcutsToOneProgramPinItOnce() throws {
        try makeExe("Games/Racer/racer.exe")
        try writeShortcut(startMenu.appending(path: "Racer.lnk"), to: #"C:\Games\Racer\racer.exe"#)
        try writeShortcut(desktop.appending(path: "Racer.lnk"), to: #"C:\GAMES\Racer\RACER.EXE"#)
        let bottle = Bottle(bottleUrl: bottleURL)

        XCTAssertTrue(sync(bottle))
        XCTAssertEqual(bottle.settings.pins.count, 1)
    }
}
