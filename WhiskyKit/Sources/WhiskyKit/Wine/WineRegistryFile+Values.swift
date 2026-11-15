//
//  WineRegistryFile+Values.swift
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

extension WineRegistryFile {
    /// The values set directly under `key`, by name, or `nil` when the hive's
    /// `.reg` file is missing or unreadable.
    ///
    /// Names come back spelled as in the file, as from ``valueNames(bottleURL:key:)``,
    /// and each value's data as the file writes it: a string in its quotes,
    /// escapes and all, or `dword:` and `hex:` data as is.
    static func rawValues(bottleURL: URL, key: String) -> [String: String]? {
        guard let file = contents(for: key, bottleURL: bottleURL) else {
            return nil
        }

        var values: [String: String] = [:]
        var inSection = false
        for line in file.text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                inSection = trimmed.lowercased().hasPrefix(file.sectionHeader.lowercased())
                continue
            }
            guard inSection, let name = quotedName(in: trimmed) else {
                continue
            }
            // Past the name, its two quotes and the `=` after them.
            values[name] = String(trimmed.dropFirst(name.count + 3))
        }
        return values
    }

    /// How Wine spells a value name in a `.reg` file it saves, so a name can
    /// be found among ``valueNames(bottleURL:key:)``.
    ///
    /// Wine puts a backslash before a quote or a backslash, and writes each
    /// UTF-16 unit past ASCII as a `\x` escape in lowercase hex, padded to four
    /// digits when a hex digit follows so the escape cannot run on into it
    /// (`dump_strW` in Wine's `server/unicode.c`).
    static func savedSpelling(of name: String) -> String {
        let units = Array(name.utf16)
        var spelling = ""
        for (index, unit) in units.enumerated() {
            guard unit < 128 else {
                let next = index + 1 < units.count ? units[index + 1] : nil
                let hexDigitFollows = next.map(isASCIIHexDigit) ?? false
                let digits = String(unit, radix: 16)
                let padding = hexDigitFollows ? String(repeating: "0", count: max(0, 4 - digits.count)) : ""
                spelling += #"\x"# + padding + digits
                continue
            }
            let character = Character(Unicode.Scalar(UInt8(unit)))
            if character == "\"" || character == "\\" {
                spelling.append("\\")
            }
            spelling.append(character)
        }
        return spelling
    }

    private static func isASCIIHexDigit(_ unit: UInt16) -> Bool {
        unit < 128 && Character(Unicode.Scalar(UInt8(unit))).isHexDigit
    }
}
