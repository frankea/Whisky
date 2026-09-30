//
//  ShellTestSupport.swift
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

/// A real shell for tests to run generated shell text in. Reading the text cannot show
/// what a shell makes of it, so the tests run it and check the result.
enum TestShell: String, CaseIterable, CustomTestStringConvertible {
    // Named for its executable, /bin/sh.
    // swiftlint:disable:next identifier_name
    case sh
    case zsh
    case bash
    case dash
    case ksh
    case fish

    /// The shells installed here. macOS ships all of them except fish, which users install
    /// from Homebrew, so fish is tested wherever it is present.
    static let installed = allCases.filter { $0.executable != nil }

    /// The installed shells people use as their login shell: zsh (the macOS default), bash
    /// and fish. Open in Terminal sources its script in the login shell.
    static let loginShells = installed.filter { [.zsh, .bash, .fish].contains($0) }

    /// The PATH each shell starts with. Nothing on it provides `wine64`.
    static let basePath = "/usr/bin:/bin:/usr/sbin:/sbin"

    var executable: URL? {
        let candidates = switch self {
        case .fish:
            ["/opt/homebrew/bin/fish", "/usr/local/bin/fish"]
        case .sh, .zsh, .bash, .dash, .ksh:
            ["/bin/\(rawValue)"]
        }
        return candidates.first(where: FileManager.default.isExecutableFile(atPath:)).map { URL(filePath: $0) }
    }

    /// Skips every startup file, so nothing but the text under test touches the
    /// environment. sh, dash and ksh read none when given `-c`.
    var startupFlags: [String] {
        switch self {
        case .zsh:
            ["-f"]
        case .bash:
            ["--noprofile", "--norc"]
        case .fish:
            ["--no-config", "--private"]
        case .sh, .dash, .ksh:
            []
        }
    }

    var testDescription: String {
        rawValue
    }

    struct Result {
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

    /// Runs `script` with `-c` in `home`, writing `input` to its standard input.
    ///
    /// The environment holds only ``basePath`` and a `HOME` of `home`: fish creates its
    /// configuration directories under `HOME` even with `--no-config`, and those belong in
    /// the test's temporary directory, not the user's. Running in `home` also means that a
    /// payload which does run, and writes to a relative path, writes inside it.
    ///
    /// The pipe reads and the exit wait hold their thread until the shell exits, so they run
    /// in a detached task, off whatever actor the caller is on. On the main actor they would
    /// hold it for the whole run and starve the suites that need it to answer in time.
    func run(_ script: String, input: String = "", home: URL) async throws -> Result {
        let executableURL = try #require(executable, "\(rawValue) is not installed")
        let arguments = startupFlags + ["-c", script]
        return try await Task.detached {
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            process.environment = ["PATH": Self.basePath, "HOME": home.path]
            process.currentDirectoryURL = home
            let stdin = Pipe()
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = stderr
            try process.run()
            stdin.fileHandleForWriting.write(Data(input.utf8))
            try stdin.fileHandleForWriting.close()
            let out = stdout.fileHandleForReading.readDataToEndOfFile()
            let err = stderr.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return Result(status: process.terminationStatus, stdout: out, stderr: err)
        }.value
    }

    /// A fresh directory for one test to use as `home`; the caller removes it.
    static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "shell-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
