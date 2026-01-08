//
//  TextTable.swift
//  WhiskyCmd
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

// MARK: - Terminal Display Width Calculation

/// Extension to calculate terminal display width for a string
/// This accounts for East Asian wide characters and emojis that occupy
/// two character cells in monospaced terminal output
extension String {
    /// Calculate the terminal display width of the string
    /// - Returns: The number of character cells this string occupies in a terminal
    var terminalWidth: Int {
        var width = 0
        for scalar in unicodeScalars {
            width += scalar.terminalCellWidth
        }
        return width
    }

    /// Pad the string to a specific terminal width
    /// - Parameters:
    ///   - targetWidth: The desired terminal display width
    ///   - padCharacter: The character to use for padding (default: space)
    /// - Returns: A string padded to the target terminal width
    func terminalPadding(toWidth targetWidth: Int, withPad padCharacter: Character = " ") -> String {
        let currentWidth = self.terminalWidth
        if currentWidth >= targetWidth {
            return self
        }
        let paddingNeeded = targetWidth - currentWidth
        return self + String(repeating: padCharacter, count: paddingNeeded)
    }
}

extension Unicode.Scalar {
    /// Determine the terminal cell width of a Unicode scalar
    /// Based on wcwidth behavior for terminal display
    /// - Returns: 0 for non-printing, 1 for normal, 2 for wide characters
    var terminalCellWidth: Int {
        let value = self.value

        // Non-printing characters (control characters, combining marks)
        if value < 32 || (value >= 0x7F && value < 0xA0) {
            return 0
        }

        // Combining diacritical marks and other zero-width characters
        if isCombiningMark || isZeroWidth {
            return 0
        }

        // East Asian Wide and Fullwidth characters
        if isEastAsianWide {
            return 2
        }

        // Default single-width
        return 1
    }

    /// Check if this scalar is a combining mark (zero-width)
    private var isCombiningMark: Bool {
        let value = self.value
        // Combining Diacritical Marks
        if value >= 0x0300 && value <= 0x036F { return true }
        // Combining Diacritical Marks Extended
        if value >= 0x1AB0 && value <= 0x1AFF { return true }
        // Combining Diacritical Marks Supplement
        if value >= 0x1DC0 && value <= 0x1DFF { return true }
        // Combining Diacritical Marks for Symbols
        if value >= 0x20D0 && value <= 0x20FF { return true }
        // Combining Half Marks
        if value >= 0xFE20 && value <= 0xFE2F { return true }
        return false
    }

    /// Check if this scalar is a zero-width character
    private var isZeroWidth: Bool {
        let value = self.value
        // Zero-width space, non-joiner, joiner
        if value == 0x200B || value == 0x200C || value == 0x200D { return true }
        // Word joiner
        if value == 0x2060 { return true }
        // Zero-width no-break space (BOM)
        if value == 0xFEFF { return true }
        // Variation selectors
        if value >= 0xFE00 && value <= 0xFE0F { return true }
        // Variation selectors supplement
        if value >= 0xE0100 && value <= 0xE01EF { return true }
        return false
    }

