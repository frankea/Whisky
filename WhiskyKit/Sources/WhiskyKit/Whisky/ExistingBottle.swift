//
//  ExistingBottle.swift
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

/// Why a directory cannot be added as an existing bottle.
public enum ExistingBottleError: Error, Equatable {
    /// Nothing exists at the path.
    case notFound
    /// The path names a file, not a directory.
    case notADirectory
    /// The directory has no `Metadata.plist`, so it is not a bottle.
    case missingMetadata
    /// The directory's `Metadata.plist` could not be read as bottle settings.
    case unreadableMetadata
}

extension BottleData {
    /// Turns a path typed on the command line into an absolute bottle URL.
    ///
    /// Expands `~`, resolves a relative path against `currentDirectory`, and
    /// standardizes the result (no `..`, no trailing slash) so the registry
    /// holds the same form for a bottle however it was typed.
    ///
    /// - Parameters:
    ///   - path: The path as given.
    ///   - currentDirectory: The directory a relative path is resolved against.
    /// - Returns: The bottle directory's URL.
    public static func bottleURL(forPath path: String, currentDirectory: String) -> URL {
        var fullPath = (path as NSString).expandingTildeInPath
        if !fullPath.hasPrefix("/") {
            fullPath = (currentDirectory as NSString).appendingPathComponent(fullPath)
        }
        return URL(filePath: (fullPath as NSString).standardizingPath)
    }

    /// Reads the settings of an existing bottle directory **without writing anything**.
    ///
    /// A bottle is a directory holding a `Metadata.plist`. The plist is decoded
    /// directly rather than through ``BottleSettings/decode(from:)``, which
    /// creates a missing file and rewrites one from another app version: adding
    /// a bottle must neither turn an arbitrary path into one nor change the
    /// bottle it registers.
    ///
    /// - Parameter bottleURL: The bottle directory.
    /// - Returns: The bottle's settings.
    /// - Throws: ``ExistingBottleError`` when the directory is not a readable bottle.
    public static func existingBottleSettings(at bottleURL: URL) throws -> BottleSettings {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: bottleURL.path(percentEncoded: false), isDirectory: &isDirectory)
        else { throw ExistingBottleError.notFound }
        guard isDirectory.boolValue else { throw ExistingBottleError.notADirectory }

        let metadataURL = bottleURL.appending(path: "Metadata").appendingPathExtension("plist")
        guard FileManager.default.fileExists(atPath: metadataURL.path(percentEncoded: false)) else {
            throw ExistingBottleError.missingMetadata
        }
        guard let data = try? Data(contentsOf: metadataURL),
              let settings = try? PropertyListDecoder().decode(BottleSettings.self, from: data)
        else { throw ExistingBottleError.unreadableMetadata }
        return settings
    }
}
