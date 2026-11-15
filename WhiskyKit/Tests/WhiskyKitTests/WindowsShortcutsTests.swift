//
//  WindowsShortcutsTests.swift
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

@Suite("Windows Shortcuts Tests")
struct WindowsShortcutsTests {
    /// A throwaway `drive_c` with the folders a fresh bottle has.
    private func makeDriveC() throws -> URL {
        let driveC = FileManager.default.temporaryDirectory
            .appending(path: "WindowsShortcutsTests-\(UUID().uuidString)")
            .appending(path: "drive_c")
        for folder in WindowsShortcuts.folders(driveC: driveC, wineUsername: "crossover") {
            try FileManager.default.createDirectory(at: folder.url, withIntermediateDirectories: true)
        }
        return driveC
    }

    private func touch(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0x4C, 0x00, 0x00, 0x00]).write(to: url)
    }

    // MARK: - Folders

    @Test("Start Menu folders are searched recursively, Desktop folders are not")
    func folderLayout() {
        let driveC = URL(fileURLWithPath: "/tmp/bottle/drive_c")
        let folders = WindowsShortcuts.folders(driveC: driveC, wineUsername: "crossover")

        #expect(folders.map { $0.url.path(percentEncoded: false) } == [
            "/tmp/bottle/drive_c/ProgramData/Microsoft/Windows/Start Menu",
            "/tmp/bottle/drive_c/users/crossover/AppData/Roaming/Microsoft/Windows/Start Menu",
            "/tmp/bottle/drive_c/users/crossover/Desktop",
            "/tmp/bottle/drive_c/users/Public/Desktop"
        ])
        #expect(folders.map(\.recursive) == [true, true, false, false])
    }

    // MARK: - Finding shortcuts

    @Test("Finds .lnk files in every folder, in nested Start Menu folders and with any case")
    func findsShortcuts() throws {
        let driveC = try makeDriveC()
        defer { try? FileManager.default.removeItem(at: driveC.deletingLastPathComponent()) }
        let folders = WindowsShortcuts.folders(driveC: driveC, wineUsername: "crossover")

        try touch(folders[1].url.appending(path: "Programs/Magic Wings/Magic Wings.lnk"))
        try touch(folders[0].url.appending(path: "Programs/Tool.LNK"))
        try touch(folders[2].url.appending(path: "Game.lnk"))
        try touch(folders[3].url.appending(path: "Shared Game.lnk"))

        let found = WindowsShortcuts.findShortcuts(driveC: driveC, wineUsername: "crossover")

        #expect(found.map { $0.deletingPathExtension().lastPathComponent } == [
            "Tool", "Magic Wings", "Game", "Shared Game"
        ])
    }

    @Test("Skips other files, hidden files and shortcuts nested under the Desktop")
    func skipsNonShortcuts() throws {
        let driveC = try makeDriveC()
        defer { try? FileManager.default.removeItem(at: driveC.deletingLastPathComponent()) }
        let desktop = WindowsShortcuts.folders(driveC: driveC, wineUsername: "crossover")[2].url

        try touch(desktop.appending(path: "notes.txt"))
        try touch(desktop.appending(path: "Site.url"))
        try touch(desktop.appending(path: ".hidden.lnk"))
        try touch(desktop.appending(path: "Folder/Nested.lnk"))

        #expect(WindowsShortcuts.findShortcuts(driveC: driveC, wineUsername: "crossover").isEmpty)
    }

    @Test("A Desktop that links outside the bottle is not read")
    func skipsLinkedDesktop() throws {
        let driveC = try makeDriveC()
        let root = driveC.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: root) }
        let elsewhere = root.appending(path: "MacDesktop")
        try touch(elsewhere.appending(path: "Personal.lnk"))
        let desktop = WindowsShortcuts.folders(driveC: driveC, wineUsername: "crossover")[2].url
        try FileManager.default.removeItem(at: desktop)
        try FileManager.default.createSymbolicLink(at: desktop, withDestinationURL: elsewhere)

        #expect(WindowsShortcuts.findShortcuts(driveC: driveC, wineUsername: "crossover").isEmpty)
    }

    @Test("A bottle without shortcut folders yields nothing")
    func missingFolders() {
        let driveC = FileManager.default.temporaryDirectory.appending(path: "missing-\(UUID().uuidString)")
        #expect(WindowsShortcuts.findShortcuts(driveC: driveC, wineUsername: "crossover").isEmpty)
    }

    // MARK: - Program shortcuts

    @Test("Shortcuts to installed executables are programs")
    func programShortcuts() {
        let launcher = "/b/drive_c/users/crossover/AppData/Local/MagicWings/MagicWings.Launcher.exe"
        #expect(WindowsShortcuts.isProgramShortcut(name: "Magic Wings", targetPath: launcher))
        #expect(WindowsShortcuts.isProgramShortcut(name: "Game", targetPath: "/b/drive_c/Program Files/Game/GAME.EXE"))
        #expect(WindowsShortcuts.isProgramShortcut(name: "Helper Tool", targetPath: "/b/drive_c/Games/helper.exe"))
    }

    @Test("Uninstallers, documents, web links and system programs are not")
    func nonProgramShortcuts() {
        let game = "/b/drive_c/Program Files/Game"
        #expect(!WindowsShortcuts.isProgramShortcut(name: "Uninstall Game", targetPath: "\(game)/uninstall.exe"))
        #expect(!WindowsShortcuts.isProgramShortcut(name: "Remove", targetPath: "\(game)/unins000.exe"))
        #expect(!WindowsShortcuts.isProgramShortcut(name: "Desinstalar Jogo", targetPath: "\(game)/game.exe"))
        #expect(!WindowsShortcuts.isProgramShortcut(name: "Read Me", targetPath: "\(game)/game.exe"))
        #expect(!WindowsShortcuts.isProgramShortcut(name: "Game Manual", targetPath: "\(game)/manual.pdf"))
        #expect(!WindowsShortcuts.isProgramShortcut(name: "Game Website", targetPath: "\(game)/site.url"))
        #expect(!WindowsShortcuts.isProgramShortcut(name: "Notepad", targetPath: "/b/drive_c/windows/notepad.exe"))
        #expect(!WindowsShortcuts.isProgramShortcut(name: "Discord", targetPath: "/b/drive_c/Discord/Update.exe"))
    }

    @Test("Helpers and crash reporters the program list hides are not programs")
    func noiseExecutableShortcuts() {
        let steam = "/b/drive_c/Program Files (x86)/Steam/bin/cef/cef.win7x64/steamwebhelper.exe"
        #expect(!WindowsShortcuts.isProgramShortcut(name: "Steam Web Helper", targetPath: steam))
        let reporter = "/b/drive_c/Game/CrashReporter.exe"
        #expect(!WindowsShortcuts.isProgramShortcut(name: "Crash Reporter", targetPath: reporter))
    }

    // MARK: - Handled shortcuts record

    @Test("Keeping only present shortcuts forgets the removed ones")
    func recordKeepsPresentShortcuts() {
        let driveC = URL(fileURLWithPath: "/tmp/bottle/drive_c")
        let kept = driveC.appending(path: "users/Public/Desktop/Game.lnk")
        let removed = driveC.appending(path: "users/crossover/Desktop/Old.lnk")
        var record = HandledShortcuts()
        record.insert(kept, driveC: driveC)
        record.insert(removed, driveC: driveC)

        let pruned = record.keeping([driveC.appending(path: "users/Public/Desktop/GAME.LNK")], driveC: driveC)

        #expect(pruned.contains(kept, driveC: driveC))
        #expect(!pruned.contains(removed, driveC: driveC))
    }

    @Test("The record matches shortcuts case-insensitively, relative to drive_c")
    func recordKeys() {
        let driveC = URL(fileURLWithPath: "/tmp/bottle/drive_c")
        let link = driveC.appending(path: "users/crossover/Desktop/Game.lnk")
        var record = HandledShortcuts()
        record.insert(link, driveC: driveC)

        #expect(HandledShortcuts.key(for: link, driveC: driveC) == "users/crossover/desktop/game.lnk")
        #expect(record.contains(driveC.appending(path: "Users/CrossOver/Desktop/GAME.lnk"), driveC: driveC))
        #expect(!record.contains(driveC.appending(path: "users/crossover/Desktop/Other.lnk"), driveC: driveC))
    }

    @Test("The record keeps its keys when the bottle moves")
    func recordAfterMove() {
        let link = "users/crossover/Desktop/Game.lnk"
        let old = URL(fileURLWithPath: "/old/bottle/drive_c")
        var record = HandledShortcuts()
        record.insert(old.appending(path: link), driveC: old)

        let moved = URL(fileURLWithPath: "/new/place/bottle/drive_c")
        #expect(record.contains(moved.appending(path: link), driveC: moved))
    }

    @Test("The record round-trips through the bottle folder, and an unreadable one starts over")
    func recordPersistence() throws {
        let bottle = FileManager.default.temporaryDirectory.appending(path: "handled-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: bottle, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bottle) }
        let driveC = bottle.appending(path: "drive_c")

        #expect(HandledShortcuts.load(from: bottle) == HandledShortcuts())

        var record = HandledShortcuts()
        record.insert(driveC.appending(path: "users/Public/Desktop/Game.lnk"), driveC: driveC)
        try record.save(to: bottle)
        #expect(HandledShortcuts.load(from: bottle) == record)

        try Data("not a plist".utf8).write(to: bottle.appending(path: HandledShortcuts.fileName))
        #expect(HandledShortcuts.load(from: bottle) == HandledShortcuts())
    }
}
