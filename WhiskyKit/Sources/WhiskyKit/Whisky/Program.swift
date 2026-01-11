//
//  Program.swift
//  WhiskyKit
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
import SwiftUI
import os.log

/// Represents a Windows executable program within a ``Bottle``.
///
/// A `Program` encapsulates a Windows `.exe` file along with its configuration,
/// parsed metadata, and pin state. It provides access to program-specific settings
/// that can override bottle-level defaults.
///
/// ## Overview
///
/// Programs are discovered by scanning a bottle's `drive_c` directory for executable
/// files. Each program has its own settings file for locale, environment variables,
/// and command-line arguments.
///
/// ## Running a Program
///
/// ```swift
/// @MainActor
/// func runProgram(_ program: Program) async throws {
///     let environment = program.generateEnvironment()
///     try await Wine.runProgram(
///         at: program.url,
///         args: program.settings.arguments.split(separator: " ").map(String.init),
///         bottle: program.bottle,
///         environment: environment
///     )
/// }
/// ```
///
/// ## Pinning Programs
///
/// Pin frequently-used programs for quick access:
///
/// ```swift
/// program.pinned = true  // Adds to bottle's pinned programs
/// ```
///
/// ## Topics
///
/// ### Creating Programs
/// - ``init(url:bottle:)``
///
/// ### Program Information
/// - ``name``
/// - ``url``
/// - ``bottle``
/// - ``peFile``
///
/// ### Configuration
/// - ``settings``
/// - ``generateEnvironment()``
///
/// ### Pin State
/// - ``pinned``
@MainActor
public final class Program: ObservableObject, Equatable, Hashable, Identifiable {
    /// The ``Bottle`` that contains this program.
    public let bottle: Bottle
    /// The file system URL to the program's executable file.
    public let url: URL
    /// The URL where this program's settings are stored.
    public let settingsURL: URL

    /// The display name of the program, derived from the executable filename.
    public var name: String {
        url.lastPathComponent
    }

    /// The program-specific configuration settings.
    ///
    /// Changes to settings are automatically persisted to disk.
    /// These settings can override bottle-level defaults for locale
    /// and environment variables.
    @Published public var settings: ProgramSettings {
        didSet { saveSettings() }
    }

    /// Whether this program is pinned for quick access.
    ///
    /// Setting this property automatically updates the bottle's pin list.
    /// Pinned programs appear in a separate section of the UI.
    @Published public var pinned: Bool {
        didSet {
            if pinned {
                bottle.settings.pins.append(PinnedProgram(
                    name: name.replacingOccurrences(of: ".exe", with: ""),
                    url: url
                ))
            } else {
                bottle.settings.pins.removeAll(where: { $0.url == url })
            }
        }
    }

    /// The parsed PE (Portable Executable) file metadata.
    ///
    /// This provides access to the executable's architecture, resources,
    /// and icon. May be `nil` if the file couldn't be parsed.
    public let peFile: PEFile?

    // MARK: - Cross-actor access (nonisolated members on @MainActor type)

    /// The unique identifier for this program.
    ///
    /// This property is `nonisolated` to allow access from any thread,
    /// making it safe to use in collections and async contexts.
    nonisolated public var id: URL {
        url
    }

    /// Creates a new program instance for an executable file.
    ///
    /// This initializer loads existing settings from the program's settings file
    /// if present, or creates default settings. It also parses the PE file to
    /// extract metadata and icons.
    ///
    /// - Parameters:
    ///   - url: The URL to the Windows executable (.exe) file.
    ///   - bottle: The ``Bottle`` that contains this program.
    public init(url: URL, bottle: Bottle) {
        let name = url.lastPathComponent
        self.bottle = bottle
        self.url = url
        self.pinned = bottle.settings.pins.contains(where: { $0.url == url })

        // Warning: This will break if two programs share the same name such as "Launch.exe"
        // Best to add some sort of UUID in the path or file
        let settingsFolder = bottle.url.appending(path: "Program Settings")
        let settingsUrl = settingsFolder.appending(path: name).appendingPathExtension("plist")
        self.settingsURL = settingsUrl

        do {
            if !FileManager.default.fileExists(atPath: settingsFolder.path(percentEncoded: false)) {
                try FileManager.default.createDirectory(at: settingsFolder, withIntermediateDirectories: true)
            }

            self.settings = try ProgramSettings.decode(from: settingsUrl)
        } catch {
            Logger.wineKit.error("Failed to load settings for `\(name)`: \(error)")
            self.settings = ProgramSettings()
        }

        do {
            self.peFile = try PEFile(url: url)
        } catch {
            self.peFile = nil
        }
    }

    /// Generates the environment variables for running this program.
    ///
    /// This method combines the program's custom environment variables with
    /// locale settings. The resulting dictionary can be passed to Wine when
    /// executing the program.
    ///
    /// - Returns: A dictionary of environment variable names to values.
    public func generateEnvironment() -> [String: String] {
        var environment = settings.environment
        if settings.locale != .auto {
            environment["LC_ALL"] = settings.locale.rawValue
        }
        return environment
    }

    /// Save the settings to file
    private func saveSettings() {
        do {
            try settings.encode(to: settingsURL)
        } catch {
            Logger.wineKit.error("Failed to save settings for `\(self.name)`: \(error)")
        }
    }

    // MARK: - Equatable

    nonisolated public static func == (lhs: Program, rhs: Program) -> Bool {
        return lhs.url == rhs.url
    }

    // MARK: - Hashable

    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}
