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
    ///
    /// The replace is non-destructive on failure: the source is copied to a
    /// sibling temp file first and only swapped into place once the copy
    /// succeeds, so an unreadable source or an interrupted copy can never leave
    /// the destination missing (which would degrade even unrelated launches
    /// when the destination is a shared runtime file).
    func installFile(at destinationURL: URL, from sourceURL: URL) throws {
        guard fileExists(atPath: destinationURL.path(percentEncoded: false)) else {
            try copyItem(at: sourceURL, to: destinationURL)
            return
        }
        let tempURL = destinationURL.appendingPathExtension("whisky-tmp")
        if fileExists(atPath: tempURL.path(percentEncoded: false)) {
            try removeItem(at: tempURL)
        }
        do {
            try copyItem(at: sourceURL, to: tempURL)
            _ = try replaceItemAt(destinationURL, withItemAt: tempURL)
        } catch {
            try? removeItem(at: tempURL)
            throw error
        }
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

    /// Replaces the file at `originalURL` with a copy of `replacementURL`, but
    /// only when there is a file there to replace. A missing destination is
    /// left missing: this is how DXVK's DLLs go over Wine's own placeholders,
    /// and a slot the prefix never had is not one to invent.
    ///
    /// The swap is atomic. The replacement is copied beside the original
    /// under a `.whisky-tmp` name and moved over it with a single
    /// `replaceItemAt`, so a crash or a failed copy part way through leaves
    /// the original in place rather than a system directory without the DLL.
    /// The temp is removed when anything fails.
    ///
    /// - Parameters:
    ///   - originalURL: The file to replace.
    ///   - replacementURL: The file to copy over it.
    ///   - makeOriginalCopy: Whether to keep the original beside it as
    ///     `<name>.orig`, replacing any earlier backup.
    func replaceFile(at originalURL: URL, with replacementURL: URL, makeOriginalCopy: Bool = true) throws {
        guard fileExists(atPath: originalURL.path(percentEncoded: false)) else { return }
        if makeOriginalCopy {
            let copyURL = originalURL.appendingPathExtension("orig")
            if fileExists(atPath: copyURL.path(percentEncoded: false)) {
                try removeItem(at: copyURL)
            }
            // A copy, not a move: the original has to stay in place until the
            // replacement is ready to take its slot.
            try copyItem(at: originalURL, to: copyURL)
        }
        try installFile(at: originalURL, from: replacementURL)
    }
}
