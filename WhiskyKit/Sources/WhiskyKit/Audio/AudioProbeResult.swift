//
//  AudioProbeResult.swift
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

/// The outcome status of a single audio probe execution.
public enum ProbeStatus: String, Sendable, Equatable {
    /// Probe completed successfully with no issues detected.
    case passed
    /// Probe completed but detected a potential issue.
    case warning
    /// Probe failed or detected a critical issue.
    case error
    /// Probe was skipped (e.g., missing test executable).
    case skipped

    /// Human-readable display name for this status.
    public var displayName: String {
        switch self {
        case .passed: "OK"
        case .warning: "Warning"
        case .error: "Error"
        case .skipped: "Skipped"
        }
    }

    /// SF Symbol name for status presentation.
    public var sfSymbol: String {
        switch self {
        case .passed: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.circle.fill"
        case .skipped: "arrow.right.circle"
        }
    }
}

/// The structured result of running an ``AudioProbe``.
///
/// Each probe execution produces exactly one result containing the probe
/// identity, a status classification, human-readable summary, technical
/// evidence lines, and any diagnostic findings detected.
public struct AudioProbeResult: Sendable, Identifiable {
    /// The probe identifier (e.g., "coreaudio-device", "wine-registry", "wine-audio-test").
    public let probeId: String

    /// The outcome status of the probe.
    public let status: ProbeStatus

    /// One-line human-readable summary of the result.
    public let summary: String

    /// Technical detail lines for collapsed display in the UI.
    public let evidence: [String]

    /// Issues detected by this probe.
    public let findings: [AudioFinding]

    /// When the probe was executed.
    public let timestamp: Date

    /// Stable identifier derived from probe ID and timestamp.
    public var id: String {
        "\(probeId)-\(timestamp.timeIntervalSince1970)"
    }

    public init(
        probeId: String,
        status: ProbeStatus,
        summary: String,
        evidence: [String] = [],
        findings: [AudioFinding] = [],
        timestamp: Date = Date()
    ) {
        self.probeId = probeId
        self.status = status
        self.summary = summary
        self.evidence = evidence
        self.findings = findings
        self.timestamp = timestamp
    }
}
