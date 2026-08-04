//
//  BottleOperations.swift
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

/// Phases reported during bottle duplication for progress feedback.
public enum DuplicationPhase: Equatable, Sendable {
    /// Calculating total size of the source bottle directory.
    case calculatingSize
    /// Copying files. `bytesCopied` and `totalBytes` track progress.
    case copying(bytesCopied: Int64, totalBytes: Int64)
    /// Rewriting metadata (pins, blocklist) for the new bottle.
    case updatingMetadata
    /// Registering the new bottle and reloading the bottle list.
    case finalizing
}

/// The registry seam ``BottleOperations`` uses to reach the bottle list.
///
/// Operations look up live ``Bottle`` instances, mutate the persisted path
/// registry, and trigger a reload through this protocol instead of touching
/// the app's view model directly, so the operation state machines can be
/// exercised in tests against an in-memory registry.
@MainActor
public protocol BottleRegistry: AnyObject {
    /// The registered bottle paths. Mutations must persist to the backing store.
    var bottlePaths: [URL] { get set }

    /// Returns the live bottle instance for `url`, if one is loaded.
    func bottle(for url: URL) -> Bottle?

    /// Rebuilds the bottle list from ``bottlePaths``.
    func loadBottles()
}

/// Bottle lifecycle operations (move, export, duplicate, remove) shared by the
/// app target so their state machines are testable from the package.
///
/// Each operation resolves the live bottle through a ``BottleRegistry`` and
/// manages the bottle's `inFlight` guard for the duration, preserving the
/// snapshot-and-rollback semantics of the pin/blocklist rewrite during a move
/// (issue #154).
public enum BottleOperations {
    // MARK: - Move

    /// Moves the bottle directory at `url` to `destination`.
    ///
    /// Pin and blocklist URLs are rewritten to `destination` *before* the file
    /// move so the persisted settings travel with the bottle; a snapshot of
    /// both is restored if the move throws, so a failed move never leaves
    /// settings pointing at a path that was never created (issue #154). If no
    /// live bottle exists for `url` the file move is still attempted.
    ///
    /// - Parameters:
    ///   - url: The bottle's current directory.
    ///   - destination: The directory the bottle should move to.
    ///   - registry: The registry that owns the bottle list.
    @MainActor
    public static func move(bottleAt url: URL, to destination: URL, registry: BottleRegistry) {
        let bottle = registry.bottle(for: url)
        // The URL rewrite must happen before the move so the persisted settings
        // travel with the bottle, so keep a snapshot to restore on failure.
        let originalPins = bottle?.settings.pins
        let originalBlocklist = bottle?.settings.blocklist

        bottle?.inFlight = true
        defer { bottle?.inFlight = false }

        do {
            if let bottle {
                for index in 0 ..< bottle.settings.pins.count {
                    let pin = bottle.settings.pins[index]
                    if let pinURL = pin.url {
                        bottle.settings.pins[index].url = pinURL.updateParentBottle(
                            old: url,
                            new: destination
                        )
                    }
                }

                for index in 0 ..< bottle.settings.blocklist.count {
                    let blockedUrl = bottle.settings.blocklist[index]
                    bottle.settings.blocklist[index] = blockedUrl.updateParentBottle(
                        old: url,
                        new: destination
                    )
                }
            }
            try FileManager.default.moveItem(at: url, to: destination)
            if let path = registry.bottlePaths.firstIndex(of: url) {
                registry.bottlePaths[path] = destination
            }
            registry.loadBottles()
        } catch {
            // A failed move must not leave settings pointing at a path that
            // was never created.
            if let bottle {
                if let originalPins {
                    bottle.settings.pins = originalPins
                }
                if let originalBlocklist {
                    bottle.settings.blocklist = originalBlocklist
                }
            }
            Logger.wineKit.error("Failed to move bottle: \(error.localizedDescription)")
        }
    }

    // MARK: - Export

