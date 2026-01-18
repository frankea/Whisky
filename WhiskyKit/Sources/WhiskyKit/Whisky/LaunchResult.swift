//
//  LaunchResult.swift
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

/// Result of launching a Windows program
public enum LaunchResult: Sendable {
    /// Program launched successfully in Wine
    case launchedSuccessfully(programName: String)
    /// Program launched in Terminal (shift-click mode)
    case launchedInTerminal(programName: String)
    /// Program launch failed with an error
    case launchFailed(programName: String, errorDescription: String)

    /// The name of the program that was launched
    public var programName: String {
        switch self {
        case let .launchedSuccessfully(name),
             let .launchedInTerminal(name),
             let .launchFailed(name, _):
            name
        }
    }

    /// The error description if launch failed, nil otherwise
    public var errorDescription: String? {
        if case let .launchFailed(_, description) = self {
            return description
        }
        return nil
    }

    // MARK: - Notification Properties

    /// The style category for UI notifications
    public enum NotificationStyle: Sendable {
        case success
        case info
        case error
    }

    /// The appropriate notification style for this result
    public var notificationStyle: NotificationStyle {
        switch self {
        case .launchedSuccessfully:
            .success
        case .launchedInTerminal:
            .info
        case .launchFailed:
            .error
        }
    }

    /// Whether notifications for this result should auto-dismiss
    /// Returns false for errors (user should acknowledge), true otherwise
    public var shouldAutoDismiss: Bool {
        switch self {
        case .launchedSuccessfully, .launchedInTerminal:
            true
        case .launchFailed:
            false
        }
    }
}
