//
//  WhiskyWineInstaller+Staging.swift
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
import os

private let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "WhiskyWineInstaller")

extension WhiskyWineInstaller {
    /// Name prefix of the staging folders ``install(tarball:into:moveItem:)``
    /// creates in its destination; a UUID follows it.
    static let stagingFolderPrefix = ".runtime-staging-"

    /// Where a staging folder holds the runtime an install retired.
    static let retiredRuntimeName = "Libraries.previous"

    /// Where stale-staging cleanup moves an unusable `Libraries/` aside so the
    /// retired runtime can go back in its place.
    static let unusableRuntimeName = "Libraries.unusable"

    /// Removes the staging folders an earlier install left in `destination`
    /// after a force-quit or a failed restore. Only folders named exactly as
    /// ``install(tarball:into:moveItem:)`` names them are touched.
    ///
    /// When a staging folder still holds the previous runtime and `destination`
    /// has no usable one (by ``isRuntimePresent(inLibraryFolder:)``), that
    /// runtime is moved back first. Whatever sits at `Libraries/` without being
    /// usable, such as folders another writer re-created between the two
    /// renames of an install, is moved into the staging folder to make room.
    /// A folder whose runtime can't be moved back is kept, so the only copy is
    /// never deleted.
    static func cleanUpStaleStaging(
        in destination: URL,
        moveItem: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }
    ) {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: destination.path(percentEncoded: false))
        else { return }
        let runtime = destination.appending(path: "Libraries")
        var restored = false

        for name in names where isStagingFolderName(name) {
            let folder = destination.appending(path: name)
            let retired = folder.appending(path: retiredRuntimeName)
            if fileManager.fileExists(atPath: retired.path(percentEncoded: false)),
               !isRuntimePresent(inLibraryFolder: runtime) {
                // One restore per pass: a second would only swap one retired
                // copy for another, deleting the first.
                guard !restored, restoreRetiredRuntime(from: folder, to: runtime, moveItem: moveItem)
                else { continue }
                restored = true
            }
            do {
                try fileManager.removeItem(at: folder)
            } catch {
                logger.warning("Could not remove stale staging folder \(name): \(error.localizedDescription)")
            }
        }
    }

    /// Moves the runtime retired into `folder` back to `runtime`, first moving
    /// anything already at `runtime` into `folder`.
    ///
    /// - Returns: Whether the retired runtime is back in place. When it isn't,
    ///   `folder` still holds it and must be kept.
    private static func restoreRetiredRuntime(
        from folder: URL,
        to runtime: URL,
        moveItem: (URL, URL) throws -> Void
    ) -> Bool {
        let fileManager = FileManager.default
        let name = folder.lastPathComponent
        if fileManager.fileExists(atPath: runtime.path(percentEncoded: false)) {
            let unusable = folder.appending(path: unusableRuntimeName)
            // Left by an earlier cleanup that got this far; it isn't a runtime.
            try? fileManager.removeItem(at: unusable)
            do {
                try moveItem(runtime, unusable)
            } catch {
                logger.error("""
                Could not move the unusable runtime aside to restore the previous one from \(name): \
                \(error.localizedDescription)
                """)
                return false
            }
        }
        do {
            try moveItem(folder.appending(path: retiredRuntimeName), runtime)
            logger.notice("Restored the previous runtime from \(name)")
            return true
        } catch {
            logger.error("Could not restore the previous runtime from \(name): \(error.localizedDescription)")
            return false
        }
    }

    /// Whether `name` is a staging folder name this installer creates: the
    /// prefix followed by a UUID and nothing else.
    static func isStagingFolderName(_ name: String) -> Bool {
        guard name.hasPrefix(stagingFolderPrefix) else { return false }
        return UUID(uuidString: String(name.dropFirst(stagingFolderPrefix.count))) != nil
    }
}
