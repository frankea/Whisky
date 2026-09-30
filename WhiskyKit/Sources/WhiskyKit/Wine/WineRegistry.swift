//
//  WineRegistry.swift
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

public enum RegistryType: String {
    case binary = "REG_BINARY"
    case dword = "REG_DWORD"
    case qword = "REG_QWORD"
    case string = "REG_SZ"
}

/// Reads registry values straight from a prefix's `.reg` files, so callers
/// that cannot afford a Wine process (checks, previews) still see the
/// current state.
enum WineRegistryFile {
    static func readValue(bottleURL: URL, key: String, valueName: String) -> String? {
        guard let file = contents(for: key, bottleURL: bottleURL) else {
            return nil
        }
        let sectionHeader = file.sectionHeader

        let lines = file.text.components(separatedBy: "\n")
        var inSection = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("[") {
                inSection = trimmed.lowercased().hasPrefix(sectionHeader.lowercased())
                continue
            }

            if inSection, trimmed.hasPrefix("\"\(valueName)\"") {
                // Parse value: "valueName"="value" or "valueName"=dword:00000001
                if let equalsIndex = trimmed.firstIndex(of: "=") {
                    let rawValue = String(trimmed[trimmed.index(after: equalsIndex)...])
                        .trimmingCharacters(in: .whitespaces)
                    // Strip surrounding quotes if present
                    if rawValue.hasPrefix("\""), rawValue.hasSuffix("\"") {
                        return String(rawValue.dropFirst().dropLast())
                    }
                    return rawValue
                }
            }
        }

        return nil
    }

    /// The names of the values set directly under `key`, or `nil` when the
    /// hive's `.reg` file is missing or unreadable.
    ///
    /// A name comes back as the file spells it. Wine writes one verbatim
    /// unless it holds a quote, a backslash or a non-ASCII character, which
    /// it escapes, so a plain ASCII name can be looked up as is.
    static func valueNames(bottleURL: URL, key: String) -> Set<String>? {
        guard let file = contents(for: key, bottleURL: bottleURL) else {
            return nil
        }

        var names: Set<String> = []
        var inSection = false
        for line in file.text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                inSection = trimmed.lowercased().hasPrefix(file.sectionHeader.lowercased())
                continue
            }
            if inSection, let name = quotedName(in: trimmed) {
                names.insert(name)
            }
        }
        return names
    }

    /// The `.reg` file that holds `key`, and the section header `key` has in it.
    private static func contents(for key: String, bottleURL: URL) -> (text: String, sectionHeader: String)? {
        let regFileName: String
        if key.hasPrefix("HKCU") || key.hasPrefix("HKEY_CURRENT_USER") {
            regFileName = "user.reg"
        } else if key.hasPrefix("HKLM") || key.hasPrefix("HKEY_LOCAL_MACHINE") {
            regFileName = "system.reg"
        } else {
            return nil
        }

        let regFileURL = bottleURL.appending(path: regFileName)
        guard let content = try? String(contentsOf: regFileURL, encoding: .utf8) else {
            return nil
        }

        // Normalize the key path for .reg file format
        // HKCU\Software\Wine\Drivers -> [Software\\Wine\\Drivers]
        let normalizedKey = key
            .replacingOccurrences(of: "HKCU\\", with: "")
            .replacingOccurrences(of: "HKEY_CURRENT_USER\\", with: "")
            .replacingOccurrences(of: "HKLM\\", with: "")
            .replacingOccurrences(of: "HKEY_LOCAL_MACHINE\\", with: "")
            .replacingOccurrences(of: "\\", with: "\\\\")

        return (content, "[" + normalizedKey + "]")
    }

    /// The name a `"name"=...` line sets, spelled as in the file, or `nil`
    /// for any other line. An escaped quote does not end the name.
    private static func quotedName(in line: String) -> String? {
        guard line.hasPrefix("\"") else {
            return nil
        }
        var name = ""
        var escaping = false
        for character in line.dropFirst() {
            if !escaping, character == "\"" {
                return name
            }
            escaping = !escaping && character == "\\"
            name.append(character)
        }
        return nil
    }
}

public extension Wine {
    private enum RegistryKey: String {
        case currentVersion = #"HKLM\Software\Microsoft\Windows NT\CurrentVersion"#
        case macDriver = #"HKCU\Software\Wine\Mac Driver"#
        case desktop = #"HKCU\Control Panel\Desktop"#
        case explorer = #"HKCU\Software\Wine\Explorer"#
        case explorerDesktops = #"HKCU\Software\Wine\Explorer\Desktops"#
    }

    @MainActor
    static func addRegistryKey(
        bottle: Bottle, key: String, name: String, data: String, type: RegistryType
    ) async throws {
        try await runWine(
            ["reg", "add", key, "-v", name, "-t", type.rawValue, "-d", data, "-f"],
            bottle: bottle
        )
    }

    @MainActor
    static func deleteRegistryValue(
        bottle: Bottle, key: String, name: String
    ) async throws {
        try await runWine(["reg", "delete", key, "/v", name, "/f"], bottle: bottle)
    }

    @MainActor
    static func queryRegistryKey(
        bottle: Bottle, key: String, name: String, type: RegistryType
    ) async throws -> String? {
        let output = try await runWine(["reg", "query", key, "-v", name], bottle: bottle)
        let lines = output.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)

        guard let line = lines.first(where: { $0.contains(type.rawValue) }) else { return nil }
        let array = line.split(omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
        guard let value = array.last else { return nil }
        return String(value)
    }

