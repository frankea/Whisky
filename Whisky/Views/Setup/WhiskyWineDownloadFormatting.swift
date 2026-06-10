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

    func formatBytes(bytes: Int64) -> String {
        Self.byteCountFormatter.string(fromByteCount: bytes)
    }

    func formatRemainingTime(remainingBytes: Int64) -> String {
        // Guard against invalid values that would produce meaningless time estimates.
        guard remainingBytes > 0, downloadSpeed > 0 else {
            return ""
        }
        let remainingTimeInSeconds = Double(remainingBytes) / downloadSpeed
        return Self.remainingTimeFormatter.string(from: remainingTimeInSeconds) ?? ""
    }

    /// A download/verification failure: user-facing message and telemetry reason set together.
    struct DownloadFailure: Equatable {
        let message: String
        let reason: Telemetry.InstallFailureReason
    }

    /// Sets the failure state and reports the funnel event atomically, so the
    /// reported reason always matches the surfaced message.
    @MainActor
    func setDownloadFailure(_ message: String, reason: Telemetry.InstallFailureReason = .downloadFailed) {
        downloadFailure = DownloadFailure(message: message, reason: reason)
        Telemetry.capture(.runtimeInstallFailed(reason: reason))
    }
}
