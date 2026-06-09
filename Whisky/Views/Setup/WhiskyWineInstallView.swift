//
//  WhiskyWineInstallView.swift
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

import AppKit
import SwiftUI
import WhiskyKit

struct WhiskyWineInstallView: View {
    @State var installing: Bool = true
    @State private var installError: String?
    @State private var hasStartedInstallation: Bool = false
    @Binding var tarLocation: URL
    @Binding var path: [SetupStage]
    @Binding var showSetup: Bool
    /// Shared diagnostics recorder for the setup flow, capturing events across download and install stages.
    @Binding var diagnostics: WhiskyWineSetupDiagnostics
    /// Delay to show the success checkmark before dismissing setup.
    private static let installSuccessDelay: Duration = .seconds(2)

    var body: some View {
        VStack {
            VStack {
                Text("setup.whiskywine.install")
                    .font(.title)
                    .fontWeight(.bold)
                Text("setup.whiskywine.install.subtitle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if let error = installError {
                    errorView(error: error)
                } else if installing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .frame(width: 80)
                } else {
                    Image(systemName: "checkmark.circle")
                        .resizable()
                        .frame(width: 80, height: 80)
                        .foregroundStyle(.green)
                }
                Spacer()
            }
            Spacer()
        }
        .frame(width: 400, height: 200)
        .onAppear {
            // Guard against multiple onAppear calls from NavigationStack
            guard !hasStartedInstallation else { return }
            hasStartedInstallation = true
            startInstallation(
                startLogMessage: "Entered install stage",
                finishLogMessage: "Install finished (installer returned)"
            )
        }
    }

    @MainActor
    private func proceed() {
        showSetup = false
    }

    private func errorView(error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "xmark.circle")
                .resizable()
                .foregroundStyle(.red)
                .frame(width: 80, height: 80)
                .padding(.bottom, 8)
            Text(error)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            diagnosticsButtons(error: error)
            retryButtons()
        }
        .padding()
    }

    private func diagnosticsButtons(error: String) -> some View {
        HStack(spacing: 12) {
            Button("setup.whiskywine.copyDiagnostics") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    diagnostics.reportString(stage: "install", error: error),
                    forType: .string
                )
            }
            .buttonStyle(.bordered)

            Button("open.logs") {
                WhiskyApp.openLogsFolder()
            }
            .buttonStyle(.bordered)
        }
    }

    private func retryButtons() -> some View {
        HStack(spacing: 12) {
            Button("setup.retry") {
                guard !installing else { return }
                installError = nil
                installing = true
                startInstallation(
                    startLogMessage: "Install started (retry)",
                    finishLogMessage: "Install finished (retry)"
                )
            }
            .buttonStyle(.borderedProminent)
            .disabled(installing)

            Button("setup.quit") {
                showSetup = false
            }
            .buttonStyle(.bordered)
        }
    }

    private func startInstallation(startLogMessage: String, finishLogMessage: String) {
        Task {
            let attemptStartedAt = Date()
            let attemptNumber = diagnostics.installAttempts.count + 1
            diagnostics.installFinishedAt = nil
            diagnostics.installStartedAt = attemptStartedAt
            diagnostics.record("Install attempt \(attemptNumber) started")
            diagnostics.record(startLogMessage)

            let capturedTarURL = tarLocation
            diagnostics.record("Invoking WhiskyWineInstaller.install(from:) in detached task")
            let (installFailureMessage, isInstalled) = await Self.performInstall(tarball: capturedTarURL)
            if let installFailureMessage {
                diagnostics.record("Install failed: \(installFailureMessage)")
            }
            let installStatus = isInstalled ? "installed" : "not installed"
            diagnostics.record(
                "Detached WhiskyWineInstaller.install(from:) task completed: \(installStatus)"
            )
            let attemptFinishedAt = Date()
            diagnostics.installFinishedAt = attemptFinishedAt
            diagnostics.recordInstallAttempt(
                startedAt: attemptStartedAt,
                finishedAt: attemptFinishedAt,
                succeeded: isInstalled
            )
            let attemptResult = isInstalled ? "success" : "failed"
            diagnostics.record("Install attempt \(attemptNumber) finished (\(attemptResult))")
            diagnostics.record(finishLogMessage)
            installing = false
            if isInstalled {
                installError = nil
            } else if let installFailureMessage {
                installError = String(
                    format: String(localized: "setup.whiskywine.error.installFailed.detail"),
                    Self.shortened(installFailureMessage)
                )
            } else {
                installError = String(localized: "setup.whiskywine.error.installFailed")
            }
            guard isInstalled else { return }
            // Only cleanup tarball after verified successful installation
            // This preserves it for retry attempts if installation fails
            WhiskyWineInstaller.cleanupTarball(at: capturedTarURL)
            try? await Task.sleep(for: Self.installSuccessDelay)
            proceed()
        }
    }

    /// Runs the install and post-install verification off the main actor, keeping
    /// the plist read off the main thread. Returns the (Sendable) failure message
    /// (`nil` on success) and whether the runtime is now present.
    private static func performInstall(tarball: URL) async -> (failureMessage: String?, installed: Bool) {
        await Task.detached {
            do {
                try WhiskyWineInstaller.install(from: tarball)
                return (nil, WhiskyWineInstaller.isWhiskyWineInstalled())
            } catch {
                return (error.localizedDescription, false)
            }
        }.value
    }

    /// Trims a possibly long, multi-line underlying error (e.g. raw `tar` output)
    /// down to a single short line for the install error message. The full text
    /// is preserved in the diagnostics report.
    private static func shortened(_ message: String, limit: Int = 200) -> String {
        let firstLine = message.split(whereSeparator: \.isNewline).first.map(String.init) ?? message
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        return trimmed.count <= limit ? trimmed : String(trimmed.prefix(limit)) + "…"
    }
}
