//
//  DiagnosticExportError.swift
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

/// Why a diagnostics ZIP could not be produced.
public enum DiagnosticExportError: LocalizedError, Equatable {
    /// `ditto` exited with a nonzero status.
    case compressionFailed(status: Int32)
    /// No archive exists where one was expected.
    case archiveMissing

    public var errorDescription: String? {
        switch self {
        case let .compressionFailed(status):
            String(localized: "diagnostics.export.error.compressionFailed \(Int(status))")
        case .archiveMissing:
            String(localized: "diagnostics.export.error.archiveMissing")
        }
    }
}
