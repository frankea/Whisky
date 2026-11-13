//
//  PerformanceConfigSection.swift
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

struct PerformanceConfigSection: View {
    @ObservedObject var bottle: Bottle
    @Binding var isExpanded: Bool

    /// Whether the VC++ runtime was found in the prefix; `nil` until checked.
    @State private var vcRedistDetected: Bool?
    /// Set once the installer is handed to Terminal, until the runtime is found.
    @State private var vcRedistInstallStarted = false

    var body: some View {
        Section("config.title.performance", isExpanded: $isExpanded) {
            Toggle(isOn: $bottle.settings.shaderCacheEnabled) {
                VStack(alignment: .leading) {
                    Text("config.shaderCache")
                    Text("config.shaderCache.info")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Toggle(isOn: $bottle.settings.disableAppNap) {
                VStack(alignment: .leading) {
                    Text("config.disableAppNap")
                    Text("config.disableAppNap.info")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            vcRedistRow
        }
        .task(id: bottle.url) {
            await refreshVCRedistStatus()
        }
        // Winetricks installs the runtime in Terminal; check again when the
        // user comes back from it.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshVCRedistStatus() }
        }
    }

    /// The VC++ runtime row (needed for Unity IL2CPP and other C++ games):
    /// shown as installed only once the runtime's DLLs are found in the prefix.
    @ViewBuilder
    private var vcRedistRow: some View {
        switch vcRedistDetected {
        case .some(true):
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("config.vcRedistInstalled")
            }
        case .some(false):
            Button {
                Task {
                    await Winetricks.runCommand(command: "vcrun2019", bottle: bottle)
                    vcRedistInstallStarted = true
                }
            } label: {
                HStack {
                    Image(systemName: "wrench.and.screwdriver")
                    VStack(alignment: .leading) {
                        Text("config.installVcRedist")
                        Text(
                            vcRedistInstallStarted
                                ? LocalizedStringKey("config.installVcRedist.pending")
                                : LocalizedStringKey("config.installVcRedist.info")
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
            }
        case .none:
            EmptyView()
        }
    }

    /// Looks for the runtime in the prefix off the main thread and keeps the
    /// stored flag in step with what is on disk.
    private func refreshVCRedistStatus() async {
        let prefixURL = bottle.url
        let installed = await Task.detached(priority: .utility) {
            VCRedistDetector.isInstalled(prefixURL: prefixURL)
        }.value
        vcRedistDetected = installed
        if installed {
            vcRedistInstallStarted = false
        }
        if bottle.settings.vcRedistInstalled != installed {
            bottle.settings.vcRedistInstalled = installed
        }
    }
}
