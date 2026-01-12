//
//  Magic.swift
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

public extension PEFile {
    public enum Magic: UInt16, Hashable, Equatable, CustomStringConvertible, Sendable {
        case unknown = 0x0
        case pe32 = 0x10B
        case pe32Plus = 0x20B

        // MARK: - CustomStringConvertible

        public var description: String {
            switch self {
            case .unknown:
                "unknown"
            case .pe32:
                "PE32"
            case .pe32Plus:
                "PE32+"
            }
        }
    }
}
