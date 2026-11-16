//
//  Wine+StrippedCopy.swift
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

extension Wine {
    /// Installs Wine's builtin at `source` into `destination` as a true native
    /// PE: a copy with the builtin marker stripped, so the loader runs this
    /// file instead of redirecting to whatever `lib/wine` holds.
    ///
    /// The destination is a DLL in a bottle's system directory, and a launch
    /// with that DLL missing fails outright. So the destination is never
    /// absent or half-written: the copy is made and stripped beside it under a
    /// temp name of its own and only then moved over it with a single `rename`
    /// (see `FileManager.moveIntoPlace(_:over:)`), which also replaces a
    /// symlink or a read-only file there. A failure at any step removes the
    /// temp and leaves the destination exactly as it was.
    ///
    /// The source has to carry the builtin marker. A native file at the source
    /// path is not Wine's build, and copying it in would put an unknown DLL in
    /// front of every program in the bottle.
    ///
    /// Callers run this on every launch, so a destination that already is the
    /// stripped copy of `source` is left alone rather than rewritten.
    ///
    /// - Parameters:
    ///   - destination: Where the native copy goes.
    ///   - source: Wine's builtin-marked DLL.
    /// - Throws: ``WineStrippedCopyError/sourceNotBuiltinMarked(_:)`` when the
    ///   source is missing or unmarked, or the file system error that stopped
    ///   the copy or the swap.
    static func installStrippedCopy(at destination: URL, from source: URL) throws {
        guard carriesBuiltinMarker(source) else {
            throw WineStrippedCopyError.sourceNotBuiltinMarked(source.lastPathComponent)
        }
        if isStrippedCopy(destination, of: source) {
            return
        }
        let fileManager = FileManager.default
        fileManager.removeLegacyTemp(beside: destination)
        let temp = fileManager.uniqueTempURL(beside: destination)
        do {
            // The file a symlinked source points at, not the link: `copyItem`
            // copies a link as a link, and the strip below would then write
            // through it into Wine's own DLL in the runtime.
            try fileManager.copyItem(at: source.resolvingSymlinksInPath(), to: temp)
            guard try fileManager.attributesOfItem(atPath: temp.path(percentEncoded: false))[.type]
                as? FileAttributeType == .typeRegular
            else {
                throw WineStrippedCopyError.sourceNotRegularFile(source.lastPathComponent)
            }
            try stripBuiltinMarker(at: temp)
            try fileManager.moveIntoPlace(temp, over: destination)
        } catch {
            try? fileManager.removeItem(at: temp)
            throw error
        }
    }
}

/// Errors thrown by ``Wine/installStrippedCopy(at:from:)``.
enum WineStrippedCopyError: LocalizedError, Equatable {
    /// The source is not a builtin-marked Wine DLL, so stripping it would not
    /// produce Wine's implementation as a native PE.
    case sourceNotBuiltinMarked(String)
    /// The copy of the source is not a regular file, so stripping it in place
    /// could write somewhere other than the copy.
    case sourceNotRegularFile(String)

    var errorDescription: String? {
        switch self {
        case let .sourceNotBuiltinMarked(name):
            "\(name) does not carry the Wine builtin marker"
        case let .sourceNotRegularFile(name):
            "\(name) is not a regular file"
        }
    }
}
