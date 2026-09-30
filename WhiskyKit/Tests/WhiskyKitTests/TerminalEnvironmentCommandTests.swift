//
//  TerminalEnvironmentCommandTests.swift
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

/// `WhiskyCmd shellenv` prints ``Wine/generateTerminalEnvironmentCommand(bottle:)`` for
/// `eval`, and Open in Terminal evaluates the same text in the user's login shell. A syntax
/// check cannot catch the failure this guards against: the old output parsed fine and still
/// set the wrong values. So these tests evaluate the real output in each installed login
/// shell (zsh and bash ship with macOS, fish is tested where Homebrew put it) and compare
/// what it exports with the environment it was generated from.
///
/// Serialized for the same reason as ``ShellQuotingTests``: each case waits on a real shell.
@Suite("Terminal environment command", .serialized)
struct TerminalEnvironmentCommandTests {
    /// Characters a custom bottle path can carry. The old quoting kept the backslash `.esc`
    /// puts before a space, `=`, `;` or `'`, and stripped it before `"`, `$`, a backtick or
    /// another backslash; both groups are checked.
    static let trickyCharacters: [Character] = [" ", "=", ";", "$", "`", "\"", "'", "\\"]

    /// Evaluates `output` the way `eval "$(WhiskyCmd shellenv <bottle>)"` does, then runs
    /// `probe` in the same shell.
    static func evaluate(
        _ output: String,
        in shell: TestShell,
        home: URL,
        then probe: String
    ) throws -> TestShell.Result {
        // WhiskyCmd prints the output with a trailing newline; feed it the same way.
        try shell.run("eval \"$(/bin/cat)\" || exit 97\n\(probe)", input: output + "\n", home: home)
    }

    /// What `shell` exports after evaluating `output`, read back with `env -0` so values
    /// containing newlines stay whole.
    static func exportedEnvironment(
        evaluating output: String,
        in shell: TestShell,
        home: URL
    ) throws -> [String: String] {
        let result = try evaluate(output, in: shell, home: home, then: "/usr/bin/env -0")
        try #require(result.status == 0, "\(shell.rawValue) exited \(result.status): \(result.errors)")
        var environment: [String: String] = [:]
        for entry in result.stdout.split(separator: 0) {
            guard let text = String(bytes: entry, encoding: .utf8), let separator = text.firstIndex(of: "=") else {
                continue
            }
            environment[String(text[..<separator])] = String(text[text.index(after: separator)...])
        }
        return environment
    }

