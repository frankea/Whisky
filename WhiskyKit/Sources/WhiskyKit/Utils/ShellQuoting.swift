//
//  ShellQuoting.swift
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

/// Turns values into shell words that a POSIX shell reads back verbatim.
///
/// Single quotes are the one quoting form in which nothing expands: no `$`,
/// no backticks, no backslash escapes. The only character that needs care is
/// the single quote itself, which ends the quoted run; it is written as
/// `'\''` (close, escaped quote, reopen). Prefer this over backslash-escaping
/// whenever a value ends up in shell text, such as a script handed to a
/// terminal, rather than in a `Process` argument array.
public enum ShellQuoting {
    /// `value` as one shell word, safe to paste into any POSIX shell.
    public static func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// `words` as one command line, each word quoted.
    public static func commandLine(_ words: [String]) -> String {
        words.map(quoted).joined(separator: " ")
    }

    /// A `NAME=value` assignment with the value quoted, for prefixing a command
    /// (`WINEPREFIX='...' wine ...`). `name` must be a valid identifier; it is
    /// the caller's constant, never data.
    public static func assignment(_ name: String, _ value: String) -> String {
        "\(name)=\(quoted(value))"
    }
}
