//
//  URL+Extensions.swift
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

extension String {
    /// Escapes shell metacharacters and removes control characters for safe shell interpolation.
    ///
    /// This property returns a string safe for use in shell commands by:
    /// 1. Removing control characters (newlines, tabs, etc.) that could cause command injection
    /// 2. Escaping shell metacharacters with backslashes
    ///
    /// - Important: Control characters are stripped rather than escaped because
    ///   backslash-escaped newlines in shell are line continuations, not literal newlines.
    public var esc: String {
        // First, remove control characters (newlines, tabs, carriage returns, etc.)
        // These could be used for command injection if present in filenames or arguments
        var str = self.filter { char in
            // Allow only printable characters (ASCII 32-126) and extended Unicode
            // Reject control characters (ASCII 0-31 and 127)
            guard let ascii = char.asciiValue else {
                // Non-ASCII characters (Unicode) are allowed
                return true
            }
            return ascii >= 32 && ascii != 127
        }

        // Escape shell metacharacters
        let metacharacters = ["\\", "\"", "'", " ", "(", ")", "[", "]", "{", "}", "&", "|",
                              ";", "<", ">", "`", "$", "!", "*", "?", "#", "~", "="]
        for char in metacharacters {
            str = str.replacingOccurrences(of: char, with: "\\" + char)
        }
        return str
    }
}

extension URL {
    public var esc: String {
        path.esc
    }

    public func prettyPath() -> String {
        var prettyPath = path(percentEncoded: false)
        prettyPath = prettyPath
            .replacingOccurrences(of: Bundle.main.bundleIdentifier ?? Bundle.whiskyBundleIdentifier, with: "Whisky")
            .replacingOccurrences(of: "/Users/\(NSUserName())", with: "~")
        return prettyPath
    }

    // NOT to be used for logic only as UI decoration
    public func prettyPath(_ bottle: Bottle) -> String {
        var prettyPath = path(percentEncoded: false)
        prettyPath = prettyPath
            .replacingOccurrences(of: bottle.url.path(percentEncoded: false), with: "")
            .replacingOccurrences(of: "/drive_c/", with: "C:\\")
            .replacingOccurrences(of: "/", with: "\\")
        return prettyPath
    }

    // There is probably a better way to do this
    public func updateParentBottle(old: URL, new: URL) -> URL {
        let originalPath = path(percentEncoded: false)

        var oldBottlePath = old.path(percentEncoded: false)
        if oldBottlePath.last != "/" {
            oldBottlePath += "/"
        }

        var newBottlePath = new.path(percentEncoded: false)
        if newBottlePath.last != "/" {
            newBottlePath += "/"
        }

        let newPath = originalPath.replacingOccurrences(of: oldBottlePath,
                                                        with: newBottlePath)
        return URL(filePath: newPath)
    }
}

extension URL: @retroactive Identifiable {
    public var id: URL { self }
}
