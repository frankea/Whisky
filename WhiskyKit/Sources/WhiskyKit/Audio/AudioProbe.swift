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

        var evidence: [String] = []
        evidence.append("Device: \(device.name)")
        evidence.append("Transport: \(device.transportType.displayName)")
        evidence.append("Sample rate: \(Int(device.sampleRate)) Hz")
        evidence.append("Output channels: \(device.outputChannelCount)")
        evidence.append("Is default: \(device.isDefault)")

        var findings: [AudioFinding] = []

        // Bluetooth audio can introduce latency
        if device.transportType == .bluetooth {
            findings.append(AudioFinding(
                id: "bluetooth-device",
                description: "Bluetooth audio device detected",
                confidence: .medium,
                evidence: "\(device.name) connected via Bluetooth",
                suggestedAction: "Consider using wired headphones for lower latency"
            ))
        }

        // Low sample rate detection
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

        // No output channels
        if device.outputChannelCount == 0 {
            findings.append(AudioFinding(
                id: "no-output-channels",
                description: "No output channels",
                confidence: .high,
                evidence: "Device \(device.name) reports 0 output channels",
                suggestedAction: "The device may not support audio output; select a different device"
            ))
        }

        let status: ProbeStatus = findings.isEmpty ? .ok : .warning
        let summary = findings.isEmpty
            ? "\(device.name) (\(device.transportType.displayName), \(Int(device.sampleRate)) Hz)"
            : "\(device.name): \(findings.count) issue\(findings.count == 1 ? "" : "s") detected"

        return AudioProbeResult(
            probeId: id,
            status: status,
            summary: summary,
            evidence: evidence,
            findings: findings
        )
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

        // Read audio driver setting
        let driverValue: String?
        do {
            driverValue = try await Wine.readAudioDriver(bottle: bottle)
        } catch {
            return AudioProbeResult(
                probeId: id,
                status: .error,
                summary: "Failed to read Wine audio registry",
                evidence: ["Error reading audio driver key: \(error.localizedDescription)"],
                findings: []
            )
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

        // Read DirectSound buffer size
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

        let status: ProbeStatus = findings.isEmpty ? .ok : .warning
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
}

// MARK: - WineAudioTestProbe

/// Runs WhiskyAudioTest.exe via Wine to exercise the audio stack.
///
/// This is the most complex probe. It runs a minimal Windows executable
/// that initializes WinMM waveOut and writes a short audio buffer,
/// then parses the JSON result line from stdout. The probe is designed
/// to be completely resilient -- it never crashes and always produces
/// a structured result.
public final class WineAudioTestProbe: AudioProbe, @unchecked Sendable {
    public let id = "wine-audio-test"
    public let displayName = "Wine Audio Stack Test"

    /// Curated WINEDEBUG preset for audio troubleshooting channels.
    private static let audioDebugPreset = "+mmdevapi,+dsound,+winmm"

    private let bottle: Bottle
    private let testExeURL: URL?
    private let logger = Logger(
        subsystem: "com.isaacmarovitz.Whisky",
        category: "WineAudioTestProbe"
    )

    public init(bottle: Bottle, testExeURL: URL?) {
        self.bottle = bottle
        self.testExeURL = testExeURL
    }

    public func run() async -> AudioProbeResult {
        await runTest(beep: false)
    }

    /// Runs the audio test with the --beep flag to play a test tone.
    public func runWithBeep() async -> AudioProbeResult {
        await runTest(beep: true)
    }

