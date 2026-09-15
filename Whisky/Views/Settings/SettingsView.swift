//
//  SettingsView.swift
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

struct SettingsView: View {
    @AppStorage("SUEnableAutomaticChecks") var whiskyUpdate = true
    @AppStorage("killOnTerminate") var killOnTerminate = true
    @AppStorage("showMenuBarExtra") var showMenuBarExtra = false
    @AppStorage("checkWhiskyWineUpdates") var checkWhiskyWineUpdates = true
    @AppStorage("defaultBottleLocation") var defaultBottleLocation = BottleData.defaultBottleDir
    @AppStorage("preferredTerminal") var preferredTerminal = "terminal"
    @AppStorage(Telemetry.consentDefaultsKey) private var telemetryConsentRaw: String = Telemetry.ConsentState
        .undecided.rawValue
    @State private var registeredRuntimes = WineRuntime.registeredRuntimes

    /// Mirrors the setup-flow opt-in; writing records the explicit choice.
    private var telemetryOptIn: Binding<Bool> {
        Binding(
            get: { telemetryConsentRaw == Telemetry.ConsentState.granted.rawValue },
            set: { Telemetry.setConsent(granted: $0) }
        )
    }

    var body: some View {
        Form {
            Section("settings.general") {
                Toggle("settings.toggle.kill.on.terminate", isOn: $killOnTerminate)
                Toggle("settings.toggle.menubar", isOn: $showMenuBarExtra)
                    .help("settings.toggle.menubar.help")
                Picker("settings.terminal", selection: $preferredTerminal) {
                    // installedTerminals should always include Terminal.app on macOS,
                    // but fall back to showing just Terminal if somehow empty
                    let terminals = TerminalApp.installedTerminals
                    ForEach(terminals.isEmpty ? [.terminal] : terminals) { terminal in
                        Text(terminal.displayName).tag(terminal.rawValue)
                    }
                }
                ActionView(
                    text: "settings.path",
                    subtitle: defaultBottleLocation.prettyPath(),
                    actionName: "create.browse"
                ) {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.canCreateDirectories = true
                    panel.directoryURL = BottleData.containerDir
                    panel.begin { result in
                        if result == .OK, let url = panel.urls.first {
                            defaultBottleLocation = url
                        }
                    }
                }
            }
            Section("settings.updates") {
                Toggle("settings.toggle.whisky.updates", isOn: $whiskyUpdate)
                Toggle("settings.toggle.whiskywine.updates", isOn: $checkWhiskyWineUpdates)
            }
            Section("Wine Runtimes") {
                ForEach(WineRuntime.availableRuntimes) { runtime in
                    WineRuntimeRow(runtime: runtime) {
                        WineRuntime.unregisterExternalRuntime(runtime)
                        registeredRuntimes = WineRuntime.registeredRuntimes
                    }
                }
                HStack {
                    Button("Refresh") {
                        registeredRuntimes = WineRuntime.registeredRuntimes
                    }
                    ActionView(
                        text: "Register Runtime",
                        subtitle: "Choose an external Wine runtime folder",
                        actionName: "create.browse"
                    ) {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        panel.canCreateDirectories = false
                        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
                            .appending(path: "Library")
                            .appending(path: "Application Support")
                        panel.begin { result in
                            if result == .OK, let url = panel.urls.first {
                                WineRuntime.registerExternalRuntime(
                                    name: url.lastPathComponent,
                                    root: url
                                )
                                registeredRuntimes = WineRuntime.registeredRuntimes
                            }
                        }
                    }
                }
            }
            GPTKSettingsSection()
            Section("settings.privacy") {
                Toggle("settings.toggle.telemetry", isOn: telemetryOptIn)
                    .help("setup.telemetry.consent.help")
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: ViewWidth.medium)
    }

}

#Preview {
    SettingsView()
}

private struct WineRuntimeRow: View {
    let runtime: WineRuntime
    let onRemove: () -> Void
    @State private var status = "Checking Wine version..."

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(runtime.name)
                Text("\(status) - \(runtime.root.prettyPath())")
                    .font(.caption)
                    .foregroundStyle(runtime.isUsable ? Color.secondary : Color.red)
            }
            Spacer()
            if WineRuntime.isRegisteredRuntime(runtime) {
                Button("Remove", action: onRemove)
            }
        }
        .task(id: runtime.id) {
            status = await Task.detached {
                runtime.statusDescription
            }.value
        }
    }
}
