//
//  RedactorSecretTests.swift
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

@Suite("Redactor: secret shapes")
struct RedactorSecretTests {
    private func redact(_ text: String) -> String {
        Redactor.redactSecrets(text)
    }

    @Test("key=value and key: value forms lose their value", arguments: [
        ("token=abc123", "token=<redacted>"),
        ("api_key=sk-live-9f8e7d", "api_key=<redacted>"),
        ("Password: hunter2", "Password: <redacted>"),
        ("STEAM_AUTH := deadbeef", "STEAM_AUTH := <redacted>"),
        ("access-token=eyJ.abc", "access-token=<redacted>"),
        ("secret=\"quoted value\" next", "secret=<redacted> next")
    ])
    func keyValueForms(input: String, expected: String) {
        #expect(redact(input) == expected)
    }

    @Test("Flag forms lose their value but keep the flag and the rest of the line")
    func flagForms() {
        #expect(redact("-dx11 -token abc123 -windowed") == "-dx11 -token <redacted> -windowed")
        #expect(redact("--password hunter2 --nolauncher") == "--password <redacted> --nolauncher")
        #expect(redact("-pass 1234 --auth x") == "-pass <redacted> --auth <redacted>")
    }

    @Test("Authorization credentials, URL user info, query parameters and JWTs")
    func webShapes() {
        #expect(redact("Authorization: Bearer abcdefgh12345678") == "Authorization: Bearer <redacted>")
        #expect(redact("Basic dXNlcjpwYXNz==") == "Basic <redacted>")
        #expect(redact("https://user:p%40ss@example.com/path") == "https://<redacted>@example.com/path")
        #expect(redact("https://alice@example.com/") == "https://<redacted>@example.com/")
        #expect(redact("GET /api?token=abc&x=1&sig=zzz") == "GET /api?token=<redacted>&x=1&sig=<redacted>")
        #expect(redact("jwt eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0In0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV")
            == "jwt <redacted>")
    }

    @Test("Prose and ordinary keys are left alone")
    func negatives() {
        for line in [
            "auth failed, retrying",
            "keyboard layout: US",
            "Steam token refresh scheduled",
            "err:winediag:secur32 no password given",
            "-dx11 -windowed -width=1920",
            "fixme:ntdll:NtQueryInformationToken stub"
        ] {
            #expect(redact(line) == line, "\(line)")
        }
    }

    @Test("Log text redaction combines home paths and secrets")
    func logTextCombines() {
        var home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        if home.hasSuffix("/") {
            home.removeLast()
        }
        let text = "loading \(home)/Games/x.exe --token abc"
        let out = Redactor.redactLogText(text)
        #expect(out.contains("/Users/<redacted>/Games/x.exe"))
        #expect(out.hasSuffix("--token <redacted>"))
    }

    @Test("Program arguments are scrubbed unless sensitive details are included")
    @MainActor func programSummaryGating() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir.appending(path: "drive_c"), withIntermediateDirectories: true)
        let bottle = Bottle(bottleUrl: dir, inFlight: false, isAvailable: true)
        let exe = dir.appending(path: "drive_c/game.exe")
        try Data().write(to: exe)
        let program = Program(url: exe, bottle: bottle, peFile: nil)
        program.settings.arguments = "-dx11 -token abc123"

        let scrubbed = DiagnosticExporter.programSettingsSummary(program: program, options: ExportOptions())
        #expect(scrubbed.contains("-token <redacted>"))
        #expect(!scrubbed.contains("abc123"))

        let raw = DiagnosticExporter.programSettingsSummary(
            program: program, options: ExportOptions(includeSensitiveDetails: true)
        )
        #expect(raw.contains("-token abc123"))
    }
}
