//
//  BetaEngineSection.swift
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

import SemanticVersion
import SwiftUI
import WhiskyKit

/// Which engine an engine switch installs.
enum EngineSwitchTarget: Identifiable {
    /// A specific beta build from GitHub Releases.
    case beta(EngineRelease)
    /// The engine the version feed names.
    case stable

    var id: String {
        switch self {
        case let .beta(release): release.tag
        case .stable: "stable"
        }
    }

    var release: EngineRelease? {
        if case let .beta(release) = self {
            return release
        }
        return nil
    }
}

/// Opt-in access to beta engine builds, and the way back to stable.
///
/// Betas used to be installed by hand from Terminal, which kept most people
/// from testing them. This installs the newest beta through the same verified
/// download and staged install the stable engine uses, and switching back
/// reinstalls the stable engine the same way.
struct BetaEngineSection: View {
    @Environment(\.openURL) private var openURL
    @State private var installedVersion: SemanticVersion?
    @State private var installedBeta: InstalledBetaRecord?
    /// The stable engine's version, read once the section appears; used to
    /// say when a beta's fixes have reached stable.
    @State private var stableVersion: SemanticVersion?
    @State private var checking = false
    @State private var offeredBeta: EngineRelease?
    @State private var confirmStable = false
    @State private var infoMessage: String?
    @State private var errorMessage: String?
    @State private var runningBottles: [String] = []
    @State private var switchTarget: EngineSwitchTarget?