    /// Exports the bottle at `url` as a gzip-compressed tar archive.
    ///
    /// The archive work runs on a background task to avoid blocking the main
    /// actor. The bottle's `inFlight` property is set for the duration so the
    /// UI can show progress and block conflicting actions.
    ///
    /// - Parameters:
    ///   - url: The bottle's directory.
    ///   - destination: The URL where the archive should be saved.
    ///   - registry: The registry that owns the bottle list.
    /// - Throws: `TarError` if the archive operation fails, or an error if the
    ///   bottle is not found.
    @MainActor
    public static func export(bottleAt url: URL, to destination: URL, registry: BottleRegistry) async throws {
        guard let bottle = registry.bottle(for: url) else {
            throw bottleNotFoundError()
        }
        bottle.inFlight = true
        defer { bottle.inFlight = false }

        // Capture URL before entering detached task to satisfy actor isolation
        let sourceURL = url
        try await Task.detached(priority: .userInitiated) {
            try Tar.tar(folder: sourceURL, toURL: destination)
        }.value
    }

    // MARK: - Duplicate

    /// Duplicates the bottle at `url` to a new directory with the given name.
    ///
    /// The copy runs on a background task to avoid blocking the main actor.
    /// The bottle's `inFlight` property is set during the operation, and an
    /// optional progress callback reports duplication phases for UI feedback.
    ///
    /// On copy failure the partially created directory is removed before
    /// re-throwing. Transient artifacts (old logs, diagnosis history) are
    /// excluded from the clone.
    ///
    /// - Parameters:
    ///   - url: The source bottle's directory.
    ///   - newName: The name for the duplicated bottle.
    ///   - registry: The registry that owns the bottle list.
    ///   - progress: Optional callback reporting ``DuplicationPhase`` updates.
    /// - Returns: The URL of the newly created bottle directory.
    /// - Throws: An error if the bottle is not found or the copy operation fails.
    @MainActor
    public static func duplicate(
        bottleAt url: URL,
        newName: String,
        registry: BottleRegistry,
        progress: (@Sendable (DuplicationPhase) -> Void)? = nil
    ) async throws -> URL {
        guard let bottle = registry.bottle(for: url) else {
            throw bottleNotFoundError()
        }
        bottle.inFlight = true
        defer { bottle.inFlight = false }

        // Create new bottle directory in the same parent folder
        let parentDir = url.deletingLastPathComponent()
        let newBottleDir = parentDir.appendingPathComponent(UUID().uuidString)

        // Capture URLs before entering detached task to satisfy actor isolation
        let sourceURL = url
        try await Task.detached(priority: .userInitiated) {
            // Phase: calculate size
            progress?(.calculatingSize)
            let totalBytes = Self.calculateDirectorySize(at: sourceURL)

            // Phase: copying
            progress?(.copying(bytesCopied: 0, totalBytes: totalBytes))
            do {
                try FileManager.default.copyItem(at: sourceURL, to: newBottleDir)
            } catch {
                // Clean up partial clone on failure
                try? FileManager.default.removeItem(at: newBottleDir)
                throw error
            }
            progress?(.copying(bytesCopied: totalBytes, totalBytes: totalBytes))

            // Remove transient artifacts from the clone
            Self.removeTransientArtifacts(in: newBottleDir)
        }.value

        // Phase: updating metadata
        progress?(.updatingMetadata)

        // Update the new bottle's settings
        let newBottle = Bottle(bottleUrl: newBottleDir)
        newBottle.settings.name = newName

        // Update pin URLs to point to the new bottle
        for index in 0 ..< newBottle.settings.pins.count {
            if let pinURL = newBottle.settings.pins[index].url {
                newBottle.settings.pins[index].url = pinURL.updateParentBottle(
                    old: sourceURL,
                    new: newBottleDir
                )
            }
        }

        // Update blocklist URLs to point to the new bottle
        for index in 0 ..< newBottle.settings.blocklist.count {
            newBottle.settings.blocklist[index] = newBottle.settings.blocklist[index]
                .updateParentBottle(old: sourceURL, new: newBottleDir)
        }

        // Explicitly save settings to ensure all modifications are persisted
        // (modifying nested struct properties may not always trigger didSet)
        newBottle.saveBottleSettings()

        // Phase: finalizing
        progress?(.finalizing)

        // Register the new bottle
        registry.bottlePaths.append(newBottleDir)
        registry.loadBottles()

        return newBottleDir
    }

