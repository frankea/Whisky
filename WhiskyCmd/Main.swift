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
            discussion: "Runs a Windows program directly using Wine. Use --command to print the command instead."
        )

        @Argument(help: "Name of the bottle to use")
        var bottleName: String

        @Argument(help: "Path to the Windows executable")
        var path: String

        @Argument(help: "Additional arguments to pass to the program")
        var args: [String] = []

        @Flag(name: .shortAndLong, help: "Print the Wine command instead of running it")
        var command: Bool = false

        @MainActor
        mutating func run() async throws {
            var bottlesList = BottleData()
            let bottles = bottlesList.loadBottles()

            guard let bottle = bottles.first(where: { $0.settings.name == bottleName }) else {
                throw ValidationError("A bottle with that name doesn't exist.")
            }

            let url = URL(fileURLWithPath: path)
            let program = Program(url: url, bottle: bottle)

            if command {
                // Print the command for manual execution or scripting
                // Use array overload to properly escape each argument individually
                print(program.generateTerminalCommand(args: args))
            } else {
                // Run directly via Wine, applying program-specific environment and locale
                let environment = program.generateEnvironment()
                try await Wine.runProgram(at: url, args: args, bottle: bottle, environment: environment)
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