    /// Check if this scalar is East Asian Wide (occupies 2 cells)
    private var isEastAsianWide: Bool {
        let value = self.value

        // CJK Radicals Supplement
        if value >= 0x2E80 && value <= 0x2EFF { return true }
        // Kangxi Radicals
        if value >= 0x2F00 && value <= 0x2FDF { return true }
        // CJK Symbols and Punctuation
        if value >= 0x3000 && value <= 0x303F { return true }
        // Hiragana
        if value >= 0x3040 && value <= 0x309F { return true }
        // Katakana
        if value >= 0x30A0 && value <= 0x30FF { return true }
        // Bopomofo
        if value >= 0x3100 && value <= 0x312F { return true }
        // Hangul Compatibility Jamo
        if value >= 0x3130 && value <= 0x318F { return true }
        // Kanbun
        if value >= 0x3190 && value <= 0x319F { return true }
        // Bopomofo Extended
        if value >= 0x31A0 && value <= 0x31BF { return true }
        // CJK Strokes
        if value >= 0x31C0 && value <= 0x31EF { return true }
        // Katakana Phonetic Extensions
        if value >= 0x31F0 && value <= 0x31FF { return true }
        // Enclosed CJK Letters and Months
        if value >= 0x3200 && value <= 0x32FF { return true }
        // CJK Compatibility
        if value >= 0x3300 && value <= 0x33FF { return true }
        // CJK Unified Ideographs Extension A
        if value >= 0x3400 && value <= 0x4DBF { return true }
        // CJK Unified Ideographs
        if value >= 0x4E00 && value <= 0x9FFF { return true }
        // Yi Syllables
        if value >= 0xA000 && value <= 0xA48F { return true }
        // Yi Radicals
        if value >= 0xA490 && value <= 0xA4CF { return true }
        // Hangul Syllables
        if value >= 0xAC00 && value <= 0xD7AF { return true }
        // CJK Compatibility Ideographs
        if value >= 0xF900 && value <= 0xFAFF { return true }
        // Halfwidth and Fullwidth Forms (Fullwidth portion)
        if value >= 0xFF00 && value <= 0xFF60 { return true }
        if value >= 0xFFE0 && value <= 0xFFE6 { return true }
        // CJK Unified Ideographs Extension B-G
        if value >= 0x20000 && value <= 0x2FFFF { return true }
        // Supplementary Ideographic Plane
        if value >= 0x30000 && value <= 0x3FFFF { return true }

        // Common emoji ranges (most render as double-width)
        // Miscellaneous Symbols and Pictographs
        if value >= 0x1F300 && value <= 0x1F5FF { return true }
        // Emoticons
        if value >= 0x1F600 && value <= 0x1F64F { return true }
        // Transport and Map Symbols
        if value >= 0x1F680 && value <= 0x1F6FF { return true }
        // Supplemental Symbols and Pictographs
        if value >= 0x1F900 && value <= 0x1F9FF { return true }
        // Symbols and Pictographs Extended-A
        if value >= 0x1FA00 && value <= 0x1FA6F { return true }
        // Symbols and Pictographs Extended-B
        if value >= 0x1FA70 && value <= 0x1FAFF { return true }

        return false
    }
}

// MARK: - TextTable

/// A simple text table generator for CLI output
struct TextTable {
    /// Represents a column in the table
    struct Column {
        let header: String
        var width: Int

        init(header: String) {
            self.header = header
            self.width = header.terminalWidth
        }
    }

    private var columns: [Column]
    private var rows: [[String]]

    /// Initialize a new text table with the given headers
    /// - Parameter headers: An array of header strings for each column
    init(headers: [String]) {
        self.columns = headers.map { Column(header: $0) }
        self.rows = []
    }

    /// Add a row of values to the table
    /// - Parameter values: An array of string values, one for each column
    mutating func addRow(values: [String]) {
        // Pad or truncate the values array to match the number of columns
        var adjustedValues = values
        while adjustedValues.count < columns.count {
            adjustedValues.append("")
        }
        if adjustedValues.count > columns.count {
            adjustedValues = Array(adjustedValues.prefix(columns.count))
        }

        // Update column widths based on the new values (using terminal width)
        for (index, value) in adjustedValues.enumerated() {
            columns[index].width = max(columns[index].width, value.terminalWidth)
        }

        rows.append(adjustedValues)
    }

    /// Render the table as a formatted string
    /// - Returns: A string representation of the table with ASCII borders
    func render() -> String {
        guard !columns.isEmpty else { return "" }

        var lines: [String] = []

        // Create the separator line
        let separator = "+" + columns.map { String(repeating: "-", count: $0.width + 2) }.joined(separator: "+") + "+"

        // Add top border
        lines.append(separator)

        // Add header row (using terminal-aware padding)
        let headerRow = "|" + columns.map { column in
            " " + column.header.terminalPadding(toWidth: column.width) + " "
        }.joined(separator: "|") + "|"
        lines.append(headerRow)

        // Add header separator
        lines.append(separator)

        // Add data rows (using terminal-aware padding)
        for row in rows {
            let dataRow = "|" + zip(columns, row).map { column, value in
                " " + value.terminalPadding(toWidth: column.width) + " "
            }.joined(separator: "|") + "|"
            lines.append(dataRow)
        }

        // Add bottom border
        lines.append(separator)

        return lines.joined(separator: "\n")
    }
}
