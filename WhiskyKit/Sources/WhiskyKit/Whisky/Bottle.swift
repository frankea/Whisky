//
//  Bottle.swift
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

/// Represents an isolated Wine environment for running Windows applications.
///
/// A bottle is a Wine prefix—a self-contained directory containing a Windows-like
/// filesystem, registry, and configuration. Each bottle can have different Windows
/// versions, installed programs, and settings without affecting other bottles.
///
/// ## Overview
///
/// Bottles are the primary organizational unit in Whisky. Users can create multiple
/// bottles for different games or applications, each with its own configuration.
///
/// ## Creating a Bottle
///
/// ```swift
/// let bottleURL = FileManager.default.urls(
///     for: .applicationSupportDirectory,
///     in: .userDomainMask
/// )[0].appendingPathComponent("MyBottle")
///
/// let bottle = Bottle(bottleUrl: bottleURL)
/// bottle.settings.name = "Gaming Bottle"
/// bottle.settings.windowsVersion = .win10
/// ```
///
/// ## Running Programs
///
/// Use ``Wine/runProgram(at:args:bottle:environment:)`` to execute programs within a bottle:
///
/// ```swift
/// try await Wine.runProgram(at: programURL, bottle: bottle)
/// ```
///
/// ## Thread Safety
///
/// `Bottle` is `@MainActor` isolated. For cross-thread access to the identifier,
/// use the `nonisolated` ``id`` property.
///
/// ## Topics
///
/// ### Creating Bottles
/// - ``init(bottleUrl:inFlight:isAvailable:)``
///
/// ### Configuration
/// - ``settings``
/// - ``saveBottleSettings()``
///
/// ### Programs
/// - ``programs``
/// - ``pinnedPrograms``
///
/// ### State
/// - ``url``
/// - ``inFlight``
/// - ``isAvailable``
@MainActor
public final class Bottle: ObservableObject, Equatable, Hashable, Identifiable, @preconcurrency Comparable {
    /// The file system URL to this bottle's directory.
    public let url: URL
    /// URL to the bottle's metadata plist file.
    private let metadataURL: URL
    /// The bottle's configuration settings.
    ///
    /// Changes to settings are automatically persisted to disk.
    @Published public var settings: BottleSettings {
        didSet { saveSettings() }
    }
    /// The list of discovered Windows programs in this bottle.
    ///
    /// Programs are typically populated by scanning the bottle's drive_c directory.
    @Published public var programs: [Program] = []
    /// Indicates whether the bottle is currently being created or modified.
    @Published public var inFlight: Bool = false
    /// Indicates whether the bottle's directory exists and is accessible.
    public var isAvailable: Bool = false

    // MARK: - Cross-actor access (nonisolated members on @MainActor Bottle)

    /// The unique identifier for this bottle.
    ///
    /// This property is `nonisolated` to allow access from any thread,
    /// making it safe to use in collections and async contexts.
    nonisolated public var id: URL {
        url
    }

    /// Returns all pinned programs with their associated ``Program`` objects.
    ///
    /// This computed property filters and maps the pins in settings to their
    /// corresponding program objects, excluding pins for programs that no longer exist.
    ///
    /// - Returns: A tuple array containing the pin, program, and a unique identifier string.
    public var pinnedPrograms: [(pin: PinnedProgram, program: Program, // swiftlint:disable:this large_tuple
                                 id: String)] {
        return settings.pins.compactMap { pin in
            let exists = FileManager.default.fileExists(atPath: pin.url?.path(percentEncoded: false) ?? "")
            guard let program = programs.first(where: { $0.url == pin.url && exists }) else { return nil }
            return (pin, program, "\(pin.name)//\(program.url)")
        }
    }

    /// Creates a new bottle instance from a directory URL.
    ///
    /// This initializer loads existing settings from the metadata file if present,
    /// or creates default settings if the file doesn't exist or is corrupted.
    /// Invalid pins (referencing deleted programs) are automatically cleaned up.
    ///
    /// - Parameters:
    ///   - bottleUrl: The URL to the bottle's root directory.
    ///   - inFlight: Whether the bottle is currently being created. Defaults to `false`.
    ///   - isAvailable: Whether the bottle directory is accessible. Defaults to `false`.
    public init(bottleUrl: URL, inFlight: Bool = false, isAvailable: Bool = false) {
        let metadataURL = bottleUrl.appending(path: "Metadata").appendingPathExtension("plist")
        self.url = bottleUrl
        self.inFlight = inFlight
        self.isAvailable = isAvailable
        self.metadataURL = metadataURL

        do {
            self.settings = try BottleSettings.decode(from: metadataURL)
        } catch {
            Logger.wineKit.error(
                "Failed to load settings for bottle `\(metadataURL.path(percentEncoded: false))`: \(error)"
            )
            // Create default settings if decode fails
            self.settings = BottleSettings()
            // Try to create the metadata file with default settings
            do {
                try self.settings.encode(to: metadataURL)
                Logger.wineKit.info("Created default settings for bottle `\(metadataURL.path(percentEncoded: false))`")
            } catch {
                let path = metadataURL.path(percentEncoded: false)
                Logger.wineKit.error(
                    "Failed to create default settings for bottle `\(path)`: \(error)"
                )
            }
        }

        // Get rid of duplicates and pins that reference removed files
        var found: Set<URL> = []
        self.settings.pins = self.settings.pins.filter { pin in
            guard let url = pin.url else { return false }
            guard !found.contains(url) else { return false }
            found.insert(url)
            let urlPath = url.path(percentEncoded: false)
            let volume: URL?
            do {
                volume = try url.resourceValues(forKeys: [.volumeURLKey]).volume ?? nil
            } catch {
                volume = nil
            }
            let legallyRemoved = pin.removable && volume == nil
            return FileManager.default.fileExists(atPath: urlPath) || legallyRemoved
        }
    }

    /// Manually saves the bottle settings to disk.
    ///
    /// Settings are automatically saved when modified through the ``settings`` property.
    /// Use this method when you need to ensure settings are persisted immediately,
    /// such as before app termination.
    public func saveBottleSettings() {
        saveSettings()
    }

    /// Encode and save the bottle settings
    private func saveSettings() {
        do {
            try settings.encode(to: self.metadataURL)
        } catch {
            Logger.wineKit.error(
                "Failed to encode settings for bottle `\(self.metadataURL.path(percentEncoded: false))`: \(error)"
            )
        }
    }

    // MARK: - Equatable

    nonisolated public static func == (lhs: Bottle, rhs: Bottle) -> Bool {
        return lhs.url == rhs.url
    }

    // MARK: - Hashable

    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }

    // MARK: - Comparable

    public static func < (lhs: Bottle, rhs: Bottle) -> Bool {
        lhs.settings.name.lowercased() < rhs.settings.name.lowercased()
    }
}

// MARK: - Program Sequence Extensions

@MainActor
public extension Sequence where Iterator.Element == Program {
    /// Returns only the pinned programs from the sequence.
    ///
    /// Use this to filter a collection of programs to show favorites or
    /// frequently-used applications.
    var pinned: [Program] {
        return self.filter({ $0.pinned })
    }

    /// Returns only the unpinned programs from the sequence.
    ///
    /// Use this alongside ``pinned`` to separate programs into categories
    /// in the user interface.
    var unpinned: [Program] {
        return self.filter({ !$0.pinned })
    }
}