    /// Returns a duplicate name following the Finder convention.
    ///
    /// - If no existing bottle is named "\(baseName) Copy", returns "\(baseName) Copy".
    /// - Otherwise tries "\(baseName) Copy 2", "Copy 3", etc.
    ///
    /// - Parameters:
    ///   - baseName: The original bottle's name.
    ///   - existingNames: Names of all current bottles.
    /// - Returns: The next available duplicate name.
    public static func nextDuplicateName(baseName: String, existingNames: [String]) -> String {
        let candidate = "\(baseName) Copy"
        if !existingNames.contains(candidate) {
            return candidate
        }
        var counter = 2
        while existingNames.contains("\(baseName) Copy \(counter)") {
            counter += 1
        }
        return "\(baseName) Copy \(counter)"
    }

    // MARK: - Remove

    /// Removes the bottle at `url` from the registry, optionally deleting its
    /// files from disk.
    ///
    /// Callers are responsible for stopping any running processes first; this
    /// is only the delete-and-deregister step.
    ///
    /// Deleting the files also forgets any Steam game routes pointing at the
    /// bottle, since they can never resolve again. Removing the bottle from
    /// the list while keeping its files leaves routes in place: the bottle can
    /// come back through re-import, and resolution ignores routes to bottles
    /// it doesn't know. A failed deletion keeps the routes, matching the kept
    /// registry entry.
    ///
    /// - Parameters:
    ///   - url: The bottle's directory.
    ///   - deleteFiles: Whether to delete the bottle directory from disk.
    ///   - registry: The registry that owns the bottle list.
    ///   - routing: The Steam route store to prune. Defaults to the real one.
    @MainActor
    public static func remove(
        bottleAt url: URL,
        deleteFiles: Bool,
        registry: BottleRegistry,
        routing: GameRouting = GameRouting()
    ) {
        do {
            if let bottle = registry.bottle(for: url) {
                bottle.inFlight = true
            }

            if deleteFiles {
                try FileManager.default.removeItem(at: url)
                routing.removeRoutes(toBottle: url)
            }

            if let path = registry.bottlePaths.firstIndex(of: url) {
                registry.bottlePaths.remove(at: path)
            }
            registry.loadBottles()
        } catch {
            Logger.wineKit.error("Failed to remove bottle: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    /// The error thrown when an operation's bottle has no live instance in the
    /// registry.
    private static func bottleNotFoundError() -> NSError {
        NSError(
            domain: "com.franke.Whisky",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Bottle not found"]
        )
    }

    /// Calculates the total allocated size of a directory tree.
    private static func calculateDirectorySize(at url: URL) -> Int64 {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        )
        else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey]),
               let size = values.totalFileAllocatedSize {
                total += Int64(size)
            }
        }
        return total
    }

    /// Removes transient artifacts from a cloned bottle directory.
    ///
    /// Deletes old log files, diagnosis history sidecars, and temp files so the
    /// duplicate starts clean.
    private static func removeTransientArtifacts(in bottleDir: URL) {
        let fileManager = FileManager.default

        // Remove .log files from the logs directory
        let logsDir = bottleDir.appending(path: "logs")
        if let logEnumerator = fileManager.enumerator(
            at: logsDir,
            includingPropertiesForKeys: nil,
            options: [.skipsSubdirectoryDescendants]
        ) {
            for case let fileURL as URL in logEnumerator where fileURL.pathExtension == "log" {
                try? fileManager.removeItem(at: fileURL)
            }
        }

        // Remove diagnosis history sidecar files
        if let enumerator = fileManager.enumerator(
            at: bottleDir,
            includingPropertiesForKeys: nil,
            options: []
        ) {
            for case let fileURL as URL in enumerator
                where fileURL.lastPathComponent.hasSuffix(".diagnosis-history.plist") {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }
}
