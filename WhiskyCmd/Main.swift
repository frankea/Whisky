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

@main
struct Whisky: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "A CLI interface for Whisky.",
        subcommands: [
            List.self,
            Create.self,
            Add.self,
//                      Export.self,
            Delete.self,
            Remove.self,
            Run.self,
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
            let bottleURL = BottleData.defaultBottleDir.appending(path: UUID().uuidString)

            do {
                try FileManager.default.createDirectory(
                    atPath: bottleURL.path(percentEncoded: false),
                    withIntermediateDirectories: true
                )
                let bottle = Bottle(bottleUrl: bottleURL, inFlight: true)
                // Should allow customisation
                bottle.settings.windowsVersion = .win10
                bottle.settings.name = name
//                try await Wine.changeWinVersion(bottle: bottle, win: winVersion)
//                let wineVer = try await Wine.wineVersion()
                bottle.settings.wineVersion = SemanticVersion(0, 0, 0)

                var bottlesList = BottleData()
                bottlesList.paths.append(bottleURL)
                print("Created new bottle \"\(name)\".")
            } catch {
                throw ValidationError("\(error)")
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
                    print("Deleted \"\(name)\".")
                } catch {
                    print(error)
                }
            } else {
                throw ValidationError("No bottle called \"\(name)\" found.")
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
                throw ValidationError("No bottle called \"\(name)\" found.")
            }
        }
    }

    struct Run: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Run a program with Whisky.",
            discussion: """
            Runs a Windows program directly using Wine. Use --command to print \
            the command instead. Use --follow to stream program output to the \
            terminal in real time. Use --tail-log to follow the Wine log file.
            """
        )

        @Argument(help: "Name of the bottle to use")
        var bottleName: String

        // Path handling note: ArgumentParser treats @Argument as a single string
        // (including spaces via shell quoting), and Wine.runProgram passes the URL
        // through an argument array (not string interpolation), so paths with
        // spaces, parentheses, apostrophes, and ampersands work correctly.
        @Argument(help: "Path to the Windows executable")
        var path: String

        @Argument(help: "Additional arguments to pass to the program")
        var args: [String] = []

        @Flag(name: .shortAndLong, help: "Print the Wine command instead of running it")
        var command: Bool = false

        @Flag(name: .long, help: "Stream program output to terminal")
        var follow: Bool = false

        @Flag(name: .long, help: "Follow the Wine log file after launch")
        var tailLog: Bool = false

        @MainActor
        mutating func run() async throws {
            var bottlesList = BottleData()
            let bottles = bottlesList.loadBottles()

            guard let bottle = bottles.first(where: { $0.settings.name == bottleName }) else {
                throw ValidationError("A bottle with that name doesn't exist.")
            }

            // URL(fileURLWithPath:) handles paths with special characters correctly
            let url = URL(fileURLWithPath: path)
            let program = Program(url: url, bottle: bottle)

            if command {
                // Print the command for manual execution or scripting
                // Use array overload to properly escape each argument individually
                print(program.generateTerminalCommand(args: args))
            } else if follow {
                // Stream Wine output to the terminal in real time
                try await runWithFollow(url: url, args: args, bottle: bottle, program: program)
            } else {
                // Default mode: launch and print deterministic confirmation
                try await runDefault(url: url, args: args, bottle: bottle, program: program)
            }
        }

        /// Default run mode: launches the program and prints a deterministic confirmation line.
        @MainActor
        private func runDefault(url: URL, args: [String], bottle: Bottle, program: Program) async throws {
            let environment = program.generateEnvironment()

            do {
                let result = try await Wine.runProgram(
                    at: url, args: args, bottle: bottle, environment: environment
                )

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
        private func runWithFollow(
            url: URL, args: [String], bottle: Bottle, program: Program
        ) async throws {
            let environment = program.generateEnvironment()
            var exitCode: Int32 = 0

            // Use the public runWineProcess streaming API for real-time output
            let wineArgs = ["start", "/unix", url.path(percentEncoded: false)] + args
            let stream = try Wine.runWineProcess(
                name: url.lastPathComponent, args: wineArgs, bottle: bottle, environment: environment
            )

            for await output in stream {
                switch output {
                case .started:
                    break
                case let .message(line):
                    FileHandle.standardOutput.write(Data(line.utf8))
                case let .error(line):
                    FileHandle.standardError.write(Data(line.utf8))
                case let .terminated(code):
                    exitCode = code
                }
            }

            FileHandle.standardError.write(Data("Exited with code \(exitCode)\n".utf8))

            if exitCode != 0 {
                throw ExitCode(exitCode)
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

    struct Shellenv: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Prints export statements for a Bottle for eval.")

        @Argument var bottleName: String

        @MainActor
        mutating func run() async throws {
            var bottlesList = BottleData()
            let bottles = bottlesList.loadBottles()

            guard let bottle = bottles.first(where: { $0.settings.name == bottleName }) else {
                throw ValidationError("A bottle with that name doesn't exist.")
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
