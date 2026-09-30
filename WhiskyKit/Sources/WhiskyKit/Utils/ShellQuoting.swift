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

/// Turns values into shell words that zsh, bash, the other POSIX shells and
/// fish all read back verbatim.
///
/// The value goes inside single quotes, where nothing expands: no `$`, no
/// backticks, no globs. Two characters are kept out of the quoted runs. A
/// single quote would end the run early, and a backslash is literal inside
/// single quotes in POSIX shells but starts an escape in fish when a quote or
/// another backslash follows it, so fish would read a different value or end
/// the run somewhere else. Both go between runs instead, backslash-escaped,
/// which all of those shells read the same way: `'` becomes `'\''` and `\`
/// becomes `'\\'` (close, escaped character, reopen).
///
/// That matters because Open in Terminal and the winetricks terminal source
/// their scripts in the user's login shell, which can be fish. Prefer this
/// over backslash-escaping whenever a value ends up in shell text, such as a
/// script handed to a terminal, rather than in a `Process` argument array.
public enum ShellQuoting {
    /// `value` as one shell word, safe to paste into zsh, bash, sh or fish.
    ///
    /// Walks the value by Unicode scalar, not by `Character`: a quote followed
    /// by a combining mark is one `Character` that does not compare equal to
    /// `'`, so a character-level replacement would leave that quote in place,
    /// where it ends the quoted run and turns the rest of the value into shell
    /// code.
    public static func quoted(_ value: String) -> String {
        var word = "'"
        for scalar in value.unicodeScalars {
            switch scalar {
            case "'":
                word += #"'\''"#
            case "\\":
                word += #"'\\'"#
            default:
                word.unicodeScalars.append(scalar)
            }
        }
        return word + "'"
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