    var body: some View {
        Section {
            LabeledContent("settings.betaEngine.installed", value: installedDescription)
            if let installedBeta {
                onBetaContent(installedBeta)
            } else {
                Text("settings.betaEngine.help")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("settings.betaEngine.try") {
                        Task { await checkForBeta() }
                    }
                    .disabled(checking)
                    progress
                }
            }
        } header: {
            Text("settings.betaEngine")
        }
        .task {
            refresh()
            guard installedBeta != nil else { return }
            stableVersion = try? await BetaEngine.fetchStableVersion()
        }
        .alert(
            offeredBeta.map {
                String(format: String(localized: "settings.betaEngine.confirm.title"), String($0.version))
            } ?? "",
            isPresented: isPresented($offeredBeta),
            presenting: offeredBeta
        ) { release in
            Button("settings.betaEngine.confirm.install") {
                Task { await startSwitch(to: .beta(release)) }
            }
            Button("settings.betaEngine.releaseNotes") {
                openURL(release.notesURL)
            }
            Button("button.removeAlert.cancel", role: .cancel) {}
        } message: { _ in
            Text("settings.betaEngine.confirm.message")
        }
        .alert("settings.betaEngine.returnToStable.title", isPresented: $confirmStable) {
            Button("settings.betaEngine.returnToStable") {
                Task { await startSwitch(to: .stable) }
            }
            Button("button.removeAlert.cancel", role: .cancel) {}
        } message: {
            Text("settings.betaEngine.returnToStable.message")
        }
        .alert("settings.betaEngine", isPresented: isPresented($infoMessage)) {
            Button("button.ok", role: .cancel) {}
        } message: {
            Text(infoMessage ?? "")
        }
        .alert("settings.betaEngine.error.title", isPresented: isPresented($errorMessage)) {
            Button("button.ok", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert(
            "settings.betaEngine.running.title",
            isPresented: .init(
                get: { !runningBottles.isEmpty },
                set: {
                    if !$0 {
                        runningBottles = []
                    }
                }
            )
        ) {
            Button("button.ok", role: .cancel) {}
        } message: {
            Text(String(
                format: String(localized: "settings.betaEngine.running.message"),
                runningBottles.formatted(.list(type: .and))
            ))
        }
        .sheet(item: $switchTarget, onDismiss: refresh) { target in
            EngineSwitchSheet(release: target.release, isPresented: isPresented($switchTarget))
        }
    }

    @ViewBuilder
    private func onBetaContent(_ record: InstalledBetaRecord) -> some View {
        if let stableVersion, record.isSuperseded(byStable: stableVersion) {
            Label(
                String(format: String(localized: "settings.betaEngine.superseded"), String(stableVersion)),
                systemImage: "info.circle"
            )
            .font(.callout)
        } else {
            Text("settings.betaEngine.onBeta.help")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        Link("settings.betaEngine.releaseNotes", destination: record.notesURL)
            .font(.callout)
        HStack {
            Button("settings.betaEngine.returnToStable") {
                confirmStable = true
            }
            .disabled(checking)
            Button("settings.betaEngine.checkNewer") {
                Task { await checkForBeta() }
            }
            .disabled(checking)
            progress
        }
    }

    @ViewBuilder
    private var progress: some View {
        if checking {
            ProgressView()
                .controlSize(.small)
        }
    }

    private var installedDescription: String {
        if let installedBeta {
            return String(
                format: String(localized: "settings.betaEngine.installed.beta"),
                installedBeta.version.map { String($0) } ?? installedBeta.tag
            )
        }
        guard let installedVersion else {
            return String(localized: "settings.betaEngine.installed.none")
        }
        return String(installedVersion)
    }

    private func refresh() {
        installedVersion = WhiskyWineInstaller.whiskyWineVersion()
        installedBeta = BetaEngine.installedBeta()
    }

    /// Looks up the newest beta and offers it, or says why there is nothing
    /// to offer.
    @MainActor
    private func checkForBeta() async {
        checking = true
        defer { checking = false }
        do {
            guard let latest = try await BetaEngine.fetchLatestBeta() else {
                infoMessage = String(localized: "settings.betaEngine.none")
                return
            }
            if latest.tag == installedBeta?.tag {
                infoMessage = String(localized: "settings.betaEngine.upToDate")
                return
            }
            offeredBeta = latest
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Opens the download and install sheet, once no bottle is running a
    /// program: replacing the engine under a running wineserver would pull
    /// its binaries out from under it.
    @MainActor
    private func startSwitch(to target: EngineSwitchTarget) async {
        var running: [String] = []
        for bottle in BottleVM.shared.bottles {
            let tracked = ProcessRegistry.shared.getProcessCount(for: bottle) > 0
            if tracked {
                running.append(bottle.settings.name)
            } else if await Wine.isWineserverRunning(for: bottle) {
                running.append(bottle.settings.name)
            }
        }
        guard running.isEmpty else {
            runningBottles = running
            return
        }
        switchTarget = target
    }

    /// A Bool binding over an optional, for alerts and sheets keyed on it.
    private func isPresented(_ value: Binding<(some Any)?>) -> Binding<Bool> {
        Binding(
            get: { value.wrappedValue != nil },
            set: {
                if !$0 {
                    value.wrappedValue = nil
                }
            }
        )
    }
}

/// Downloads and installs one engine build, reusing the setup flow's stages:
/// the same resumable download, SHA-256 check, and staged install that keeps
/// the current engine until the new one is in place.
struct EngineSwitchSheet: View {
    let release: EngineRelease?
    @Binding var isPresented: Bool
    @State private var path: [SetupStage] = []
    @State private var tarLocation: URL = .init(fileURLWithPath: "")
    @State private var diagnostics = WhiskyWineSetupDiagnostics()

    var body: some View {
        NavigationStack(path: $path) {
            WhiskyWineDownloadView(
                tarLocation: $tarLocation,
                path: $path,
                showSetup: $isPresented,
                diagnostics: $diagnostics,
                release: release
            )
            .navigationBarBackButtonHidden(true)
            .navigationDestination(for: SetupStage.self) { stage in
                if stage == .whiskyWineInstall {
                    WhiskyWineInstallView(
                        tarLocation: $tarLocation,
                        path: $path,
                        showSetup: $isPresented,
                        diagnostics: $diagnostics,
                        release: release
                    )
                    .navigationBarBackButtonHidden(true)
                }
            }
        }
        .padding()
        .interactiveDismissDisabled()
    }
}
