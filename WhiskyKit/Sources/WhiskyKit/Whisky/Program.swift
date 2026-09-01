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

import CryptoKit
import Foundation
import os.log
import SwiftUI

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
/// - Note: The argument splitting shown above is simplified and doesn't handle
///   quoted arguments. The `arguments` string is expected to contain simple
///   space-separated values like `-windowed -nosound`.
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

    /// The display name of the program: the executable filename.
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
    public nonisolated var id: URL {
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
    public convenience init(url: URL, bottle: Bottle) {
        self.init(url: url, bottle: bottle, peFile: try? PEFile(url: url))
    }

    /// The settings file for a program, keyed by the executable's
    /// bottle-relative path so two programs sharing a filename
    /// (the classic `Launch.exe` case) never collide. The name keeps the
    /// executable's stem for readability: `Launch-3fa2b1c9.plist`.
    ///
    /// Legacy filename-keyed settings are migrated by copying (never moving)
    /// the old plist to the identity-keyed name on first load, so downgrading
    /// loses nothing.
    static func settingsURL(for url: URL, in bottle: Bottle, legacyName: String) -> URL {
        let locations = settingsLocations(for: url, bottleURL: bottle.url, legacyName: legacyName)
        let fileManager = FileManager.default
        try? fileManager.createDirectory(
            at: locations.identity.deletingLastPathComponent(), withIntermediateDirectories: true
        )

        if !fileManager.fileExists(atPath: locations.identity.path(percentEncoded: false)),
           fileManager.fileExists(atPath: locations.legacy.path(percentEncoded: false)) {
            do {
                try fileManager.copyItem(at: locations.legacy, to: locations.identity)
            } catch {
                Logger.wineKit.error(
                    "Failed to migrate settings for `\(legacyName)`: \(error.localizedDescription)"
                )
            }
        }
        return locations.identity
    }

    /// Where a program's settings live: the identity-keyed plist and the
    /// legacy filename-keyed one it may have to be migrated from. Pure path
    /// computation; nothing is created or copied.
    nonisolated static func settingsLocations(
        for url: URL, bottleURL: URL, legacyName: String
    ) -> (identity: URL, legacy: URL) {
        let settingsFolder = bottleURL.appending(path: "Program Settings")
        let identityURL = settingsFolder
            .appending(path: settingsIdentity(for: url, bottleURL: bottleURL))
            .appendingPathExtension("plist")
        let legacyURL = settingsFolder.appending(path: legacyName).appendingPathExtension("plist")
        return (identityURL, legacyURL)
    }

    /// The overrides an executable's persisted settings carry, read without
    /// materializing a ``Program``: a missing settings plist yields `nil`
    /// where the initializer would write a default plist to disk.
    ///
    /// A legacy filename-keyed plist is read in place; migrating it to the
    /// identity-keyed name stays with the initializer, as does quarantining
    /// an unreadable plist (an unreadable plist reads as no overrides here).
    nonisolated static func persistedOverrides(for url: URL, bottleURL: URL) -> ProgramOverrides? {
        let locations = settingsLocations(for: url, bottleURL: bottleURL, legacyName: url.lastPathComponent)
        let settingsURL = FileManager.default.fileExists(atPath: locations.identity.path(percentEncoded: false))
            ? locations.identity
            : locations.legacy

        do {
            return try ProgramSettings.decodeIfPresent(from: settingsURL)?.overrides
        } catch {
            Logger.wineKit.error(
                """
                Failed to read settings for `\(url.lastPathComponent, privacy: .public)`: \
                \(String(describing: error), privacy: .public)
                """
            )
            return nil
        }
    }

    /// A stable identity for a program: the executable's stem plus a short
    /// hash of its bottle-relative path. Stable across bottle moves (the
    /// relative path doesn't change) and across game updates (file contents
    /// don't participate).
    nonisolated static func settingsIdentity(for url: URL, bottleURL: URL) -> String {
        let bottlePath = bottleURL.standardizedFileURL.path
        let fullPath = url.standardizedFileURL.path
        let relativePath = fullPath.hasPrefix(bottlePath)
            ? String(fullPath.dropFirst(bottlePath.count))
            : fullPath

        let digest = SHA256.hash(data: Data(relativePath.utf8))
        let shortHash = digest.prefix(4).map { String(format: "%02x", $0) }.joined()
        let stem = url.deletingPathExtension().lastPathComponent
        return "\(stem)-\(shortHash)"
    }

    /// Creates a new program instance from an already-parsed PE file.
    ///
    /// Use this when the PE file was parsed off the main actor (e.g. during a
    /// bulk installed-programs scan), so the executable isn't re-read on the main
    /// thread. Settings are still loaded here; that's a small per-program plist
    /// read. Pass `nil` for `peFile` when the file isn't a parseable PE.
    ///
    /// - Parameters:
    ///   - url: The URL to the Windows executable (.exe) file.
    ///   - bottle: The ``Bottle`` that contains this program.
    ///   - peFile: The pre-parsed PE metadata, or `nil` if it couldn't be parsed.
    public init(url: URL, bottle: Bottle, peFile: PEFile?) {
        let name = url.lastPathComponent
        self.bottle = bottle
        self.url = url
        self.pinned = bottle.settings.pins.contains(where: { $0.url == url })

        let settingsUrl = Self.settingsURL(for: url, in: bottle, legacyName: name)
        self.settingsURL = settingsUrl

        do {
            self.settings = try ProgramSettings.decode(from: settingsUrl)
        } catch {
            Logger.wineKit.error(
                "Failed to load settings for `\(name)`: \(String(describing: error), privacy: .public)"
            )
            // Preserve the unreadable file before the next save overwrites it with defaults.
            BottleSettings.quarantineCorruptedFile(at: settingsUrl)
            self.settings = ProgramSettings()
        }

        self.peFile = peFile
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

    public nonisolated static func == (lhs: Program, rhs: Program) -> Bool {
        lhs.url == rhs.url
    }

    // MARK: - Hashable

    public nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}
