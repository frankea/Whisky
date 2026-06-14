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
import os.log
import SwiftUI

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
    /// Indicates whether the installed-programs list is currently being scanned.
    ///
    /// Set while ``programs`` is being repopulated by an off-main-actor directory
    /// walk, so the UI can show a loading indicator instead of hitching the main
    /// thread on a large bottle.
    @Published public var programsLoading: Bool = false
    /// Indicates whether the bottle's directory exists and is accessible.
    public var isAvailable: Bool = false

    /// The in-flight program scan, if any, used to coalesce concurrent rescans.
    /// See ``coalesceProgramScan(_:)``.
    private var programScanTask: Task<Void, Never>?

    // MARK: - Cross-actor access (nonisolated members on @MainActor Bottle)

    /// The unique identifier for this bottle.
    ///
    /// This property is `nonisolated` to allow access from any thread,
    /// making it safe to use in collections and async contexts.
    public nonisolated var id: URL {
        url
    }

    /// Returns all pinned programs with their associated ``Program`` objects.
    ///
    /// This computed property filters and maps the pins in settings to their
    /// corresponding program objects, excluding pins for programs that no longer exist.
    ///
    /// - Returns: A tuple array containing the pin, program, and a unique identifier string.
    public var pinnedPrograms: [( // swiftlint:disable:this large_tuple
        pin: PinnedProgram,
        program: Program,
        id: String
    )] {
        settings.pins.compactMap { pin in
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
                """
                Failed to load settings for bottle \
                `\(metadataURL.path(percentEncoded: false), privacy: .public)`: \
                \(String(describing: error), privacy: .public)
                """
            )
            // Preserve the unreadable file before defaults overwrite it, so a corrupt
            // Metadata.plist is moved aside for diagnosis rather than silently destroyed.
            BottleSettings.quarantineCorruptedFile(at: metadataURL)
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

    /// Manually saves the bottle settings to disk synchronously.
    ///
    /// Settings are automatically saved when modified through the ``settings`` property.
    /// Use this method when you need to ensure settings are persisted immediately,
    /// such as before app termination or before launching programs that depend on
    /// current settings (e.g., launcher compatibility fixes).
    ///
    /// - Note: This method completes synchronously and blocks until the file write
    ///   finishes or fails. Any save errors are logged but not thrown.
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

    // MARK: - Program discovery

    /// Lower-cased basenames of helper / crash-reporter / redistributable
    /// executables that pollute the installed-programs list. Filtered before the
    /// user's `blocklist` so the visible list stays clean by default.
    ///
    /// Conservative: only unambiguously-noise binaries (helpers, crash reporters,
    /// redistributables). Generic `setup.exe`/`installer.exe` are intentionally
    /// excluded because users still need to launch installers.
    public nonisolated static let noiseExecutableNames: Set<String> = [
        "steamerrorreporter.exe",
        "steamerrorreporter64.exe",
        "steamservice.exe",
        "steamwebhelper.exe",
        "steam_monitor.exe",
        "steamsysinfo.exe",
        "steamxboxutil.exe",
        "crashreporter.exe",
        "crashhandler.exe",
        "crashpad_handler.exe",
        "gameoverlayui.exe",
        "gameoverlayui64.exe",
        "fossilize-replay.exe",
        "fossilize-replay64.exe",
        "gldriverquery.exe",
        "gldriverquery64.exe",
        "hardwareupdater.exe",
        "secure_desktop_capture.exe",
        "writeminidump.exe",
        "vc_redist.x86.exe",
        "vc_redist.x64.exe",
        "vcredist_x86.exe",
        "vcredist_x64.exe",
        "ueprereqsetup_x86.exe",
        "ueprereqsetup_x64.exe",
        "crossover html engine.exe"
    ]

    /// Walks the bottle's `Program Files` directories and returns the URLs of
    /// installed `.exe` files, excluding ClickOnce cache artifacts, known noise
    /// executables, and anything in `blocklist`.
    ///
    /// This is a pure filesystem read with no actor-isolated state, so callers
    /// can run it off the main actor — it's the heavy part of repopulating
    /// ``programs`` for a large bottle.
    ///
    /// - Parameters:
    ///   - driveC: The bottle's `drive_c` directory.
    ///   - blocklist: User-blocked program URLs to omit.
    /// - Returns: Discovered executable URLs in filesystem-enumeration order.
    public nonisolated static func discoverInstalledExecutables(
        driveC: URL,
        blocklist: Set<URL>
    ) -> [URL] {
        var found: [URL] = []
        for folderName in ["Program Files", "Program Files (x86)"] {
            let folderURL = driveC.appending(path: folderName)
            let enumerator = FileManager.default.enumerator(
                at: folderURL, includingPropertiesForKeys: [.isExecutableKey], options: [.skipsHiddenFiles]
            )

            while let url = enumerator?.nextObject() as? URL {
                guard !url.hasDirectoryPath, url.pathExtension == "exe" else { continue }
                // Skip ClickOnce cache executables (noisy internal artifacts)
                guard !url.path.contains("/Apps/2.0/") else { continue }
                // Skip known launcher helpers and crash reporters that pollute the list
                guard !noiseExecutableNames.contains(url.lastPathComponent.lowercased()) else { continue }
                guard !blocklist.contains(url) else { continue }
                found.append(url)
            }
        }
        return found
    }

    /// Runs a program rescan, coalescing concurrent callers onto one scan.
    ///
    /// If a scan is already in flight this awaits *that* scan instead of starting
    /// a duplicate or returning early. The distinction matters versus an
    /// early-return guard: a caller that bailed out would then read whatever
    /// ``programs`` happened to hold (e.g. the Start Menu auto-pin pinning against
    /// an empty list), whereas awaiting means the caller observes the in-flight
    /// scan's freshly published results before it proceeds. The owning call clears
    /// the handle when its scan finishes, so the next call starts a fresh scan.
    ///
    /// The coalesced result reflects the in-flight scan, which began at the
    /// *owning* call — so a caller that must observe a change it made after that
    /// scan started should rescan once the current one completes.
    ///
    /// - Parameter scan: The rescan body; should publish into ``programs`` and
    ///   manage ``programsLoading``. Only the owning call runs it — coalesced
    ///   callers just await the shared result.
    public func coalesceProgramScan(_ scan: @escaping @MainActor () async -> Void) async {
        if let existing = programScanTask {
            await existing.value
            return
        }
        let task = Task { @MainActor in await scan() }
        programScanTask = task
        defer { programScanTask = nil }
        await task.value
    }

    // MARK: - Equatable

    public nonisolated static func == (lhs: Bottle, rhs: Bottle) -> Bool {
        lhs.url == rhs.url
    }

    // MARK: - Hashable

    public nonisolated func hash(into hasher: inout Hasher) {
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
        self.filter(\.pinned)
    }

    /// Returns only the unpinned programs from the sequence.
    ///
    /// Use this alongside ``pinned`` to separate programs into categories
    /// in the user interface.
    var unpinned: [Program] {
        self.filter { !$0.pinned }
    }
}
