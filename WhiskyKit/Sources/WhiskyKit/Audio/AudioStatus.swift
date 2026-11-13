//
//  AudioStatus.swift
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

/// Overall audio health classification for a bottle.
///
/// This is a transient status computed from the latest probe results and device
/// state. It is not persisted (not `Codable`).
public enum AudioStatus: Sendable, Equatable {
    /// Audio is working correctly.
    case healthy
    /// Audio is functional but has an identified issue.
    case degraded(primaryIssue: String)
    /// Audio is not functional.
    case broken(primaryIssue: String)
    /// Audio status has not been assessed.
    case unknown

    /// Localized display name for the status line in the UI.
    public var displayName: String {
        switch self {
        case .healthy: String(localized: "audio.status.ok")
        case .degraded: String(localized: "audio.status.degraded")
        case .broken: String(localized: "audio.status.broken")
        case .unknown: String(localized: "audio.status.unknown")
        }
    }

    /// SF Symbol name for status presentation.
    public var sfSymbol: String {
        switch self {
        case .healthy: "checkmark.circle.fill"
        case .degraded: "exclamationmark.triangle.fill"
        case .broken: "xmark.circle.fill"
        case .unknown: "questionmark.circle"
        }
    }

    /// Semantic tint color name for status presentation.
    public var tintColor: String {
        switch self {
        case .healthy: "green"
        case .degraded: "orange"
        case .broken: "red"
        case .unknown: "secondary"
        }
    }
}
