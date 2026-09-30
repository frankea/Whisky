// swiftlint:disable file_length
//
//  Main.swift
//  WhiskyCmd
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

import ArgumentParser
import Foundation
import SemanticVersion
import WhiskyKit

/// A well-formed invocation that names state the system does not have or an
/// operation that failed: a missing bottle, an unknown game, a failed
/// creation. Prints the message to stderr and exits 1. Exit 64 with the
/// usage block stays reserved for malformed invocations.
struct DomainError: LocalizedError {
    private let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}

@main
struct Whisky: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "A CLI interface for Whisky.",
        discussion: """
        Exit codes: 64 for a malformed invocation (unknown flags, missing or \
        empty arguments; printed with usage), 1 for a well-formed command \
        that fails (no such bottle, game not found, operation failed), and \
        `run` and `launch` pass through the launched program's own nonzero \
        exit code.
        """,
        subcommands: [
            List.self,
            Create.self,
            Add.self,
//                      Export.self,
            Delete.self,
            Remove.self,
            Run.self,
            Games.self,
            Launch.self,
            Shortcut.self,
            Shellenv.self
            /* Install.self,
             Uninstall.self */
        ]
    )
}

extension Whisky {
    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List existing bottles.")

        @MainActor
        mutating func run() async throws {
            var bottlesList = BottleData()
            let bottles = bottlesList.loadBottles()

            var table = TextTable(headers: ["Name", "Windows Version", "Path"])
            for bottle in bottles {
                table.addRow(values: [
                    bottle.settings.name,
                    bottle.settings.windowsVersion.pretty(),
                    bottle.url.prettyPath()
                ])
            }

            print(table.render())
        }
    }

    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Create a new bottle.")

        @Argument var name: String

        @MainActor
        mutating func run() async throws {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw ValidationError("Bottle name cannot be empty.")
            }

            var bottlesList = BottleData()
            let existing = bottlesList.loadBottles()
            if existing.contains(where: { $0.settings.name == trimmed }) {
                throw DomainError("A bottle named \"\(trimmed)\" already exists.")
            }

            let bottleURL = BottleData.defaultBottleDir.appending(path: UUID().uuidString)

            do {
                try FileManager.default.createDirectory(
                    atPath: bottleURL.path(percentEncoded: false),
                    withIntermediateDirectories: true
                )
                let bottle = Bottle(bottleUrl: bottleURL, inFlight: true)
                bottle.settings.windowsVersion = .win10
                bottle.settings.name = trimmed
                bottle.settings.wineVersion = SemanticVersion(0, 0, 0)

                bottlesList.paths.append(bottleURL)
                print("Created bottle \"\(trimmed)\". Open Whisky to bootstrap the Wine prefix.")
            } catch {
                throw DomainError("\(error)")
            }
        }
    }

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Add an existing bottle.")

        @Argument var path: String

        mutating func run() throws {
            // Should be sanitised
            let bottleURL = URL(filePath: path)
            let settings = try BottleSettings.decode(from: bottleURL)
            var bottlesList = BottleData()
            bottlesList.paths.append(bottleURL)
            print("Bottle \"\(settings.name)\" added.")
        }
    }

    struct Export: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Export an existing bottle.")

        mutating func run() throws {
//            print("Create a bottle")
        }
    }

    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Delete an existing bottle from disk.")

        @Argument var name: String

        @MainActor
        mutating func run() async throws {
            var bottlesList = BottleData()
            let bottles = bottlesList.loadBottles()

            // Should ask for confirmation
            let bottleToRemove = bottles.first(where: { $0.settings.name == name })
            if let bottleToRemove {
                bottlesList.paths.removeAll(where: { $0 == bottleToRemove.url })
                do {
                    try FileManager.default.removeItem(at: bottleToRemove.url)
                    GameRouting().removeRoutes(toBottle: bottleToRemove.url)
                    print("Deleted \"\(name)\".")
                } catch {
                    print(error)
                }
            } else {
                throw DomainError("No bottle called \"\(name)\" found.")
            }
        }
    }

    struct Remove: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Remove an existing bottle from Whisky.",
            discussion: "This will not remove the bottle from disk."
        )

        @Argument var name: String

        @MainActor
        mutating func run() async throws {
            var bottlesList = BottleData()
            let bottles = bottlesList.loadBottles()

            let bottleToRemove = bottles.first(where: { $0.settings.name == name })
            if let bottleToRemove {
                bottlesList.paths.removeAll(where: { $0 == bottleToRemove.url })
                print("Removed \"\(name)\".")
            } else {
                throw DomainError("No bottle called \"\(name)\" found.")
            }
        }
    }

    struct Run: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Run a program with Whisky.",
            discussion: """
            Runs a Windows program directly using Wine, with the same settings \
            and preparation as a launch from Whisky. Use --command to print the \
            command instead: the bottle is prepared first (DLL overrides written \
            to its registry, graphics backend files deployed), so the printed \
            command runs the program the same way. Use --follow to stream program \
            output to the terminal in real time. Use --tail-log to follow the \
            Wine log file.

            Options the program itself takes (for example --disable-gpu) are \
            passed through as written. If a program option has the same name \
            as one of run's own options, put it after a bare -- separator: \
            whisky run MyBottle app.exe -- --follow
            """
        )

        @Argument(help: "Name of the bottle to use")
        var bottleName: String

        /// Path handling note: ArgumentParser treats @Argument as a single string
        /// (including spaces via shell quoting), and Wine.runProgram passes the URL
        /// through an argument array (not string interpolation), so paths with
        /// spaces, parentheses, apostrophes, and ampersands work correctly.
        @Argument(help: "Path to the Windows executable")
        var path: String

        /// .allUnrecognized keeps run's own flags working anywhere on the
        /// command line while options the parser doesn't know (--disable-gpu)
        /// flow through to the program instead of erroring. A program flag
        /// that collides with one of run's flag names still needs the `--`
        /// terminator to reach the program.
        @Argument(parsing: .allUnrecognized, help: "Additional arguments to pass to the program")
        var args: [String] = []

        @Flag(name: .shortAndLong, help: "Prepare the bottle and print the Wine command instead of running it")
        var command: Bool = false

        @Flag(name: .long, help: "Stream program output to terminal")
        var follow: Bool = false

        @Flag(name: .long, help: "Follow the Wine log file after launch")
        var tailLog: Bool = false

        @MainActor
        mutating func run() async throws {
            // .allUnrecognized captures the -- terminator itself instead of
            // consuming it the way default parsing does. Drop the first one
            // so `run B app.exe -- --follow` hands the program --follow, not
            // `-- --follow`; any later -- stays, as it always has.
            if let terminator = args.firstIndex(of: "--") {
                args.remove(at: terminator)
            }

            var bottlesList = BottleData()
            let bottles = bottlesList.loadBottles()

            guard let bottle = bottles.first(where: { $0.settings.name == bottleName }) else {
                throw DomainError("A bottle with that name doesn't exist.")
            }

            let url = URL(fileURLWithPath: Self.resolveExecutablePath(path, in: bottle))
            let program = Program(url: url, bottle: bottle)

            if command {
                // Print the command for manual execution or scripting. The bottle
                // is prepared the way a launch prepares it, since the registry and
                // prefix state that preparation leaves behind is part of what makes
                // the command behave like a launch from Whisky.
                let terminalCommand = try await program.prepareTerminalCommand(args: args)
                print(terminalCommand)
            } else if follow {
                // Stream Wine output to the terminal in real time
                try await runWithFollow(args: args, program: program)
            } else {
                // Default mode: launch and print deterministic confirmation
                try await runDefault(url: url, args: args, bottle: bottle, program: program)
            }
        }

        /// Resolves a user-supplied path to a Unix path inside the bottle.
        ///
        /// Windows-style paths like `C:\windows\notepad.exe` get translated to the
        /// bottle's `drive_c/windows/notepad.exe`. Everything else is taken verbatim
        /// (URL(fileURLWithPath:) will resolve relative paths against the CWD).
        @MainActor
        static func resolveExecutablePath(_ raw: String, in bottle: Bottle) -> String {
            // Match drive-letter Windows paths like `C:\...` or `C:/...`
            guard let driveMatch = raw.range(of: #"^([A-Za-z]):[\\/]"#, options: .regularExpression) else {
                return raw
            }
            let drive = raw[raw.index(driveMatch.lowerBound, offsetBy: 0)].lowercased()
            let rest = raw[driveMatch.upperBound...]
                .replacingOccurrences(of: "\\", with: "/")
            let prefix = bottle.url.appending(path: "drive_\(drive)")
            return prefix.appending(path: rest).path(percentEncoded: false)
        }

        /// Default run mode: launches the program and prints a deterministic confirmation line.
        @MainActor
        private func runDefault(url: URL, args: [String], bottle: Bottle, program: Program) async throws {
            do {
                let result = try await program.launch(args: args)

                let exeName = url.lastPathComponent
                let bottleName = bottle.settings.name
                var message = "Launched \"\(exeName)\" in bottle \"\(bottleName)\"."

                // Append log path for traceability
                message += " Log: \(result.logFileURL.path(percentEncoded: false))"
                print(message)

                if tailLog {
                    // After launch confirmation, tail the log file
                    try await tailLogFile(at: result.logFileURL)
                }

                if result.exitCode != 0 {
                    throw ExitCode(result.exitCode)
                }
            } catch let exitCode as ExitCode {
                throw exitCode
            } catch {
                FileHandle.standardError.write(
                    Data("Error: \(error.localizedDescription)\n".utf8)
                )
                throw ExitCode(1)
            }
        }

        /// Follow mode: streams Wine process stdout/stderr to the terminal in real time.
        @MainActor
        private func runWithFollow(args: [String], program: Program) async throws {
            // The same launch as the default mode, with its output streamed as it
            // arrives, so following a program never changes how it runs.
            let result = try await program.launch(args: args) { output in
                switch output {
                case .started, .terminated:
                    break
                case let .message(line):
                    FileHandle.standardOutput.write(Data(line.utf8))
                case let .error(line):
                    FileHandle.standardError.write(Data(line.utf8))
                }
            }

            FileHandle.standardError.write(Data("Exited with code \(result.exitCode)\n".utf8))

            if result.exitCode != 0 {
                throw ExitCode(result.exitCode)
            }
        }

        /// Tails a log file, printing new lines as they appear until the Wine process exits.
        @MainActor
        private func tailLogFile(at logFileURL: URL) async throws {
            guard FileManager.default.fileExists(atPath: logFileURL.path(percentEncoded: false)) else {
                return
            }

            guard let handle = try? FileHandle(forReadingFrom: logFileURL) else { return }
            defer { try? handle.close() }

            // Seek to end to only show new content
            _ = try? handle.seekToEnd()

            // Poll for new data until interrupted
            // This is a simple polling approach; exits after 5 seconds of no new data
            var idleCount = 0
            let maxIdleIterations = 50 // 50 * 100ms = 5 seconds of no new data

            while idleCount < maxIdleIterations {
                let data = handle.availableData
                if data.isEmpty {
                    idleCount += 1
                    try await Task.sleep(for: .milliseconds(100))
                } else {
                    idleCount = 0
                    if let text = String(data: data, encoding: .utf8) {
                        FileHandle.standardOutput.write(Data(text.utf8))
                    }
                }
            }
        }
    }

    struct Shortcut: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Create a macOS app shortcut for a Windows program."
        )

        @Argument(help: "Name of the bottle")
        var bottleName: String

        @Argument(help: "Path to the Windows executable")
        var exePath: String

        @Option(name: .long, help: "Display name for the shortcut")
        var name: String?

        @Option(name: .long, help: "Output directory (default: ~/Applications)")
        var output: String?

        @Flag(name: .long, help: "Overwrite existing shortcut")
        var overwrite: Bool = false

        @MainActor
        mutating func run() async throws {
            var bottlesList = BottleData()
            let bottles = bottlesList.loadBottles()

            guard let bottle = bottles.first(where: { $0.settings.name == bottleName }) else {
                throw DomainError("A bottle with that name doesn't exist.")
            }

            let url = URL(fileURLWithPath: exePath)
            let program = Program(url: url, bottle: bottle)

            // Determine shortcut name: --name option or program name sans extension
            let shortcutName = name ?? url.deletingPathExtension().lastPathComponent

            // Determine output directory: --output option or ~/Applications/
            let outputDir: URL = if let output {
                URL(fileURLWithPath: output)
            } else {
                FileManager.default.homeDirectoryForCurrentUser
                    .appending(path: "Applications")
            }

            // Ensure output directory exists
            if !FileManager.default.fileExists(atPath: outputDir.path(percentEncoded: false)) {
                try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
            }

            let appURL = outputDir.appending(path: "\(shortcutName).app")

            // Check for existing shortcut
            if FileManager.default.fileExists(atPath: appURL.path(percentEncoded: false)) {
                if overwrite {
                    try FileManager.default.removeItem(at: appURL)
                } else {
                    throw DomainError(
                        "Shortcut already exists at \(appURL.path(percentEncoded: false)). "
                            + "Use --overwrite to replace it."
                    )
                }
            }

            // Generate launch script and create the bundle
            let target = ShortcutCreator.liveTarget(for: program.url, bottle: program.bottle)
            let launchScript = ShortcutCreator.liveLaunchScript(for: target)
            try ShortcutCreator.createShortcutBundle(at: appURL, launchScript: launchScript, name: shortcutName)

            print("Created \(appURL.path(percentEncoded: false))")
        }
    }

    struct Shellenv: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Prints export statements for a Bottle for eval.")

        @Argument var bottleName: String

        @MainActor
        mutating func run() async throws {
            var bottlesList = BottleData()
            let bottles = bottlesList.loadBottles()

            guard let bottle = bottles.first(where: { $0.settings.name == bottleName }) else {
                throw DomainError("A bottle with that name doesn't exist.")
            }

            let envCmd = Wine.generateTerminalEnvironmentCommand(bottle: bottle)
            print(envCmd)
        }
    }

    struct Install: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Install WhiskyWine.")

        mutating func run() throws {}
    }

    struct Uninstall: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Uninstall WhiskyWine.")

        @Flag(name: [.long, .short], help: "Uninstall WhiskyWine") var whiskyWine = false

        mutating func run() throws {}
    }
}

