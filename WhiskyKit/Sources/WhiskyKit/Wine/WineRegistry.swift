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

enum RegistryType: String {
    case binary = "REG_BINARY"
    case dword = "REG_DWORD"
    case qword = "REG_QWORD"
    case string = "REG_SZ"
}

public extension Wine {
    private enum RegistryKey: String {
        case currentVersion = #"HKLM\Software\Microsoft\Windows NT\CurrentVersion"#
        case macDriver = #"HKCU\Software\Wine\Mac Driver"#
        case desktop = #"HKCU\Control Panel\Desktop"#
    }

    @MainActor
    private static func addRegistryKey(
        bottle: Bottle, key: String, name: String, data: String, type: RegistryType
    ) async throws {
        try await runWine(
            ["reg", "add", key, "-v", name, "-t", type.rawValue, "-d", data, "-f"],
            bottle: bottle
        )
    }

    @MainActor
    private static func queryRegistryKey(
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
    static func retinaMode(bottle: Bottle) async throws -> Bool {
        let values: Set<String> = ["y", "n"]
        guard let output = try await Wine.queryRegistryKey(
            bottle: bottle, key: RegistryKey.macDriver.rawValue, name: "RetinaMode", type: .string
        ), values.contains(output)
        else {
            try await changeRetinaMode(bottle: bottle, retinaMode: false)
            return false
        }
        return output == "y"
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
}