    @MainActor
    private func runTest(beep: Bool) async -> AudioProbeResult {
        guard let exeURL = testExeURL, FileManager.default.fileExists(atPath: exeURL.path) else {
            return AudioProbeResult(
                probeId: id,
                status: .skipped,
                summary: "Audio test helper not available",
                evidence: ["WhiskyAudioTest.exe not found in app bundle"]
            )
        }

        let exePath = exeURL.path
        var args = [exePath]
        if beep {
            args.append("--beep")
        }

        let environment = ["WINEDEBUG": Self.audioDebugPreset]

        var stdoutLines: [String] = []
        var stderrLines: [String] = []
        var exitCode: Int32 = -1

        do {
            let stream = try Wine.runWineProcess(
                name: "WhiskyAudioTest",
                args: args,
                bottle: bottle,
                environment: environment
            )

            for await output in stream {
                switch output {
                case .started:
                    break
                case let .message(line):
                    stdoutLines.append(line)
                case let .error(line):
                    stderrLines.append(line)
                case let .terminated(code):
                    exitCode = code
                }
            }
        } catch {
            return AudioProbeResult(
                probeId: id,
                status: .error,
                summary: "Failed to launch audio test",
                evidence: [
                    "Error: \(error.localizedDescription)",
                    "Exe path: \(exePath)"
                ]
            )
        }

        // Parse JSON result line from stdout
        let allOutput = stdoutLines.joined()
        return parseTestResult(
            output: allOutput,
            stderr: stderrLines,
            exitCode: exitCode,
            beep: beep
        )
    }

    private func parseTestResult(
        output: String, stderr: [String], exitCode: Int32, beep: Bool
    ) -> AudioProbeResult {
        var evidence: [String] = []
        evidence.append("Exit code: \(exitCode)")

        // Include relevant Wine stderr lines for troubleshooting
        let relevantStderr = stderr.filter { line in
            line.contains("mmdevapi") || line.contains("dsound") ||
                line.contains("winmm") || line.contains("err:") || line.contains("warn:")
        }
        if !relevantStderr.isEmpty {
            evidence.append("Wine audio log:")
            evidence.append(contentsOf: relevantStderr.prefix(20))
        }

        // Look for JSON result line in stdout
        let lines = output.components(separatedBy: .newlines)
        let jsonLine = lines.first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("{\"") }

        guard let json = jsonLine else {
            evidence.append("No JSON result line found in output")
            if !output.isEmpty {
                evidence.append("Raw output: \(output.prefix(500))")
            }
            return AudioProbeResult(
                probeId: id,
                status: .error,
                summary: "Audio test produced no result",
                evidence: evidence
            )
        }

        // Parse JSON
        guard let data = json.data(using: .utf8),
              let result = try? JSONDecoder().decode(AudioTestResult.self, from: data)
        else {
            evidence.append("Failed to parse JSON: \(json)")
            return AudioProbeResult(
                probeId: id,
                status: .error,
                summary: "Audio test result could not be parsed",
                evidence: evidence
            )
        }

        evidence.append("API: \(result.api)")

        if result.status == "ok" {
            if let rate = result.sampleRate {
                evidence.append("Sample rate: \(rate) Hz")
            }
            if let channels = result.channels {
                evidence.append("Channels: \(channels)")
            }
            evidence.append("Beep mode: \(beep)")

            return AudioProbeResult(
                probeId: id,
                status: .ok,
                summary: "Wine audio stack is functional (\(result.api))",
                evidence: evidence
            )
        } else {
            var findings: [AudioFinding] = []
            let codeStr = result.code.map { String($0) } ?? "unknown"
            findings.append(AudioFinding(
                id: "wine-audio-test-error",
                description: "Wine audio test failed via \(result.api)",
                confidence: .high,
                evidence: "Error code: \(codeStr)",
                suggestedAction: "Check Wine audio driver configuration"
            ))

            evidence.append("Error code: \(codeStr)")

            return AudioProbeResult(
                probeId: id,
                status: .warning,
                summary: "Wine audio test failed: \(result.api) error \(codeStr)",
                evidence: evidence,
                findings: findings
            )
        }
    }
}

/// Internal model for parsing WhiskyAudioTest.exe JSON output.
private struct AudioTestResult: Codable {
    let status: String
    let api: String
    let sampleRate: Int?
    let channels: Int?
    let beep: Bool?
    let code: Int?
}
