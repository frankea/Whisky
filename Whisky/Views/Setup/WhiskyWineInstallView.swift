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
    @Binding var tarLocation: URL
    @Binding var path: [SetupStage]
    @Binding var showSetup: Bool
    @Binding var diagnostics: WhiskyWineSetupDiagnostics

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
            Task.detached {
                await MainActor.run {
                    diagnostics.installStartedAt = Date()
                    diagnostics.record("Entered install stage")
                }
                await WhiskyWineInstaller.install(from: tarLocation)
                await MainActor.run {
                    diagnostics.installFinishedAt = Date()
                    diagnostics.record("Install finished (installer returned)")
                    if WhiskyWineInstaller.isWhiskyWineInstalled() {
                        installing = false
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(2))
                            proceed()
                        }
                    } else {
                        installError = String(localized: "setup.whiskywine.error.installFailed")
                    }
                }
            }
        }
    }

    @MainActor
    func proceed() {
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

            HStack(spacing: 12) {
                Button("setup.retry") {
                    installError = nil
                    installing = true
                    Task.detached {
                        await WhiskyWineInstaller.install(from: tarLocation)
                        await MainActor.run {
                            diagnostics.installFinishedAt = Date()
                            diagnostics.record("Install finished (retry)")
                            installing = false
                            proceed()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("setup.quit") {
                    showSetup = false
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
    }
}
