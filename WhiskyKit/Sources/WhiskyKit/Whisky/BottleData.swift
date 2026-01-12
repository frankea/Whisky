//
//  BottleData.swift
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
import SemanticVersion

// Minimal BottleData for fallback encoding
private struct BottleDataMinimal: Codable {
    var paths: [URL]
}

// MARK: - BottleData

public struct BottleData: Codable {
    public static let containerDir = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library")
        .appending(path: "Containers")
        .appending(path: Bundle.whiskyBundleIdentifier)

    public static let bottleEntriesDir = containerDir
        .appending(path: "BottleVM")
        .appendingPathExtension("plist")

    public static let defaultBottleDir = containerDir
        .appending(path: "Bottles")

    static let currentVersion = SemanticVersion(1, 0, 0)

    private var fileVersion: SemanticVersion
    public var paths: [URL] = [] {
        didSet {
            encode()
        }
    }

    public init() {
        fileVersion = Self.currentVersion

        if !decode() {
            encode()
        }
    }

    @MainActor
    public mutating func loadBottles() -> [Bottle] {
        var bottles: [Bottle] = []

        for path in paths {
            let bottleMetadata = path
                .appending(path: "Metadata")
                .appendingPathExtension("plist")
                .path(percentEncoded: false)

            if FileManager.default.fileExists(atPath: bottleMetadata) {
                bottles.append(Bottle(bottleUrl: path, isAvailable: true))
            } else {
                bottles.append(Bottle(bottleUrl: path))
            }
        }

        return bottles
    }

    @discardableResult
    private mutating func decode() -> Bool {
        let decoder = PropertyListDecoder()
        do {
            let data = try Data(contentsOf: Self.bottleEntriesDir)
            self = try decoder.decode(BottleData.self, from: data)
            let loadedVersion = self.fileVersion
            let currentVersion = Self.currentVersion
            if loadedVersion != currentVersion {
                Logger.wineKit.warning("Invalid file version \(loadedVersion), expected \(currentVersion)")
                return false
            }
            return true
        } catch {
            Logger.wineKit.error("Failed to decode BottleData: \(error)")
            return false
        }
    }

    @discardableResult
    private func encode() -> Bool {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml

        do {
            try FileManager.default.createDirectory(at: Self.containerDir, withIntermediateDirectories: true)
            let data = try encoder.encode(self)
            try data.write(to: Self.bottleEntriesDir, options: .atomic)
            return true
        } catch {
            Logger.wineKit.error("Failed to encode BottleData: \(error)")
            // Try alternative encoding without version check
            return encodeFallback()
        }
    }

    private func encodeFallback() -> Bool {
        // Fallback: try to recover existing paths and save minimal data
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml

        do {
            try FileManager.default.createDirectory(at: Self.containerDir, withIntermediateDirectories: true)
            // Create a minimal BottleData with just the paths
            let fallbackData = BottleDataMinimal(paths: self.paths)
            let data = try encoder.encode(fallbackData)
            try data.write(to: Self.bottleEntriesDir, options: .atomic)
            return true
        } catch {
            Logger.wineKit.error("Failed to encode fallback BottleData: \(error)")
            return false
        }
    }
}