    @Test("Evaluating the output exports the bottle's environment verbatim", arguments: TestShell.loginShells)
    @MainActor func bottleEnvironmentSurvivesEval(shell: TestShell) throws {
        let root = try TestShell.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        // A custom bottle location can contain any of these; WINEPREFIX and
        // DXVK_CONFIG_FILE carry the path into the environment.
        let bottleURL = root.appending(path: #"Games it's "odd" $HOME `id` back\slash; a=b"#)
        try FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)
        try Data().write(to: bottleURL.appending(path: "dxvk.conf"))
        let bottle = Bottle(bottleUrl: bottleURL, isAvailable: true)
        bottle.settings.graphicsBackend = .dxvk
        // Override names come from the bottle's Metadata.plist. The last one ran its
        // substitution in fish while backslashes were left inside the single quotes.
        // The report's list had DXVK's `d3d12=`, which the preset now only sets over
        // D3DMetal's builtin, so the empty value is set by hand to keep it under test.
        let marker = root.appending(path: "expanded")
        bottle.settings.dllOverrides = [
            DLLOverrideEntry(dllName: "d2d1", mode: .nativeThenBuiltin),
            DLLOverrideEntry(dllName: "d3d12", mode: .disabled),
            DLLOverrideEntry(dllName: #"it's "odd" $HOME `id` back\slash"#, mode: .native),
            DLLOverrideEntry(dllName: #"x\'$(touch \#(marker.path))\'"#, mode: .native)
        ]

        let output = Wine.generateTerminalEnvironmentCommand(bottle: bottle)
        let expected = Wine.constructWineEnvironment(for: bottle)

        // Guard against a vacuous pass: the settings have to put every character under
        // test into the values, starting with the override list from the report.
        let prefix = try #require(expected["WINEPREFIX"])
        let overrides = try #require(expected["WINEDLLOVERRIDES"])
        #expect(overrides.hasPrefix("d2d1=n,b;d3d10core=n,b;d3d11=n,b;d3d12=;d3d9=n,b;dxgi=n,b;"))
        #expect(overrides.contains(#"x\'$(touch "#))
        #expect(expected["DXVK_CONFIG_FILE"] == "Z:\(prefix)/dxvk.conf")
        for character in Self.trickyCharacters {
            #expect(prefix.contains(character), "WINEPREFIX lacks \(character)")
            #expect(overrides.contains(character), "WINEDLLOVERRIDES lacks \(character)")
        }

        let exported = try Self.exportedEnvironment(evaluating: output, in: shell, home: root)
        for (key, value) in expected where Wine.isValidEnvKey(key) {
            #expect(exported[key] == value, "\(key)")
        }
        #expect(exported["PATH"] == "\(WhiskyWineInstaller.binFolder.path):\(TestShell.basePath)")
        #expect(exported["WINE"] == "wine64")
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test(
        "A bin folder with spaces and quotes goes first on PATH and wine64 resolves",
        arguments: TestShell.loginShells
    )
    func binFolderSurvivesEval(shell: TestShell) throws {
        let root = try TestShell.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let binFolder = root.appending(path: "Application Support")
            .appending(path: #"it's "odd" $HOME `id` back\slash; a=b"#)
            .appending(path: "bin")
        try FileManager.default.createDirectory(at: binFolder, withIntermediateDirectories: true)
        let wine64 = binFolder.appending(path: "wine64")
        try Data("#!/bin/sh\necho wine-stub\n".utf8).write(to: wine64)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wine64.path)

        let output = Wine.generateTerminalEnvironmentCommand(binFolder: binFolder, environment: [:])

        let exported = try Self.exportedEnvironment(evaluating: output, in: shell, home: root)
        #expect(exported["PATH"] == "\(binFolder.path):\(TestShell.basePath)")

        // The reported symptom: with a literal backslash left in the PATH entry, the
        // lookup missed and `wine64` exited 127.
        let lookup = try Self.evaluate(output, in: shell, home: root, then: "command -v wine64 && wine64")
        #expect(lookup.status == 0, "\(lookup.errors)")
        #expect(lookup.output == "\(wine64.path)\nwine-stub\n")
    }

    @Test("Values a shell would expand, split or unescape come back verbatim", arguments: TestShell.loginShells)
    func shellSyntaxInValuesSurvivesEval(shell: TestShell) throws {
        let root = try TestShell.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let marker = root.appending(path: "expanded")
        let environment = [
            "OVERRIDES": "d2d1=n,b;d3d10core=n,b;d3d11=n,b;d3d12=;d3d9=n,b;dxgi=n,b",
            "SPACES": "  leading, inner and trailing  ",
            "QUOTES": #"it's "quoted" ''doubled'' '"#,
            "BACKSLASHES": #"\ \\ \n \' \" \$ trailing\"#,
            "EXPANSIONS": "$HOME ${HOME} $(touch \(marker.path)) `touch \(marker.path)`",
            "ESCAPED_QUOTES": #"x\'$(touch \#(marker.path))\'"#,
            "GLOBS": "* ? [a-z] ~ ~/x:~/y !",
            "OPERATORS": "a; b && c || d | e > f < g & (h) {i} # j",
            "CONTROL": "line one\nline two\ttab\rreturn\n",
            "EMPTY": "",
            "UNICODE": "Ångström 游戏",
            "COMBINING": "x'\u{301}; touch \(marker.path); echo '",
            "NOT A KEY": "skipped"
        ]

        let output = Wine.generateTerminalEnvironmentCommand(binFolder: root, environment: environment)
        let exported = try Self.exportedEnvironment(evaluating: output, in: shell, home: root)

        for (key, value) in environment where Wine.isValidEnvKey(key) {
            #expect(exported[key] == value, "\(key)")
        }
        #expect(!output.contains("NOT A KEY"))
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }
}