    @MainActor
    static func changeBuildVersion(bottle: Bottle, version: Int) async throws {
        try await addRegistryKey(
            bottle: bottle,
            key: RegistryKey.currentVersion.rawValue,
            name: "CurrentBuild",
            data: "\(version)",
            type: .string
        )
        try await addRegistryKey(
            bottle: bottle,
            key: RegistryKey.currentVersion.rawValue,
            name: "CurrentBuildNumber",
            data: "\(version)",
            type: .string
        )
    }

    @MainActor
    static func winVersion(bottle: Bottle) async throws -> WinVersion {
        let output = try await Wine.runWine(["winecfg", "-v"], bottle: bottle)
        let lines = output.split(whereSeparator: \.isNewline)

        if let lastLine = lines.last {
            let winString = String(lastLine)

            if let version = WinVersion(rawValue: winString) {
                return version
            }
        }

        throw WineInterfaceError.invalidResponse
    }

    @MainActor
    static func buildVersion(bottle: Bottle) async throws -> String? {
        try await Wine.queryRegistryKey(
            bottle: bottle, key: RegistryKey.currentVersion.rawValue,
            name: "CurrentBuild", type: .string
        )
    }

    @MainActor
    static func retinaMode(bottle: Bottle) async throws -> Bool? {
        guard let output = try await Wine.queryRegistryKey(
            bottle: bottle, key: RegistryKey.macDriver.rawValue, name: "RetinaMode", type: .string
        )
        else {
            return nil
        }
        switch output {
        case "y":
            return true
        case "n":
            return false
        default:
            return nil
        }
    }

    @MainActor
    static func changeRetinaMode(bottle: Bottle, retinaMode: Bool) async throws {
        try await Wine.addRegistryKey(
            bottle: bottle, key: RegistryKey.macDriver.rawValue, name: "RetinaMode", data: retinaMode ? "y" : "n",
            type: .string
        )
    }

    @MainActor
    static func dpiResolution(bottle: Bottle) async throws -> Int? {
        guard let output = try await Wine.queryRegistryKey(
            bottle: bottle,
            key: RegistryKey.desktop.rawValue,
            name: "LogPixels",
            type: .dword
        )
        else { return nil }

        let noPrefix = output.replacingOccurrences(of: "0x", with: "")
        let int = Int(noPrefix, radix: 16)
        guard let int else { return nil }
        return int
    }

    @MainActor
    static func changeDpiResolution(bottle: Bottle, dpi: Int) async throws {
        try await Wine.addRegistryKey(
            bottle: bottle, key: RegistryKey.desktop.rawValue, name: "LogPixels", data: String(dpi),
            type: .dword
        )
    }

    @discardableResult
    @MainActor
    static func control(bottle: Bottle) async throws -> String {
        try await Wine.runWine(["control"], bottle: bottle)
    }

    @discardableResult
    @MainActor
    static func regedit(bottle: Bottle) async throws -> String {
        try await Wine.runWine(["regedit"], bottle: bottle)
    }

    @discardableResult
    @MainActor
    static func cfg(bottle: Bottle) async throws -> String {
        try await Wine.runWine(["winecfg"], bottle: bottle)
    }

    @discardableResult
    @MainActor
    static func changeWinVersion(bottle: Bottle, win: WinVersion) async throws -> String {
        try await Wine.runWine(["winecfg", "-v", win.rawValue], bottle: bottle)
    }

    // MARK: - Virtual Desktop

    /// Enables Wine's virtual desktop mode with the given resolution.
    ///
    /// Writes two registry values:
    /// - `Desktop = "Default"` in `HKCU\Software\Wine\Explorer`
    /// - `Default = "{width}x{height}"` in `HKCU\Software\Wine\Explorer\Desktops`
    ///
    /// - Parameters:
    ///   - bottle: The bottle whose registry to modify.
    ///   - resolution: A resolution string like `"1920x1080"`.
    @MainActor
    static func enableVirtualDesktop(bottle: Bottle, resolution: String) async throws {
        try await addRegistryKey(
            bottle: bottle,
            key: RegistryKey.explorer.rawValue,
            name: "Desktop",
            data: "Default",
            type: .string
        )
        try await addRegistryKey(
            bottle: bottle,
            key: RegistryKey.explorerDesktops.rawValue,
            name: "Default",
            data: resolution,
            type: .string
        )
    }

    /// Disables Wine's virtual desktop mode by removing the Desktop value.
    ///
    /// - Parameter bottle: The bottle whose registry to modify.
    @MainActor
    static func disableVirtualDesktop(bottle: Bottle) async throws {
        do {
            try await runWine(
                ["reg", "delete", RegistryKey.explorer.rawValue, "-v", "Desktop", "-f"],
                bottle: bottle
            )
        } catch {
            // Key might not exist; this is expected on bottles that never had virtual desktop
        }
    }

    /// Queries whether Wine's virtual desktop is currently enabled and returns the resolution.
    ///
    /// - Parameter bottle: The bottle whose registry to query.
    /// - Returns: The resolution string (e.g., `"1920x1080"`) if virtual desktop is enabled, or `nil`.
    @MainActor
    static func queryVirtualDesktop(bottle: Bottle) async throws -> String? {
        guard let desktop = try await queryRegistryKey(
            bottle: bottle,
            key: RegistryKey.explorer.rawValue,
            name: "Desktop",
            type: .string
        ), !desktop.isEmpty
        else {
            return nil
        }
        // Desktop value is present -- query the resolution
        return try await queryRegistryKey(
            bottle: bottle,
            key: RegistryKey.explorerDesktops.rawValue,
            name: "Default",
            type: .string
        )
    }
}
