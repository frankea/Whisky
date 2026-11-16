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
/// Returns `.pass` for an available device (noting the latency risk of a
/// Bluetooth one) and `.fail` when no device is detected.
///
/// With `params["check"]` set to `sample_rate_compat` it also fails a device
/// whose sample rate is known and below 44.1 kHz, the rate the audio probe
/// treats as standard. An unknown rate is not held against the device.
public struct AudioDeviceCheck: TroubleshootingCheck {
    public let checkId = "audio.device_check"

    /// The `check` param value that adds the sample rate test.
    static let sampleRateCheck = "sample_rate_compat"

    /// The lowest sample rate that passes the sample rate test, in Hz.
    static let minimumSampleRate = 44_100

    public init() {}

    public let signature: CheckSignature? = CheckSignature(
        acceptedParams: ["check"], outcomes: [.pass, .fail]
    )

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
        let sampleRate = context.preflight.audioSampleRate.map { Int($0) }.flatMap { $0 > 0 ? $0 : nil }
        if let sampleRate {
            evidence["sampleRate"] = "\(sampleRate)"
        }

        if params["check"] == Self.sampleRateCheck, let sampleRate, sampleRate < Self.minimumSampleRate {
            evidence["recommendedRate"] = "\(Self.minimumSampleRate)"
            return CheckResult(
                outcome: .fail,
                evidence: evidence,
                summary: "\(deviceName) runs at \(sampleRate) Hz, below \(Self.minimumSampleRate) Hz",
                confidence: .medium
            )
        }

        // Check for Bluetooth transport (potential latency)
        if Self.isBluetooth(transportType) {
            evidence["warning"] = String(localized: "troubleshooting.check.audioDevice.bluetoothWarning")
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

    /// The summary of a result from this check in the user's language.
    ///
    /// ``CheckResult/summary`` stays in English because it is written to
    /// history and escalation exports; this rebuilds the on-screen text from
    /// the result's outcome and evidence.
    ///
    /// - Parameter result: A result produced by ``run(params:context:)``.
    /// - Returns: The localized summary, or `nil` if the result was not
    ///   produced by this check.
    public static func localizedSummary(for result: CheckResult) -> String? {
        if result.outcome == .fail {
            // A failure with a device is the sample rate test's.
            if result.evidence["deviceName"] != nil,
               let sampleRate = result.evidence["sampleRate"].flatMap({ Int($0) }) {
                return String(localized: "audio.finding.lowSampleRate \(sampleRate)")
            }
            return String(localized: "troubleshooting.check.audioDevice.none")
        }
        guard let deviceName = result.evidence["deviceName"],
              let transportType = result.evidence["transportType"]
        else {
            return nil
        }
        if isBluetooth(transportType) {
            return String(localized: "troubleshooting.check.audioDevice.bluetooth \(deviceName)")
        }
        // Preflight stores the English name ("Built-in"); older sessions may hold a raw value.
        let transport = AudioTransportType.allCases
            .first { $0.exportName == transportType || $0.rawValue == transportType }?
            .displayName ?? transportType
        return String(localized: "troubleshooting.check.audioDevice.available \(deviceName) \(transport)")
    }

    /// Whether a preflight transport value names a Bluetooth device.
    ///
    /// Accepts both a raw ``AudioTransportType`` value and its display name.
    private static func isBluetooth(_ transportType: String) -> Bool {
        AudioTransportType(rawValue: transportType) == .bluetooth
            || transportType.lowercased().contains("bluetooth")
    }
}
