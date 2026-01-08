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

/// A simple text table generator for CLI output
struct TextTable {
    /// Represents a column in the table
    struct Column {
        let header: String
        var width: Int

        init(header: String) {
            self.header = header
            self.width = header.count
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

        // Update column widths based on the new values
        for (index, value) in adjustedValues.enumerated() {
            columns[index].width = max(columns[index].width, value.count)
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

        // Add header row
        let headerRow = "|" + columns.map { column in
            " " + column.header.padding(toLength: column.width, withPad: " ", startingAt: 0) + " "
        }.joined(separator: "|") + "|"
        lines.append(headerRow)

        // Add header separator
        lines.append(separator)

        // Add data rows
        for row in rows {
            let dataRow = "|" + zip(columns, row).map { column, value in
                " " + value.padding(toLength: column.width, withPad: " ", startingAt: 0) + " "
            }.joined(separator: "|") + "|"
            lines.append(dataRow)
        }

        // Add bottom border
        lines.append(separator)

        return lines.joined(separator: "\n")
    }
}
