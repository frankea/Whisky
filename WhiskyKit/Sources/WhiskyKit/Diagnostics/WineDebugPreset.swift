//
//  WineDebugPreset.swift
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

/// Curated WINEDEBUG presets for diagnostic logging.
///
/// Each preset configures the Wine debug channels to capture specific
/// categories of diagnostic information. The ``normal`` preset preserves
/// the existing default; other presets enable targeted channels for
/// crash analysis, DLL loading issues, or verbose output.
public enum WineDebugPreset: String, Codable, Sendable, CaseIterable {
    /// Default Wine debug level. Suppresses fixme messages.
    case normal

    /// Enhanced logging for crash analysis: SEH exceptions, thread IDs, timestamps.
    case crash

    /// Enhanced logging for DLL and module loading issues.
    case dllLoad

    /// Full verbose output. Warning: very noisy.
    case verbose

    /// The WINEDEBUG environment variable value for this preset.
    public var winedebugValue: String {
        switch self {
        case .normal:
            "fixme-all"
        case .crash:
            "+seh,+tid,+pid,+timestamp,fixme-all"
        case .dllLoad:
            "+loaddll,+module,+tid,+pid,fixme-all"
        case .verbose:
            "+all"
        }
    }

    /// The preset name in the app's language, for the preset picker and other UI.
    ///
    /// Check evidence and exports use ``exportName`` instead so they read the
    /// same whatever language the app runs in.
    public var displayName: String {
        switch self {
        case .normal:
            String(localized: "diagnostics.wineDebug.normal")
        case .crash:
            String(localized: "diagnostics.wineDebug.crash")
        case .dllLoad:
            String(localized: "diagnostics.wineDebug.dllLoad")
        case .verbose:
            String(localized: "diagnostics.wineDebug.verbose")
        }
    }

    /// English name of the preset, for check evidence and exported reports.
    public var exportName: String {
        switch self {
        case .normal:
            "Normal"
        case .crash:
            "Crash Analysis"
        case .dllLoad:
            "DLL Loading"
        case .verbose:
            "Verbose"
        }
    }

    /// Description of what this preset enables, in the user's language.
    public var presetDescription: String {
        switch self {
        case .normal:
            String(localized: "diagnostics.wineDebug.normal.description")
        case .crash:
            String(localized: "diagnostics.wineDebug.crash.description")
        case .dllLoad:
            String(localized: "diagnostics.wineDebug.dllLoad.description")
        case .verbose:
            String(localized: "diagnostics.wineDebug.verbose.description")
        }
    }
}
