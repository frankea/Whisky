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

// Serialized: every case blocks a thread on a real shell process, and running them
// all at once starves the cooperative pool that timing-sensitive suites rely on.
@Suite("Shell quoting", .serialized)
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
        "semi; echo pwned",
        "pipe | cat",
        "amp && echo hi",
        "hash # not a comment",
        "tilde ~/home",
        "star * glob",
        "newline\nin name",
        "unicode Ångström 游戏",
        // fish, unlike POSIX shells, reads \' and \\ as escapes inside single quotes.
        #"back\'slash"#,
        #"trailing\"#,
        #"double\\backslash"#,
        // A quote with a combining mark on it is one Character, unequal to "'".
        "combining '\u{301} mark",
        "''",
        ""
    ]

    /// What `shell` prints for `printf %s <quoted value>`.
    private func readBack(_ value: String, in shell: TestShell, home: URL) async throws -> String {
        try await shell.run("printf %s " + ShellQuoting.quoted(value), home: home).output
    }

    @Test("Every installed shell reads each quoted value back verbatim", arguments: TestShell.installed, hostile)
    func roundTrips(shell: TestShell, value: String) async throws {
        let home = try TestShell.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }

        #expect(try await readBack(value, in: shell, home: home) == value)
    }

    @Test("Command substitution inside a quoted value never runs", arguments: TestShell.installed)
    func substitutionIsInert(shell: TestShell) async throws {
        let home = try TestShell.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let marker = home.appending(path: "expanded").path
        let values = [
            "Bottle $(touch \(marker)) `touch \(marker)`",
            // fish reads `\'` as an escaped quote inside a quoted run, so while
            // backslashes stayed inside, fish ended the run at a different quote
            // than a POSIX shell and ran the substitution.
            #"x\'$(touch \#(marker))\'"#,
            // A Character-level replacement skipped a quote with a combining mark on
            // it, which then ended the run early in every shell.
            "x'\u{301}; touch \(marker); echo '",
            "x'\u{301}$(touch \(marker))'\u{301}"
        ]

        for value in values {
            #expect(try await readBack(value, in: shell, home: home) == value)
        }
        #expect(!FileManager.default.fileExists(atPath: marker))
    }

    @Test("A single quote or a backslash becomes close, escaped character, reopen")
    func singleQuoteForm() {
        #expect(ShellQuoting.quoted("it's") == "'it'\\''s'")
        #expect(ShellQuoting.quoted("") == "''")
        // No quoted run may hold a backslash, or fish splits the word differently
        // from POSIX shells. CI has no fish, so the form itself is pinned here.
        #expect(ShellQuoting.quoted(#"C:\dir\"#) == #"'C:'\\'dir'\\''"#)
        #expect(ShellQuoting.quoted(#"x\'"#) == #"'x'\\''\'''"#)
        // The quote under a combining mark is escaped like any other.
        #expect(ShellQuoting.quoted("a'\u{301}") == "'a'\\''\u{301}'")
    }

    @Test("PATH assignment safely quotes paths containing spaces")
    func pathWithSpaces() throws {
        let wineBin = "/Users/test/Library/Application Support/com.franke.Whisky/Libraries/Wine/bin"
        let command = "export PATH=\(ShellQuoting.quoted(wineBin)):\"$PATH\""

        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", command + "; printf %s \"$PATH\""]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let path = String(bytes: data, encoding: .utf8) ?? ""
        #expect(path.hasPrefix(wineBin + ":"))
    }

    @Test("Command lines and assignments quote every value")
    func commandLineAndAssignment() {
        #expect(ShellQuoting.commandLine(["bash", "/p/w t", "vcrun2019"]) == "'bash' '/p/w t' 'vcrun2019'")
        #expect(ShellQuoting.assignment("WINEPREFIX", "/Users/me/It's") == "WINEPREFIX='/Users/me/It'\\''s'")
    }
}
