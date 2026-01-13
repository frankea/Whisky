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

import SwiftUI
import WhiskyKit

struct WhiskyWineInstallView: View {
    @State var installing: Bool = true
    @State private var installError: String?
    @Binding var tarLocation: URL
    @Binding var path: [SetupStage]
    @Binding var showSetup: Bool

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
                if let installError {
                    errorView(error: installError)
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
                do {
                    try await WhiskyWineInstaller.install(from: tarLocation)
                    await MainActor.run {
                        installing = false
                    }
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    await proceed()
                } catch {
                    await MainActor.run {
                        installing = false
                        installError = error.localizedDescription
                    }
                }
            }
        }
    }

    private func errorView(error: String) -> some View {
        VStack(spacing: 16) {
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
                Button("setup.retry") {
                    retryInstall()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)

                Button("setup.quit") {
                    showSetup = false
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.top, 8)
        }
        .padding()
    }

    private func retryInstall() {
        installError = nil
        installing = true
        Task.detached {
            do {
                try await WhiskyWineInstaller.install(from: tarLocation)
                await MainActor.run {
                    installing = false
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await proceed()
            } catch {
                await MainActor.run {
                    installing = false
                    installError = error.localizedDescription
                }
            }
        }
    }

    @MainActor
    func proceed() {
        showSetup = false
    }
}
