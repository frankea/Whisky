//
//  DiagnosisMatch.swift
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

/// A single match of a crash pattern against a specific log line.
public struct DiagnosisMatch: Sendable {
    /// The pattern that matched.
    public let pattern: CrashPattern

    /// Zero-based index of the matched line in the log.
    public let lineIndex: Int

    /// The full text of the matched line.
    public let lineText: String

    /// Captured groups from the regex match.
    public let captures: [String]

    public init(pattern: CrashPattern, lineIndex: Int, lineText: String, captures: [String]) {
        self.pattern = pattern
        self.lineIndex = lineIndex
        self.lineText = lineText
        self.captures = captures
    }
}
