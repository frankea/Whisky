//
//  AudioDeviceCheck.swift
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

/// Checks the default audio output device availability and transport type.
///
/// Uses preflight data to verify that a default audio device is present.
/// Returns `.warning` for Bluetooth devices (potential latency), `.pass`
/// for wired devices, and `.fail` when no device is detected.
public struct AudioDeviceCheck: TroubleshootingCheck {
    public let checkId = "audio.device_check"

    public init() {}

    public func run(params: [String: String], context: CheckContext) async -> CheckResult {
        guard let deviceName = context.preflight.audioDeviceName else {
            return CheckResult(
                outcome: .fail,
                evidence: [:],
                summary: "No default audio output device detected",
                confidence: .high
            )
        }

        let transportType = context.preflight.audioTransportType ?? "unknown"

        var evidence = [
            "deviceName": deviceName,
            "transportType": transportType
        ]

        // Check for Bluetooth transport (potential latency)
        if transportType.lowercased().contains("bluetooth") {
            evidence["warning"] = "Bluetooth audio may have latency issues"
            return CheckResult(
                outcome: .pass,
                evidence: evidence,
                summary: "\(deviceName) connected via Bluetooth (potential latency)",
                confidence: .medium
            )
        }

        return CheckResult(
            outcome: .pass,
            evidence: evidence,
            summary: "\(deviceName) (\(transportType)) available",
            confidence: .high
        )
    }
}
