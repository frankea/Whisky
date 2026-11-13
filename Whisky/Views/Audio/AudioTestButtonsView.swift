//
//  AudioTestButtonsView.swift
//  Whisky
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

import SwiftUI
import WhiskyKit

/// Test button row for Wine audio testing with tone confirmation flow.
struct AudioTestButtonsView: View {
    @ObservedObject var bottle: Bottle
    var onStatusUpdate: (AudioStatus) -> Void
    var onTestComplete: ([AudioProbeResult]) -> Void
    var testExeURL: URL?

    @State private var isTestRunning: Bool = false
    @State private var isToneRunning: Bool = false
    @State private var showToneConfirmation: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                testWineAudioButton
                playTestToneButton
                refreshButton
                if isTestRunning || isToneRunning {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if showToneConfirmation {
                toneConfirmationRow
            }
        }
    }

    // MARK: - Test Wine Audio

    private var testWineAudioButton: some View {
        Button("audio.test.wine") {
            runAllProbes()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(isTestRunning || isToneRunning)
    }

    private func runAllProbes() {
        isTestRunning = true
        Task { @MainActor in
            let monitor = AudioDeviceMonitor()
            let probes: [any AudioProbe] = [
                CoreAudioDeviceProbe(monitor: monitor),
                WineRegistryAudioProbe(bottle: bottle),
                WineAudioTestProbe(bottle: bottle, testExeURL: testExeURL)
            ]

            var results: [AudioProbeResult] = []
            for probe in probes {
                let result = await probe.run()
                results.append(result)
            }

            let status = deriveOverallStatus(from: results)
            onStatusUpdate(status)
            onTestComplete(results)
            isTestRunning = false
        }
    }

    // MARK: - Play Test Tone

    private var playTestToneButton: some View {
        Button("audio.test.tone") {
            runToneTest()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(isTestRunning || isToneRunning)
    }

    private func runToneTest() {
        isToneRunning = true
        showToneConfirmation = false
        Task { @MainActor in
            let probe = WineAudioTestProbe(bottle: bottle, testExeURL: testExeURL)
            _ = await probe.runWithBeep()
            isToneRunning = false
            showToneConfirmation = true
        }
    }

    // MARK: - Tone Confirmation

    private var toneConfirmationRow: some View {
        HStack(spacing: 8) {
            Text("audio.test.toneQuestion")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("audio.test.toneYes") {
                onStatusUpdate(.healthy)
                showToneConfirmation = false
            }
            .controlSize(.small)
            Button("audio.test.toneNo") {
                let notAudible = String(localized: "audio.test.toneNotAudible")
                let finding = AudioFinding(
                    id: "tone-not-audible",
                    description: notAudible,
                    confidence: .high,
                    evidence: String(localized: "audio.test.toneNotAudible.evidence"),
                    suggestedAction: String(localized: "audio.test.toneNotAudible.action")
                )
                let result = AudioProbeResult(
                    probeId: "tone-confirmation",
                    status: .error,
                    summary: notAudible,
                    findings: [finding]
                )
                onStatusUpdate(.broken(primaryIssue: notAudible))
                onTestComplete([result])
                showToneConfirmation = false
            }
            .controlSize(.small)
        }
    }

    // MARK: - Refresh

    private var refreshButton: some View {
        Button {
            let monitor = AudioDeviceMonitor()
            let device = monitor.defaultOutputDevice()
            if device != nil {
                // Device found; status is at least not broken at the CoreAudio level.
                // Full status requires running probes, so we just signal unknown to refresh the UI.
                onStatusUpdate(.unknown)
            } else {
                onStatusUpdate(.broken(primaryIssue: String(localized: "audio.status.noOutputDevice")))
            }
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(isTestRunning || isToneRunning)
    }

    // MARK: - Status Derivation

    private func deriveOverallStatus(from results: [AudioProbeResult]) -> AudioStatus {
        let hasError = results.contains { $0.status == .error }
        let hasWarning = results.contains { $0.status == .warning }
        let allFindings = results.flatMap(\.findings)

        if hasError {
            let primaryIssue = allFindings.first(where: { $0.confidence == .high })?.description
                ?? allFindings.first?.description ?? String(localized: "audio.status.stackError")
            return .broken(primaryIssue: primaryIssue)
        }

        if hasWarning {
            let primaryIssue = allFindings.first?.description
                ?? String(localized: "audio.status.potentialIssue")
            return .degraded(primaryIssue: primaryIssue)
        }

        return .healthy
    }
}
