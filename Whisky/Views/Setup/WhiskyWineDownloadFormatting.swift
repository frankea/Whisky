//
//  WhiskyWineDownloadFormatting.swift
//  Whisky
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

/// Maps an HTTP status code from a failed runtime download into a localized,
/// user-facing message.
func formatHTTPError(statusCode: Int) -> String {
    let statusMessage = switch statusCode {
    case 404:
        String(localized: "setup.whiskywine.error.fileNotFound")
    case 403:
        String(localized: "setup.whiskywine.error.accessDenied")
    case 429:
        String(localized: "setup.whiskywine.error.rateLimit")
    case 500 ... 599:
        String(localized: "setup.whiskywine.error.serverError")
    default:
        String(
            format: String(localized: "setup.whiskywine.error.httpError"),
            statusCode
        )
    }
    return String(
        format: String(localized: "setup.whiskywine.error.downloadFailed"),
        statusMessage
    )
}

extension WhiskyWineDownloadView {
    /// Cached formatters to avoid repeated allocations during progress updates.
    static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.zeroPadsFractionDigits = true
        return formatter
    }()

    static let remainingTimeFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .full
        return formatter
    }()
}