extension Whisky {
    struct Games: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List Steam games installed in a bottle."
        )

        @Argument(help: "Name of the bottle to inspect")
        var bottleName: String

        @Flag(name: .long, help: "Output as JSON")
        var json: Bool = false

        @MainActor
        mutating func run() async throws {
            var bottlesList = BottleData()
            let bottles = bottlesList.loadBottles()

            guard let bottle = bottles.first(where: { $0.settings.name == bottleName }) else {
                throw DomainError("A bottle with that name doesn't exist.")
            }

            let games = SteamLibrary.enumerate(bottleURL: bottle.url)

            if json {
                let payload = games.map { game in
                    [
                        "appId": String(game.appId),
                        "name": game.name,
                        "installPath": game.installURL.path(percentEncoded: false)
                    ]
                }
                let data = try JSONSerialization.data(
                    withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]
                )
                print(String(bytes: data, encoding: .utf8) ?? "")
                return
            }

            var table = TextTable(headers: ["App ID", "Name", "Install Dir"])
            for game in games {
                table.addRow(values: [
                    String(game.appId),
                    game.name,
                    game.installURL.lastPathComponent
                ])
            }
            print(table.render())
        }
    }

    struct Launch: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Launch a Steam game by App ID.",
            discussion: """
            Without --bottle, the bottle a game was last launched from is used, \
            falling back to the first bottle that has it installed.

            The game is launched through the bottle's Steam client, which starts \
            first if it isn't running. The command confirms once Wine is running \
            the client, then waits for that invocation to finish: a few seconds \
            when the client was already running, the whole session when this \
            launch started it.
            """
        )

        @Argument(help: "Steam App ID of the game")
        var appId: Int

        @Option(name: .long, help: "Name of the bottle to launch from")
        var bottle: String?

        @Flag(name: .long, help: "Output as JSON")
        var json: Bool = false

        @MainActor
        mutating func run() async throws {
            var bottlesList = BottleData()
            let bottles = bottlesList.loadBottles()

            let target: Bottle
            if let bottleName = bottle {
                guard let named = bottles.first(where: { $0.settings.name == bottleName }) else {
                    throw DomainError("A bottle with that name doesn't exist.")
                }
                target = named
            } else {
                target = try SteamLauncher.resolveBottle(appId: appId, in: bottles)
            }

            // The launch happens inside the returned task. Returning before it
            // finishes ended the process while the task was still preparing the
            // bottle, so Steam never started. Confirm once Wine is running the
            // client, then wait for that invocation the way `run` waits.
            let appId = self.appId
            let json = self.json
            let bottleName = target.settings.name
            let launch = try SteamLauncher.launch(appId: appId, bottle: target) { output in
                if case .started = output {
                    Self.printConfirmation(appId: appId, bottleName: bottleName, json: json)
                }
            }
            let result = try await launch.value

            if result.exitCode != 0 {
                // The confirmation is out already, so say why this still fails.
                let log = result.logFileURL.path(percentEncoded: false)
                FileHandle.standardError.write(Data("Steam exited with code \(result.exitCode). Log: \(log)\n".utf8))
                throw ExitCode(result.exitCode)
            }
        }

        /// Prints that the game was handed to the bottle's Steam client.
        @MainActor
        private static func printConfirmation(appId: Int, bottleName: String, json: Bool) {
            guard json else {
                print("Launched \(appId) in \(bottleName)")
                return
            }
            let payload = [
                "appId": String(appId),
                "bottle": bottleName,
                "status": "launched"
            ]
            let data = try? JSONSerialization.data(
                withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]
            )
            print(data.flatMap { String(bytes: $0, encoding: .utf8) } ?? "")
        }
    }
}
