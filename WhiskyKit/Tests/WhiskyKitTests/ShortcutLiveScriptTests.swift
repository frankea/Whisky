//
//  ShortcutLiveScriptTests.swift
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

@Suite("Shortcut Live Script Tests")
struct ShortcutLiveScriptTests {
    @Test("Steam target launches by App ID")
    func steamScript() {
        let script = ShortcutCreator.liveLaunchScript(for: .steamGame(appId: 4_576_510))

        #expect(script.contains(#"exec "$WHISKY_CMD" launch 4576510"#))
        #expect(script.contains("mdfind"))
    }

    @Test("Program target quotes bottle name and Windows path")
    func programScript() {
        let script = ShortcutCreator.liveLaunchScript(
            for: .program(bottleName: "Steam dx11", windowsPath: #"C:\Games\Some Game\game.exe"#)
        )

        #expect(script.contains(#"exec "$WHISKY_CMD" run 'Steam dx11' 'C:\Games\Some Game\game.exe'"#))
    }

    @Test("Hostile names survive shell quoting")
    func hostileQuoting() {
        let quoted = ShortcutCreator.shellQuoted("Bo'ttle; rm -rf $HOME")

        #expect(quoted == #"'Bo'\''ttle; rm -rf $HOME'"#)
    }

    @Test("AppleScript quoting escapes backslashes, quotes and newlines")
    func appleScriptQuoting() {
        let quoted = ShortcutCreator.appleScriptQuoted("a \\ b \"c\"\nd")

        #expect(quoted == #""a \\ b \"c\"\nd""#)
    }

    @Test("Translated alert text with ' \" and \\ keeps the script valid")
    func translatedAlertQuoting() throws {
        let title = #"L'app "Whisky" \ introuvable"#
        let message = #"Installez Whisky pour l'utiliser; $HOME `id` \"#
        let script = ShortcutCreator.liveLaunchScript(
            for: .steamGame(appId: 4_576_510), notFoundTitle: title, notFoundMessage: message
        )

        // The whole script parses as sh.
        #expect(try runProcess("/bin/sh", ["-n", "-c", script]).status == 0)

        // The shell hands osascript exactly the AppleScript source we built.
        let line = try #require(script.split(separator: "\n").first { $0.contains("osascript -e ") })
        let echo = line.replacingOccurrences(of: "osascript -e ", with: "printf '%s' ")
        let printed = try runProcess("/bin/sh", ["-c", echo])
        let expected = "display alert \(ShortcutCreator.appleScriptQuoted(title))"
            + " message \(ShortcutCreator.appleScriptQuoted(message))"
        #expect(printed.status == 0)
        #expect(printed.output == expected)

        // And that source compiles as AppleScript (compiled only, never run).
        let compiled = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).scpt")
        defer { try? FileManager.default.removeItem(at: compiled) }
        #expect(try runProcess("/usr/bin/osacompile", ["-o", compiled.path, "-e", printed.output]).status == 0)
    }

    private func runProcess(_ executable: String, _ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(bytes: data, encoding: .utf8) ?? "")
    }

    @Test("Windows paths map from drive_c and reject outsiders")
    func windowsPathMapping() {
        let bottle = URL(fileURLWithPath: "/tmp/bottles/b")

        let inside = ShortcutCreator.windowsPath(
            for: URL(fileURLWithPath: "/tmp/bottles/b/drive_c/Games/A Game/run.exe"),
            bottleURL: bottle
        )
        #expect(inside == #"C:\Games\A Game\run.exe"#)

        let outside = ShortcutCreator.windowsPath(
            for: URL(fileURLWithPath: "/tmp/elsewhere/run.exe"),
            bottleURL: bottle
        )
        #expect(outside == nil)
    }

    @Test("Live target picks Steam games by install directory")
    @MainActor func liveTargetSteamGame() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let steamRoot = tempDir.appending(path: "drive_c")
            .appending(path: "Program Files (x86)").appending(path: "Steam")
        let steamApps = steamRoot.appending(path: "steamapps")
        let installDir = steamApps.appending(path: "common").appending(path: "Casualties Unknown Demo")
        try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)
        try Data().write(to: steamRoot.appending(path: "steam.exe"))
        let acf = """
        "AppState"
        {
            "appid"        "4576510"
            "name"        "Casualties: Unknown Demo"
            "installdir"        "Casualties Unknown Demo"
            "StateFlags"        "4"
        }
        """
        try Data(acf.utf8).write(to: steamApps.appending(path: "appmanifest_4576510.acf"))
        let exe = installDir.appending(path: "CasualtiesUnknown.exe")
        try Data().write(to: exe)

        let bottle = Bottle(bottleUrl: tempDir, inFlight: false, isAvailable: true)
        let target = ShortcutCreator.liveTarget(for: exe, bottle: bottle)

        #expect(target == .steamGame(appId: 4_576_510))
    }

    @Test("Live target falls back to bottle name and Windows path")
    @MainActor func liveTargetPlainProgram() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let exe = tempDir.appending(path: "drive_c").appending(path: "Games").appending(path: "game.exe")
        try FileManager.default.createDirectory(
            at: exe.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data().write(to: exe)

        let bottle = Bottle(bottleUrl: tempDir, inFlight: false, isAvailable: true)
        let target = ShortcutCreator.liveTarget(for: exe, bottle: bottle)

        #expect(target == .program(
            bottleName: bottle.settings.name, windowsPath: #"C:\Games\game.exe"#
        ))
    }
}
