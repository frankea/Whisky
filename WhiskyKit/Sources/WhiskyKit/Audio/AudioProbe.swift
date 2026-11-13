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
                summary: String(localized: "audio.probe.noDevice"),
                evidence: ["AudioObjectGetPropertyData returned nil for default output device"],
                findings: [
                    AudioFinding(
                        id: "no-default-device",
                        description: String(localized: "audio.probe.noDevice"),
                        confidence: .high,
                        evidence: String(localized: "audio.finding.noDevice.evidence"),
                        suggestedAction: String(localized: "audio.finding.noDevice.action")
                    )
                ]
            )
        }

        // Evidence lines are technical detail for the diagnostics export and
        // stay English; summaries and findings are shown in the UI.
        let evidence = [
            "Device: \(device.name)",
            "Transport: \(device.transportType.exportName)",
            "Sample rate: \(Int(device.sampleRate)) Hz",
            "Output channels: \(device.outputChannelCount)",
            "Is default: \(device.isDefault)"
        ]

        let findings = analyzeDevice(device)
        let status: ProbeStatus = findings.isEmpty ? .passed : .warning
        let sampleRate = Int(device.sampleRate)
        let transport = device.transportType.displayName
        let summary = findings.isEmpty
            ? String(localized: "audio.probe.device.summary \(device.name) \(transport) \(sampleRate)")
            : String(localized: "audio.probe.device.issues \(device.name) \(findings.count)")

        return AudioProbeResult(
            probeId: id, status: status, summary: summary,
            evidence: evidence, findings: findings
        )
    }

    private func analyzeDevice(_ device: AudioDeviceInfo) -> [AudioFinding] {
        var findings: [AudioFinding] = []
        let sampleRate = Int(device.sampleRate)
        let standardSampleRate = 44_100

        if device.transportType == .bluetooth {
            findings.append(AudioFinding(
                id: "bluetooth-device",
                description: String(localized: "audio.finding.bluetooth"),
                confidence: .medium,
                evidence: String(localized: "audio.finding.bluetooth.evidence \(device.name)"),
                suggestedAction: String(localized: "audio.finding.bluetooth.action")
            ))
        }

        if device.sampleRate < 22_050 {
            findings.append(AudioFinding(
                id: "low-sample-rate",
                description: String(localized: "audio.finding.lowSampleRate \(sampleRate)"),
                confidence: .high,
                evidence: String(
                    localized: "audio.finding.lowSampleRate.veryLow.evidence \(sampleRate) \(standardSampleRate)"
                ),
                suggestedAction: String(localized: "audio.finding.lowSampleRate.handsFree.action")
            ))
        } else if device.sampleRate < Double(standardSampleRate), device.sampleRate > 0 {
            findings.append(AudioFinding(
                id: "low-sample-rate",
                description: String(localized: "audio.finding.lowSampleRate \(sampleRate)"),
                confidence: .medium,
                evidence: String(
                    localized: "audio.finding.lowSampleRate.belowStandard.evidence \(sampleRate) \(standardSampleRate)"
                ),
                suggestedAction: String(localized: "audio.finding.lowSampleRate.midi.action")
            ))
        }

        if device.outputChannelCount == 0 {
            findings.append(AudioFinding(
                id: "no-output-channels",
                description: String(localized: "audio.finding.noOutputChannels"),
                confidence: .high,
                evidence: String(localized: "audio.finding.noOutputChannels.evidence \(device.name)"),
                suggestedAction: String(localized: "audio.finding.noOutputChannels.action")
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
            ? String(localized: "audio.probe.registry.ok")
            : String(localized: "audio.probe.registry.issues \(findings.count)")

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
                summary: String(localized: "audio.probe.registry.readFailed"),
                evidence: ["Error reading audio driver key: \(error.localizedDescription)"],
                findings: []
            ))
        }

        if let driver = driverValue {
            evidence.append("Audio driver: \"\(driver)\"")
            if driver.isEmpty {
                findings.append(AudioFinding(
                    id: "audio-disabled",
                    description: String(localized: "audio.finding.audioDisabled"),
                    confidence: .high,
                    evidence: String(localized: "audio.finding.audioDisabled.evidence"),
                    suggestedAction: String(localized: "audio.finding.audioDisabled.action")
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
                    description: String(localized: "audio.finding.lowBuffer"),
                    confidence: .medium,
                    evidence: "HelBuflen = \(bufSize) (< 256 bytes)",
                    suggestedAction: String(localized: "audio.finding.lowBuffer.action")
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
