//
//  AudioProbe.swift
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
import os.log

// MARK: - AudioProbe Protocol

/// A diagnostic probe that checks one aspect of the audio pipeline.
///
/// Probes never throw -- all errors are captured as ``ProbeStatus/error``
/// results so the caller always receives a structured ``AudioProbeResult``.
public protocol AudioProbe: Sendable {
    /// Unique identifier for this probe (e.g., "coreaudio-device").
    var id: String { get }

    /// Human-readable display name for UI presentation.
    var displayName: String { get }

    /// Runs the probe and returns a structured result. Never throws.
    func run() async -> AudioProbeResult
}

// MARK: - CoreAudioDeviceProbe

/// Checks the macOS CoreAudio default output device state.
///
/// This probe does not require a Wine bottle -- it checks the host
/// audio hardware for device availability, transport type, sample rate,
/// and channel configuration.
public struct CoreAudioDeviceProbe: AudioProbe {
    public let id = "coreaudio-device"
    public let displayName = "CoreAudio Device Check"

    private let monitor: AudioDeviceMonitor

    public init(monitor: AudioDeviceMonitor) {
        self.monitor = monitor
    }

    public func run() async -> AudioProbeResult {
        guard let device = monitor.defaultOutputDevice() else {
            return AudioProbeResult(
                probeId: id,
                status: .error,
                summary: "No default output device found",
                evidence: ["AudioObjectGetPropertyData returned nil for default output device"],
                findings: [
                    AudioFinding(
                        id: "no-default-device",
                        description: "No default output device found",
                        confidence: .high,
                        evidence: "System has no configured default audio output device",
                        suggestedAction: "Check macOS Sound settings and ensure an output device is selected"
                    )
                ]
            )
        }

        let evidence = [
            "Device: \(device.name)",
            "Transport: \(device.transportType.displayName)",
            "Sample rate: \(Int(device.sampleRate)) Hz",
            "Output channels: \(device.outputChannelCount)",
            "Is default: \(device.isDefault)"
        ]

        let findings = analyzeDevice(device)
        let status: ProbeStatus = findings.isEmpty ? .passed : .warning
        let summary = findings.isEmpty
            ? "\(device.name) (\(device.transportType.displayName), \(Int(device.sampleRate)) Hz)"
            : "\(device.name): \(findings.count) issue\(findings.count == 1 ? "" : "s") detected"

        return AudioProbeResult(
            probeId: id, status: status, summary: summary,
            evidence: evidence, findings: findings
        )
    }

    private func analyzeDevice(_ device: AudioDeviceInfo) -> [AudioFinding] {
        var findings: [AudioFinding] = []

        if device.transportType == .bluetooth {
            findings.append(AudioFinding(
                id: "bluetooth-device",
                description: "Bluetooth audio device detected",
                confidence: .medium,
                evidence: "\(device.name) connected via Bluetooth",
                suggestedAction: "Consider using wired headphones for lower latency"
            ))
        }

        if device.sampleRate < 22_050 {
            findings.append(AudioFinding(
                id: "low-sample-rate",
                description: "Low sample rate detected: \(Int(device.sampleRate)) Hz",
                confidence: .high,
                evidence: "Sample rate \(Int(device.sampleRate)) Hz is unusually low (expected >= 44100 Hz)",
                suggestedAction: "Check if Bluetooth Hands-Free mode is active; switch to A2DP for better quality"
            ))
        } else if device.sampleRate < 44_100, device.sampleRate > 0 {
            findings.append(AudioFinding(
                id: "low-sample-rate",
                description: "Low sample rate detected: \(Int(device.sampleRate)) Hz",
                confidence: .medium,
                evidence: "Sample rate \(Int(device.sampleRate)) Hz is below the standard 44100 Hz",
                suggestedAction: "Consider adjusting sample rate in Audio MIDI Setup"
            ))
        }

        if device.outputChannelCount == 0 {
            findings.append(AudioFinding(
                id: "no-output-channels",
                description: "No output channels",
                confidence: .high,
                evidence: "Device \(device.name) reports 0 output channels",
                suggestedAction: "The device may not support audio output; select a different device"
            ))
        }

        return findings
    }
}

// MARK: - WineRegistryAudioProbe

/// Checks the Wine audio driver configuration via registry keys.
///
/// Reads the current audio driver setting and DirectSound buffer size
/// from the Wine registry without launching a test program.
public final class WineRegistryAudioProbe: AudioProbe, @unchecked Sendable {
    public let id = "wine-registry"
    public let displayName = "Wine Audio Registry Check"

    private let bottle: Bottle

    public init(bottle: Bottle) {
        self.bottle = bottle
    }

    public func run() async -> AudioProbeResult {
        await runOnMainActor()
    }

    @MainActor
    private func runOnMainActor() async -> AudioProbeResult {
        var evidence: [String] = []
        var findings: [AudioFinding] = []

        let driverResult = await readAudioDriverSettings(evidence: &evidence, findings: &findings)
        if case let .error(result) = driverResult {
            return result
        }

        await readBufferSettings(evidence: &evidence, findings: &findings)

        let status: ProbeStatus = findings.isEmpty ? .passed : .warning
        let summary = findings.isEmpty
            ? "Wine audio registry: configured correctly"
            : "Wine audio registry: \(findings.count) issue\(findings.count == 1 ? "" : "s") detected"

        return AudioProbeResult(
            probeId: id,
            status: status,
            summary: summary,
            evidence: evidence,
            findings: findings
        )
    }

    @MainActor
    private func readAudioDriverSettings(
        evidence: inout [String],
        findings: inout [AudioFinding]
    ) async -> DriverReadResult {
        let driverValue: String?
        do {
            driverValue = try await Wine.readAudioDriver(bottle: bottle)
        } catch {
            return .error(AudioProbeResult(
                probeId: id,
                status: .error,
                summary: "Failed to read Wine audio registry",
                evidence: ["Error reading audio driver key: \(error.localizedDescription)"],
                findings: []
            ))
        }

        if let driver = driverValue {
            evidence.append("Audio driver: \"\(driver)\"")
            if driver.isEmpty {
                findings.append(AudioFinding(
                    id: "audio-disabled",
                    description: "Audio is disabled in Wine",
                    confidence: .high,
                    evidence: "Wine audio driver is set to empty string (disabled)",
                    suggestedAction: "Set audio driver to Auto or CoreAudio to enable audio"
                ))
            }
        } else {
            evidence.append("Audio driver: not set (Wine auto-detect)")
        }

        return .success
    }

    @MainActor
    private func readBufferSettings(evidence: inout [String], findings: inout [AudioFinding]) async {
        let bufferSize: Int?
        do {
            bufferSize = try await Wine.readDirectSoundBuffer(bottle: bottle)
        } catch {
            evidence.append("DirectSound HelBuflen: error reading (\(error.localizedDescription))")
            bufferSize = nil
        }

        if let bufSize = bufferSize {
            evidence.append("DirectSound HelBuflen: \(bufSize)")
            if bufSize < 256 {
                findings.append(AudioFinding(
                    id: "low-buffer-size",
                    description: "Very low audio buffer may cause issues",
                    confidence: .medium,
                    evidence: "HelBuflen = \(bufSize) (< 256 bytes)",
                    suggestedAction: "Increase audio buffer size or switch to Default latency preset"
                ))
            }
        } else if bufferSize == nil {
            evidence.append("DirectSound HelBuflen: not set (Wine default)")
        }
    }

    private enum DriverReadResult {
        case success
        case error(AudioProbeResult)
    }
}
