//
//  CrashCategory.swift
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

/// Categories for classifying Wine crash patterns.
///
/// Each category represents a high-level group of errors with shared
/// root causes and remediation strategies.
public enum CrashCategory: String, Codable, Sendable, CaseIterable, Hashable {
    /// Access violations, unhandled exceptions, page faults, process termination.
    case coreCrashFatal

    /// GPU timeout, device removed, Metal validation, backend incompatibility.
    case graphics

    /// DLL load failures, .NET/CLR issues, missing redistributables.
    case dependenciesLoading

    /// Prefix corruption, missing user dirs, path/permission errors.
    case prefixFilesystem

    /// TLS/SSL errors, HTTP timeouts, launcher connectivity.
    case networkingLaunchers

    /// EasyAntiCheat, BattlEye, and other anti-cheat signatures.
    case antiCheatUnsupported

    /// Low-confidence suggestions, unrecognized errors.
    case otherUnknown

    /// Display name for this category in the app's language.
    ///
    /// Exported reports use ``exportName`` instead so they read the same
    /// whatever language the app runs in.
    public var displayName: String {
        switch self {
        case .coreCrashFatal:
            String(localized: "diagnostics.category.coreCrashFatal")
        case .graphics:
            String(localized: "diagnostics.category.graphics")
        case .dependenciesLoading:
            String(localized: "diagnostics.category.dependenciesLoading")
        case .prefixFilesystem:
            String(localized: "diagnostics.category.prefixFilesystem")
        case .networkingLaunchers:
            String(localized: "diagnostics.category.networkingLaunchers")
        case .antiCheatUnsupported:
            String(localized: "diagnostics.category.antiCheatUnsupported")
        case .otherUnknown:
            String(localized: "diagnostics.category.otherUnknown")
        }
    }

    /// English name for this category, used in exported diagnostic reports.
    public var exportName: String {
        switch self {
        case .coreCrashFatal:
            "Crash / Fatal Error"
        case .graphics:
            "Graphics / GPU"
        case .dependenciesLoading:
            "Dependencies / Loading"
        case .prefixFilesystem:
            "Prefix / Filesystem"
        case .networkingLaunchers:
            "Networking / Launchers"
        case .antiCheatUnsupported:
            "Anti-Cheat / Unsupported"
        case .otherUnknown:
            "Other / Unknown"
        }
    }

    /// SF Symbol name for this category.
    public var sfSymbol: String {
        switch self {
        case .coreCrashFatal:
            "exclamationmark.triangle.fill"
        case .graphics:
            "gpu"
        case .dependenciesLoading:
            "shippingbox"
        case .prefixFilesystem:
            "folder.badge.questionmark"
        case .networkingLaunchers:
            "network"
        case .antiCheatUnsupported:
            "shield.slash"
        case .otherUnknown:
            "questionmark.circle"
        }
    }
}
