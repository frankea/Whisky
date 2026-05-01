//
//  PreflightData.swift
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

/// A snapshot of cheap, eagerly-collected data about a bottle and program.
///
/// Collected at the start of a troubleshooting session by the preflight collector
/// (Plan 03). Provides identity and runtime context to ``TroubleshootingCheck``
/// implementations without requiring expensive diagnostic operations.
///
/// All fields are simple `Codable` types suitable for session persistence.
public struct PreflightData: Codable, Sendable {
    /// URL of the bottle being troubleshot.
    public let bottleURL: URL

    /// Display name of the bottle.
    public let bottleName: String

    /// URL of the program being troubleshot, if any.
    public let programURL: URL?

    /// Display name of the program, if any.
    public let programName: String?

    /// Detected launcher type raw value, if any (e.g., "steam", "eaApp").
    public let launcherType: String?

    /// Whether the Wine server process is currently running for this bottle.
    public let isWineserverRunning: Bool

    /// Number of tracked Wine processes in this bottle.
    public let processCount: Int

    /// URL of the most recent log file for the program, if available.
    public let recentLogURL: URL?

    /// Exit code from the program's last run, if available.
    public let lastExitCode: Int32?

    /// Name of the current default audio output device, if detected.
    public let audioDeviceName: String?

    /// Transport type of the audio device (e.g., "built-in", "bluetooth").
    public let audioTransportType: String?

    /// Resolved graphics backend (e.g., "dxvk", "gptk").
    public let graphicsBackend: String

    /// When this preflight data was collected.
    public let collectedAt: Date

    public init(
        bottleURL: URL,
        bottleName: String,
        programURL: URL? = nil,
        programName: String? = nil,
        launcherType: String? = nil,
        isWineserverRunning: Bool,
        processCount: Int,
        recentLogURL: URL? = nil,
        lastExitCode: Int32? = nil,
        audioDeviceName: String? = nil,
        audioTransportType: String? = nil,
        graphicsBackend: String,
        collectedAt: Date = Date()
    ) {
        self.bottleURL = bottleURL
        self.bottleName = bottleName
        self.programURL = programURL
        self.programName = programName
        self.launcherType = launcherType
        self.isWineserverRunning = isWineserverRunning
        self.processCount = processCount
        self.recentLogURL = recentLogURL
        self.lastExitCode = lastExitCode
        self.audioDeviceName = audioDeviceName
        self.audioTransportType = audioTransportType
        self.graphicsBackend = graphicsBackend
        self.collectedAt = collectedAt
    }
}
