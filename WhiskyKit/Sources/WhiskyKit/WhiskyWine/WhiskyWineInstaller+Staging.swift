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

    /// Removes the staging folders an earlier install left in `destination`
    /// after a force-quit or a failed restore. Only folders named exactly as
    /// ``install(tarball:into:moveItem:)`` names them are touched.
    ///
    /// When `destination` has no runtime and a staging folder still holds the
    /// previous one, that runtime is moved back first. A folder whose runtime
    /// can't be moved back is kept, so the only copy is never deleted.
    static func cleanUpStaleStaging(
        in destination: URL,
        moveItem: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }
    ) {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: destination.path(percentEncoded: false))
        else { return }
        let runtime = destination.appending(path: "Libraries")

        for name in names where isStagingFolderName(name) {
            let folder = destination.appending(path: name)
            let retired = folder.appending(path: retiredRuntimeName)
            if !fileManager.fileExists(atPath: runtime.path(percentEncoded: false)),
               fileManager.fileExists(atPath: retired.path(percentEncoded: false)) {
                do {
                    try moveItem(retired, runtime)
                    logger.notice("Restored the previous runtime from \(name)")
                } catch {
                    logger.error("Could not restore the previous runtime from \(name): \(error.localizedDescription)")
                    continue
                }
            }
            do {
                try fileManager.removeItem(at: folder)
            } catch {
                logger.warning("Could not remove stale staging folder \(name): \(error.localizedDescription)")
            }
        }
    }

    /// Whether `name` is a staging folder name this installer creates: the
    /// prefix followed by a UUID and nothing else.
    static func isStagingFolderName(_ name: String) -> Bool {
        guard name.hasPrefix(stagingFolderPrefix) else { return false }
        return UUID(uuidString: String(name.dropFirst(stagingFolderPrefix.count))) != nil
    }
}
