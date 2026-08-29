//
//  ShellQuotingTests.swift
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

@Suite("Shell quoting")
struct ShellQuotingTests {
    /// The values an attacker-named bottle directory could carry into a
    /// terminal command, plus the ordinary ones.
    private static let hostile: [String] = [
        "Games",
        "My Games",
        "Bottle $(touch /tmp/whisky-quoting-pwned)",
        "Bottle `touch /tmp/whisky-quoting-pwned`",
        "It's a bottle",
        "\"quoted\" name",
        "back\\slash",
        "semi; rm -rf ~",
        "pipe | cat",
        "amp && echo hi",
        "hash # not a comment",
        "tilde ~/home",
        "star * glob",
        "newline\nin name",
        "unicode Ångström 游戏"
    ]

    /// Runs `printf %s <quoted>` through the real shell and compares.
    private func shellReadsBack(_ value: String) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", "printf %s " + ShellQuoting.quoted(value)]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    @Test("The shell reads every quoted value back verbatim", arguments: hostile)
    func roundTrips(value: String) throws {
        #expect(try shellReadsBack(value) == value)
    }

    @Test("Command substitution inside a quoted value never runs")
    func substitutionIsInert() throws {
        let marker = FileManager.default.temporaryDirectory
            .appending(path: "whisky-quoting-\(UUID().uuidString)")
        let value = "Bottle $(touch \(marker.path)) `touch \(marker.path)`"

        _ = try shellReadsBack(value)

        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test("A single quote becomes close, escaped quote, reopen")
    func singleQuoteForm() {
        #expect(ShellQuoting.quoted("it's") == "'it'\\''s'")
        #expect(ShellQuoting.quoted("") == "''")
    }

    @Test("Command lines and assignments quote every value")
    func commandLineAndAssignment() {
        #expect(ShellQuoting.commandLine(["bash", "/p/w t", "vcrun2019"]) == "'bash' '/p/w t' 'vcrun2019'")
        #expect(ShellQuoting.assignment("WINEPREFIX", "/Users/me/It's") == "WINEPREFIX='/Users/me/It'\\''s'")
    }
}
