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
/// `eval`, and Open in Terminal evaluates the same text. A syntax check cannot catch the
/// failure this guards against: the old output parsed fine in both shells and still set
/// the wrong values. So these tests evaluate the real output in the two shells macOS
/// ships and compare what each one exports with the environment it was generated from.
@Suite("Terminal environment command")
struct TerminalEnvironmentCommandTests {
    enum Shell: String, CaseIterable, CustomTestStringConvertible {
        case zsh
        case bash

        var executable: URL {
            URL(filePath: "/bin/\(rawValue)")
        }

        /// Skips every startup file, so nothing but the output under test touches the
        /// environment.
        var startupFlags: [String] {
            switch self {
            case .zsh:
                ["-f"]
            case .bash:
                ["--noprofile", "--norc"]
            }
        }

        var testDescription: String {
            rawValue
        }
    }

    struct ShellResult {
        let status: Int32
        let stdout: Data
        let stderr: Data

        var output: String {
            String(bytes: stdout, encoding: .utf8) ?? ""
        }

        var errors: String {
            String(bytes: stderr, encoding: .utf8) ?? ""
        }
    }

    /// The PATH each shell starts with. Nothing on it provides `wine64`.
    static let basePath = "/usr/bin:/bin:/usr/sbin:/sbin"

    /// The characters the old quoting got wrong. Inside double quotes the shell keeps the
    /// backslash `.esc` puts before a space, `=`, `;` or `'`, and only strips it before
    /// `"`, `$`, a backtick or another backslash.
    static let trickyCharacters: [Character] = [" ", "=", ";", "$", "`", "\"", "'", "\\"]

    /// Evaluates `output` the way `eval "$(WhiskyCmd shellenv <bottle>)"` does, then runs
    /// `probe` in the same shell.
    static func evaluate(_ output: String, in shell: Shell, then probe: String) throws -> ShellResult {
        let process = Process()
        process.executableURL = shell.executable
        process.arguments = shell.startupFlags + ["-c", "eval \"$(/bin/cat)\" || exit 97\n\(probe)"]
        process.environment = ["PATH": basePath]
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        // WhiskyCmd prints the output with a trailing newline; feed it the same way.
        stdin.fileHandleForWriting.write(Data((output + "\n").utf8))
        try stdin.fileHandleForWriting.close()
        let out = stdout.fileHandleForReading.readDataToEndOfFile()
        let err = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ShellResult(status: process.terminationStatus, stdout: out, stderr: err)
    }

    /// What `shell` exports after evaluating `output`, read back with `env -0` so values
    /// containing newlines stay whole.
    static func exportedEnvironment(evaluating output: String, in shell: Shell) throws -> [String: String] {
        let result = try evaluate(output, in: shell, then: "/usr/bin/env -0")
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

    static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "shellenv-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Evaluating the output exports the bottle's environment verbatim", arguments: Shell.allCases)
    @MainActor func bottleEnvironmentSurvivesEval(shell: Shell) throws {
        let root = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        // A custom bottle location can contain any of these; WINEPREFIX and
        // DXVK_CONFIG_FILE carry the path into the environment.
        let bottleURL = root.appending(path: #"Games it's "odd" $HOME `id` back\slash; a=b"#)
        try FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)
        try Data().write(to: bottleURL.appending(path: "dxvk.conf"))
        let bottle = Bottle(bottleUrl: bottleURL, isAvailable: true)
        bottle.settings.graphicsBackend = .dxvk
        bottle.settings.dllOverrides = [
            DLLOverrideEntry(dllName: "d2d1", mode: .nativeThenBuiltin),
            DLLOverrideEntry(dllName: #"it's "odd" $HOME `id` back\slash"#, mode: .native)
        ]

        let output = Wine.generateTerminalEnvironmentCommand(bottle: bottle)
        let expected = Wine.constructWineEnvironment(for: bottle)

        // Guard against a vacuous pass: the settings have to put every character under
        // test into the values, starting with the override list from the report.
        let prefix = try #require(expected["WINEPREFIX"])
        let overrides = try #require(expected["WINEDLLOVERRIDES"])
        #expect(overrides.hasPrefix("d2d1=n,b;d3d10core=n,b;d3d11=n,b;d3d12=;d3d9=n,b;dxgi=n,b;"))
        #expect(expected["DXVK_CONFIG_FILE"] == "Z:\(prefix)/dxvk.conf")
        for character in Self.trickyCharacters {
            #expect(prefix.contains(character), "WINEPREFIX lacks \(character)")
            #expect(overrides.contains(character), "WINEDLLOVERRIDES lacks \(character)")
        }

        let exported = try Self.exportedEnvironment(evaluating: output, in: shell)
        for (key, value) in expected where Wine.isValidEnvKey(key) {
            #expect(exported[key] == value, "\(key)")
        }
        #expect(exported["PATH"] == "\(WhiskyWineInstaller.binFolder.path):\(Self.basePath)")
        #expect(exported["WINE"] == "wine64")
    }

    @Test("A bin folder with spaces and quotes goes first on PATH and wine64 resolves", arguments: Shell.allCases)
    func binFolderSurvivesEval(shell: Shell) throws {
        let root = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let binFolder = root.appending(path: "Application Support")
            .appending(path: #"it's "odd" $HOME `id` back\slash; a=b"#)
            .appending(path: "bin")
        try FileManager.default.createDirectory(at: binFolder, withIntermediateDirectories: true)
        let wine64 = binFolder.appending(path: "wine64")
        try Data("#!/bin/sh\necho wine-stub\n".utf8).write(to: wine64)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wine64.path)

        let output = Wine.generateTerminalEnvironmentCommand(binFolder: binFolder, environment: [:])

        let exported = try Self.exportedEnvironment(evaluating: output, in: shell)
        #expect(exported["PATH"] == "\(binFolder.path):\(Self.basePath)")

        // The reported symptom: with a literal backslash left in the PATH entry, the
        // lookup missed and `wine64` exited 127.
        let lookup = try Self.evaluate(output, in: shell, then: "command -v wine64 && wine64")
        #expect(lookup.status == 0, "\(lookup.errors)")
        #expect(lookup.output == "\(wine64.path)\nwine-stub\n")
    }

    @Test("Values a shell would expand, split or unescape come back verbatim", arguments: Shell.allCases)
    func shellSyntaxInValuesSurvivesEval(shell: Shell) throws {
        let root = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let marker = root.appending(path: "expanded")
        let environment = [
            "OVERRIDES": "d2d1=n,b;d3d10core=n,b;d3d11=n,b;d3d12=;d3d9=n,b;dxgi=n,b",
            "SPACES": "  leading, inner and trailing  ",
            "QUOTES": #"it's "quoted" ''doubled'' '"#,
            "BACKSLASHES": #"\ \\ \n \' \" \$ trailing\"#,
            "EXPANSIONS": "$HOME ${HOME} $(touch \(marker.path)) `touch \(marker.path)`",
            "GLOBS": "* ? [a-z] ~ ~/x:~/y !",
            "OPERATORS": "a; b && c || d | e > f < g & (h) {i} # j",
            "CONTROL": "line one\nline two\ttab\rreturn\n",
            "EMPTY": "",
            "UNICODE": "Ångström 游戏",
            "NOT A KEY": "skipped"
        ]

        let output = Wine.generateTerminalEnvironmentCommand(binFolder: root, environment: environment)
        let exported = try Self.exportedEnvironment(evaluating: output, in: shell)

        for (key, value) in environment where Wine.isValidEnvKey(key) {
            #expect(exported[key] == value, "\(key)")
        }
        #expect(!output.contains("NOT A KEY"))
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }
}
