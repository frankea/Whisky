//
//  SteamAppManifest.swift
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

/// Utilities for extracting Steam App IDs from manifest files.
///
/// Steam stores application metadata in ACF/VDF format files alongside
/// installed games. This enum provides methods to parse those files and
/// locate Steam App IDs within a Wine bottle or executable directory.
///
/// ## ACF Format
///
/// Valve's ACF (App Cache File) format uses `"key"\t\t"value"` pairs:
/// ```
/// "AppState"
/// {
///     "appid"     "1245620"
///     "name"      "Elden Ring"
/// }
/// ```
public enum SteamAppManifest {
    /// Parses a Steam App ID from ACF/VDF format text.
    ///
    /// Looks for a `"appid"` key followed by its value in Valve's
    /// key-value format. Handles varying amounts of whitespace and
    /// tab indentation.
    ///
    /// - Parameter text: The raw text content of an ACF/VDF file.
    /// - Returns: The parsed App ID, or `nil` if not found.
    public static func parseAppId(from text: String) -> Int? {
        // Match "appid" followed by whitespace and a quoted integer value.
        // ACF format: "key"<whitespace>"value"
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Check if this line contains the appid key
            guard trimmed.lowercased().contains("\"appid\"") else { continue }

            // Extract the value: find all quoted strings on this line
            var quotedValues: [String] = []
            var inQuote = false
            var current = ""
            for char in trimmed {
                if char == "\"" {
                    if inQuote {
                        quotedValues.append(current)
                        current = ""
                    }
                    inQuote.toggle()
                } else if inQuote {
                    current.append(char)
                }
            }

            // The second quoted string is the value
            guard quotedValues.count >= 2 else { continue }
            return Int(quotedValues[1])
        }
        return nil
    }

    /// Searches a Wine bottle for Steam App ID by scanning manifest files.
    ///
    /// Looks for `appmanifest_*.acf` files in the standard Steam library
    /// directory within the bottle's `drive_c`. Also checks for
    /// `steam_appid.txt` in common locations.
    ///
    /// - Parameter bottleURL: The root URL of the Wine bottle.
    /// - Returns: The first App ID found, or `nil` if none found.
    public static func findAppId(in bottleURL: URL) -> Int? {
        let steamAppsDir = bottleURL
            .appending(path: "drive_c/Program Files (x86)/Steam/steamapps")

        let fileManager = FileManager.default
        let steamAppsPath = steamAppsDir.path(percentEncoded: false)

        guard fileManager.fileExists(atPath: steamAppsPath) else { return nil }

        // Scan for appmanifest_*.acf files
        guard let contents = try? fileManager.contentsOfDirectory(atPath: steamAppsPath) else {
            return nil
        }

        for filename in contents where filename.hasPrefix("appmanifest_") && filename.hasSuffix(".acf") {
            let fileURL = steamAppsDir.appending(path: filename)
            guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            if let appId = parseAppId(from: text) {
                return appId
            }
        }

        return nil
    }

    /// Searches for a Steam App ID near a specific executable.
    ///
    /// Checks for `steam_appid.txt` in the executable's directory and
    /// up to three parent directories. The file should contain a plain
    /// integer App ID.
    ///
    /// - Parameter exeURL: The URL to the game executable.
    /// - Returns: The parsed App ID, or `nil` if not found.
    public static func findAppIdForProgram(at exeURL: URL) -> Int? {
        let fileManager = FileManager.default
        var directory = exeURL.deletingLastPathComponent()

        // Check exe directory and up to 3 parent directories
        for _ in 0 ..< 4 {
            let appIdFile = directory.appending(path: "steam_appid.txt")
            let filePath = appIdFile.path(percentEncoded: false)

            if fileManager.fileExists(atPath: filePath),
               let text = try? String(contentsOf: appIdFile, encoding: .utf8) {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if let appId = Int(trimmed) {
                    return appId
                }
            }

            directory = directory.deletingLastPathComponent()
        }

        return nil
    }
}
