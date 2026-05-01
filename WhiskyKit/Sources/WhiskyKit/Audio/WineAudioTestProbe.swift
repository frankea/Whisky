//
//  WineAudioTestProbe.swift
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

        guard let processResult = await executeWineProcess(args: args, environment: environment, exePath: exePath)
        else {
            return AudioProbeResult(
                probeId: id,
                status: .error,
                summary: "Failed to launch audio test",
                evidence: ["Error launching Wine process", "Exe path: \(exePath)"]
            )
        }

        return parseTestResult(
            output: processResult.stdout,
            stderr: processResult.stderr,
            exitCode: processResult.exitCode,
            beep: beep
        )
    }

    @MainActor
    private func executeWineProcess(
        args: [String],
        environment: [String: String],
        exePath: String
    ) async -> ProcessResult? {
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

            return ProcessResult(
                stdout: stdoutLines.joined(),
                stderr: stderrLines,
                exitCode: exitCode
            )
        } catch {
            return nil
        }
    }

    private func parseTestResult(
        output: String, stderr: [String], exitCode: Int32, beep: Bool
    ) -> AudioProbeResult {
        var evidence: [String] = []
        evidence.append("Exit code: \(exitCode)")

        let relevantStderr = stderr.filter { line in
            line.contains("mmdevapi") || line.contains("dsound") ||
                line.contains("winmm") || line.contains("err:") || line.contains("warn:")
        }
        if !relevantStderr.isEmpty {
            evidence.append("Wine audio log:")
            evidence.append(contentsOf: relevantStderr.prefix(20))
        }

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

        return buildResultFromJSON(result, evidence: &evidence, beep: beep)
    }

    private func buildResultFromJSON(
        _ result: AudioTestResult, evidence: inout [String], beep: Bool
    ) -> AudioProbeResult {
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
                status: .passed,
                summary: "Wine audio stack is functional (\(result.api))",
                evidence: evidence
            )
        }

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

    private struct ProcessResult {
        let stdout: String
        let stderr: [String]
        let exitCode: Int32
    }
}

/// Internal model for parsing WhiskyAudioTest.exe JSON output.
struct AudioTestResult: Codable {
    let status: String
    let api: String
    let sampleRate: Int?
    let channels: Int?
    let beep: Bool?
    let code: Int?
}
