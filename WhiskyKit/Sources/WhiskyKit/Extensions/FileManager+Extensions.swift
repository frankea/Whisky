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
    /// Replaces each DLL in `destinationDirectory` that `sourceDirectory` also
    /// holds with the source's copy (``replaceFile(at:with:makeOriginalCopy:)``).
    ///
    /// - Parameters:
    ///   - destinationDirectory: The folder whose DLLs are replaced.
    ///   - sourceDirectory: The folder the replacements come from.
    ///   - makeOriginalCopy: Whether to keep each original as `<name>.orig`.
    ///   - excluding: DLL file names to leave as they are, compared without
    ///     case: a slot something else fills, such as the `d3d11.dll` a bottle
    ///     on the Rockstar launcher's swapped layout takes from Wine.
    func replaceDLLs(
        in destinationDirectory: URL, withContentsIn sourceDirectory: URL, makeOriginalCopy: Bool = false,
        excluding: Set<String> = []
    ) throws {
        let excluded = Set(excluding.map { $0.lowercased() })
        let enumerator = FileManager.default.enumerator(
            at: sourceDirectory, includingPropertiesForKeys: [.isRegularFileKey]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            // Skip non-DLL entries and keep scanning. The enumerator is
            // recursive, so it also yields subdirectory URLs and stray files
            // (.DS_Store, license text). Using `return` here would abort the
            // whole copy on the first such entry, silently leaving later DLLs
            // uninstalled.
            guard fileURL.pathExtension == "dll", !excluded.contains(fileURL.lastPathComponent.lowercased())
            else { continue }
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
        removeLegacyTemp(beside: destinationURL)
        let tempURL = uniqueTempURL(beside: destinationURL)
        do {
            try copyItem(at: sourceURL, to: tempURL)
            try moveIntoPlace(tempURL, over: destinationURL)
        } catch {
            try? removeItem(at: tempURL)
            throw error
        }
    }

    /// A temp path beside `url` that no other install can be using.
    ///
    /// Two launches in one bottle can install the same DLL at once. With one
    /// fixed name, the second would clear or overwrite the first's temp while
    /// it was still being written, and the first could then rename a
    /// half-copied file into the system directory. A name of its own per
    /// install makes each temp private to the call that made it.
    func uniqueTempURL(beside url: URL) -> URL {
        url.appendingPathExtension("whisky-tmp-\(UUID().uuidString)")
    }

    /// Removes the fixed-name temp (`<name>.whisky-tmp`) an interrupted
    /// install from an earlier version could leave beside `url`. Nothing
    /// writes that name any more, so removing it never races a live install.
    func removeLegacyTemp(beside url: URL) {
        try? removeItem(at: url.appendingPathExtension("whisky-tmp"))
    }

    /// Moves `tempURL` over `destinationURL` with a single `rename(2)`.
    ///
    /// `rename` swaps the directory entry in one step, so the destination
    /// path names either the old file or the new one and is never absent.
    /// It also replaces whatever the entry is: a symlink (a bottle where
    /// DXVK's own `setup_dxvk.sh --symlink` linked its DLLs in) or a
    /// read-only file, needing only write access to the directory.
    /// `replaceItemAt` refuses both, and on the DXVK path a refused swap
    /// fails the launch where removing and copying used to work. A hard
    /// link elsewhere keeps its own contents, since only this entry moves.
    ///
    /// Both paths have to be on one volume, which a temp file created beside
    /// the destination always is.
    ///
    /// - Parameters:
    ///   - tempURL: The finished file to move into place.
    ///   - destinationURL: The path it takes over, present or not.
    /// - Throws: The `POSIXError` `rename` failed with, for example when the
    ///   destination is a directory.
    func moveIntoPlace(_ tempURL: URL, over destinationURL: URL) throws {
        let status = Darwin.rename(
            tempURL.path(percentEncoded: false), destinationURL.path(percentEncoded: false)
        )
        guard status == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
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
    /// under a temp name of its own (``uniqueTempURL(beside:)``) and moved over it with a single `rename`
    /// (see ``moveIntoPlace(_:over:)``), so a crash or a failed copy part way
    /// through leaves the original in place rather than a system directory
    /// without the DLL. The temp is removed when anything fails. A symlink or
    /// a read-only file at the destination is replaced like any other, as it
    /// was when the original was removed before the copy.
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
