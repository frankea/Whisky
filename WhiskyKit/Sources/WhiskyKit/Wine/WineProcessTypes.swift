//
//  WineProcessTypes.swift
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

/// Classifies a Wine process by its role within the Windows environment.
///
/// Wine runs a number of background services and system processes alongside
/// user-launched applications. This enum lets the UI distinguish between them
/// so that service/system processes can be de-emphasized or hidden.
public enum ProcessKind: String, CaseIterable, Codable, Sendable {
    /// A user-launched application (the default for any unrecognized image name).
    case app
    /// A Wine service process (e.g. `services.exe`, `plugplay.exe`).
    case service
    /// A Wine system process (e.g. `explorer.exe`, `csrss.exe`).
    case system

    /// Known Wine service process image names (lowercase).
    public static let knownServiceProcesses: Set<String> = [
        "services.exe",
        "winedevice.exe",
        "plugplay.exe",
        "svchost.exe",
        "rpcss.exe",
        "tabtip.exe",
        "conhost.exe"
    ]

    /// Known Wine system process image names (lowercase).
    public static let knownSystemProcesses: Set<String> = [
        "explorer.exe",
        "start.exe",
        "csrss.exe",
        "wininit.exe",
        "winlogon.exe",
        "lsass.exe",
        "smss.exe"
    ]

    /// Classifies a Windows image name into the appropriate ``ProcessKind``.
    ///
    /// The lookup is case-insensitive. Any name not found in the known service
    /// or system sets is treated as `.app`.
    ///
    /// - Parameter imageName: The Windows process image name (e.g. `"game.exe"`).
    /// - Returns: The classified process kind.
    public static func classify(_ imageName: String) -> ProcessKind {
        let lower = imageName.lowercased()
        if knownServiceProcesses.contains(lower) {
            return .service
        }
        if knownSystemProcesses.contains(lower) {
            return .system
        }
        return .app
    }
}

/// Indicates how a Wine process was discovered.
public enum ProcessSource: String, Codable, Sendable {
    /// The process was launched by Whisky and is tracked in ``ProcessRegistry``.
    case whisky
    /// The process was discovered via `tasklist.exe` but is not in the registry.
    case untracked
}

/// Tracks the shutdown state of a bottle's Wine processes.
public enum ShutdownState: String, Sendable {
    /// No shutdown in progress.
    case idle
    /// A graceful shutdown (SIGTERM / `taskkill`) has been requested.
    case stopping
    /// A forced shutdown (SIGKILL / `taskkill /F`) has been requested.
    case forceKilling
}

/// A snapshot of a single Wine process as reported by `tasklist.exe`.
///
/// Instances are created by ``Wine/parseTasklistOutput(_:)`` and enriched with
/// registry data (source, launch time, macOS PID) by the view model.
public struct WineProcess: Identifiable, Hashable, Sendable {
    /// The Windows image name from tasklist (e.g. `"game.exe"`).
    public let imageName: String
    /// The Wine/Windows PID from tasklist.
    public let winePID: Int32
    /// The raw memory usage string from tasklist (e.g. `"24 K"`).
    public let memoryUsage: String
    /// The classified role of this process.
    public let kind: ProcessKind
    /// How the process was discovered.
    public var source: ProcessSource
    /// When the process was launched (from ``ProcessRegistry`` match, nil for untracked).
    public var launchTime: Date?
    /// The macOS PID (from ``ProcessRegistry`` match, nil for untracked).
    public var macosPID: Int32?
    /// The full command line, if known (for detail drawer).
    public var commandLine: String?

    /// Identifiable conformance keyed on the Wine PID.
    public var id: Int32 {
        winePID
    }

    /// Memberwise initializer with sensible defaults for optional fields.
    public init(
        imageName: String,
        winePID: Int32,
        memoryUsage: String,
        kind: ProcessKind,
        source: ProcessSource = .untracked,
        launchTime: Date? = nil,
        macosPID: Int32? = nil,
        commandLine: String? = nil
    ) {
        self.imageName = imageName
        self.winePID = winePID
        self.memoryUsage = memoryUsage
        self.kind = kind
        self.source = source
        self.launchTime = launchTime
        self.macosPID = macosPID
        self.commandLine = commandLine
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(winePID)
        hasher.combine(imageName)
    }

    public static func == (lhs: WineProcess, rhs: WineProcess) -> Bool {
        lhs.winePID == rhs.winePID && lhs.imageName == rhs.imageName
    }
}
