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
    // Mutations happen through the binding wrapper.
    @Binding var diagnostics: WhiskyWineSetupDiagnostics
    // Delay to show the success checkmark before dismissing setup.
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
            let isInstalled = await Task.detached {
                WhiskyWineInstaller.install(from: capturedTarURL)
                return WhiskyWineInstaller.isWhiskyWineInstalled()
            }.value
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
            } else {
                installError = String(localized: "setup.whiskywine.error.installFailed")
            }
            guard isInstalled else { return }
            // Only cleanup tarball after verified successful installation
            // This preserves it for retry attempts if installation fails
            WhiskyWineInstaller.cleanupTarball(at: tarballLocation)
            try? await Task.sleep(for: Self.installSuccessDelay)
            proceed()
        }
    }
}
