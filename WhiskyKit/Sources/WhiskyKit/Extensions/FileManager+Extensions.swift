//
//  FileManager+Extensions.swift
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

extension FileManager {
    func replaceDLLs(
        in destinationDirectory: URL, withContentsIn sourceDirectory: URL, makeOriginalCopy: Bool = false
    ) throws {
        let enumerator = FileManager.default.enumerator(
            at: sourceDirectory, includingPropertiesForKeys: [.isRegularFileKey]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            // Skip non-DLL entries and keep scanning. The enumerator is
            // recursive, so it also yields subdirectory URLs and stray files
            // (.DS_Store, license text). Using `return` here would abort the
            // whole copy on the first such entry, silently leaving later DLLs
            // uninstalled.
            guard fileURL.pathExtension == "dll" else { continue }
            let originalURL = destinationDirectory.appending(path: fileURL.lastPathComponent)
            try FileManager.default.replaceFile(at: originalURL, with: fileURL, makeOriginalCopy: makeOriginalCopy)
        }
    }

    /// Installs `sourceURL` at `destinationURL`, replacing any existing file —
    /// unlike ``replaceFile(at:with:makeOriginalCopy:)``, the copy also happens
    /// when the destination does not exist yet. A silently skipped install
    /// would leave a translation layer half-deployed with no error.
    func installFile(at destinationURL: URL, from sourceURL: URL) throws {
        if fileExists(atPath: destinationURL.path(percentEncoded: false)) {
            try removeItem(at: destinationURL)
        }
        try copyItem(at: sourceURL, to: destinationURL)
    }

    /// Installs `sourceURL` at `destinationURL` only when the destination is
    /// missing or its contents differ. Returns `true` when a copy happened.
    /// Used for idempotent placement of runtime components that a runtime
    /// update may revert (the installer replaces all of `Libraries/`).
    @discardableResult
    func installFileIfContentDiffers(at destinationURL: URL, from sourceURL: URL) throws -> Bool {
        if fileExists(atPath: destinationURL.path(percentEncoded: false)),
           let existing = try? Data(contentsOf: destinationURL),
           let replacement = try? Data(contentsOf: sourceURL),
           existing == replacement {
            return false
        }
        try installFile(at: destinationURL, from: sourceURL)
        return true
    }

    func replaceFile(at originalURL: URL, with replacementURL: URL, makeOriginalCopy: Bool = true) throws {
        if fileExists(atPath: originalURL.path(percentEncoded: false)) {
            if makeOriginalCopy {
                let copyURL = originalURL.appendingPathExtension("orig")

                if fileExists(atPath: copyURL.path(percentEncoded: false)) {
                    try FileManager.default.removeItem(at: copyURL)
                }

                try FileManager.default.moveItem(at: originalURL, to: copyURL)
            } else {
                try FileManager.default.removeItem(at: originalURL)
            }

            try FileManager.default.copyItem(at: replacementURL, to: originalURL)
        }
    }
}
