//
//  DriveCRecordKey.swift
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

/// The paths a record in a bottle keeps, relative to the bottle's `drive_c`.
///
/// Such a record sits in the bottle, where anyone can edit it or ship it in
/// a shared bottle, and its paths are what Whisky later replaces or removes.
/// Every loader drops the entries this refuses before any code uses them.
enum DriveCRecordKey {
    /// Whether `key` names a path inside `driveC`, as every key Whisky writes
    /// does: relative, `/`-separated, with no empty, `.` or `..` component, no
    /// backslash and no control character, and still inside `driveC` once
    /// symbolic links are followed. Wine links `drive_c/users/<name>/Documents`
    /// and its siblings into the Mac's home folder, so a key that is clean on
    /// its face can still lead out of the bottle.
    static func isContained(_ key: String, in driveC: URL) -> Bool {
        let components = key.split(separator: "/", omittingEmptySubsequences: false)
        guard !key.isEmpty, !key.contains("\\"),
              !key.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else { return false }
        let root = resolvedPath(driveC)
        let resolved = resolvedPath(driveC.appending(path: key))
        return resolved.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    /// `url` with symbolic links followed in its deepest part that exists.
    /// `resolvingSymlinksInPath()` gives up on a path whose last part does
    /// not exist yet, which would let a missing file under a linked folder
    /// pass for one inside the bottle.
    private static func resolvedPath(_ url: URL) -> String {
        var existing = url.standardizedFileURL
        var rest: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path(percentEncoded: false)),
              existing.pathComponents.count > 1 {
            rest.insert(existing.lastPathComponent, at: 0)
            existing.deleteLastPathComponent()
        }
        var resolved = existing.resolvingSymlinksInPath()
        for component in rest {
            resolved.append(path: component)
        }
        return resolved.standardizedFileURL.path(percentEncoded: false)
    }
}
