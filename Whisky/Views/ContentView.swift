//
//  ContentView.swift
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
import SemanticVersion
import SwiftUI
import UniformTypeIdentifiers
import WhiskyKit

struct ContentView: View {
    @AppStorage("selectedBottleURL") private var selectedBottleURL: URL?
    @EnvironmentObject var bottleVM: BottleVM
    @Binding var showSetup: Bool

    @State private var selected: URL?
    @State private var showBottleCreation: Bool = false
    @State private var bottlesLoaded: Bool = false
    @State private var showBottleSelection: Bool = false
    @State private var newlyCreatedBottleURL: URL?
    @State private var openedFileURL: URL?
    @State private var triggerRefresh: Bool = false
    @State private var refreshAnimation: Angle = .degrees(0)

    @State private var bottleFilter = ""
    @State private var toast: ToastData?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .toast($toast)
        .onReceive(NotificationCenter.default.publisher(for: .zombieProcessesCleaned)) { notification in
            if let count = notification.userInfo?["count"] as? Int, count > 0 {
                withAnimation {
                    toast = ToastData(
                        message: String(
                            format: String(localized: "cleanup.zombies.toast"),
                            count
                        ),
                        style: .info
                    )
                }
            }
        }
        .alert(
            "bottle.creation.failed.title",
            isPresented: Binding(
                get: { bottleVM.bottleCreationAlert != nil },
                set: { if !$0 { bottleVM.bottleCreationAlert = nil } }
            ),
            presenting: bottleVM.bottleCreationAlert
        ) { alert in
            Button("bottle.creation.failed.copyDiagnostics") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(alert.diagnostics, forType: .string)
            }
            Button("open.logs") {
                WhiskyApp.openLogsFolder()
            }
            Button("button.ok", role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showBottleCreation.toggle()
                } label: {
                    Image(systemName: "plus")
                        .help("button.createBottle")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    bottleVM.loadBottles()
                    if let bottle = bottleVM.bottles.first(where: { $0.url == selected }) {
                        bottle.updateInstalledPrograms()
                    }
                    triggerRefresh.toggle()
                    withAnimation(.default) {
                        refreshAnimation = .degrees(360)
                    } completion: {
                        refreshAnimation = .degrees(0)
                    }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .help("button.refresh")
                        .rotationEffect(refreshAnimation)
                }
            }
        }
        .sheet(isPresented: $showBottleCreation) {
            BottleCreationView(newlyCreatedBottleURL: $newlyCreatedBottleURL)
        }
        .sheet(isPresented: $showSetup) {
            SetupView(showSetup: $showSetup, firstTime: false)
        }
        .sheet(item: $openedFileURL) { url in
            FileOpenView(
                fileURL: url,
                currentBottle: selected,
                bottles: bottleVM.bottles
            )
        }
        .onChange(of: selected) { oldValue, newValue in
            selectedBottleURL = newValue

            // Check if previous bottle had running processes
            guard let oldURL = oldValue,
                  let oldBottle = bottleVM.bottles.first(where: { $0.url == oldURL })
            else { return }

            let count = ProcessRegistry.shared.getProcessCount(for: oldBottle)
            guard count > 0 else { return }

            switch oldBottle.settings.closeWithProcessesPolicy {
            case .alwaysKeepRunning:
                break
            case .alwaysStop:
                Wine.killBottle(bottle: oldBottle)
                ProcessRegistry.shared.clearRegistry(for: oldBottle.url)
            case .ask:
                showProcessCloseAlert(for: oldBottle)
            }
        }
        .handlesExternalEvents(preferring: [], allowing: ["*"])
        .onOpenURL { url in
            openedFileURL = url
        }
        .task {
            bottleVM.loadBottles()
            bottlesLoaded = true

            if !bottleVM.bottles.isEmpty || bottleVM.countActive() != 0 {
                if let bottle = bottleVM.bottles.first(where: { $0.url == selectedBottleURL && $0.isAvailable }) {
                    selected = bottle.url
                } else {
                    selected = bottleVM.bottles[0].url
                }
            }

            if !WhiskyWineInstaller.isWhiskyWineInstalled() {
                showSetup = true
            }
            let task = Task.detached {
                await WhiskyWineInstaller.shouldUpdateWhiskyWine()
            }
            let updateInfo = await task.value
            if updateInfo.0 {
                let alert = NSAlert()
                alert.messageText = String(localized: "update.whiskywine.title")
                alert.informativeText = String(
                    format: String(localized: "update.whiskywine.description"),
                    String(WhiskyWineInstaller.whiskyWineVersion()
                        ?? SemanticVersion(0, 0, 0)),
                    String(updateInfo.1)
                )
                alert.alertStyle = .warning
                alert.addButton(withTitle: String(localized: "update.whiskywine.update"))
                alert.addButton(withTitle: String(localized: "button.removeAlert.cancel"))

                let response = alert.runModal()

                if response == .alertFirstButtonReturn {
                    WhiskyWineInstaller.uninstall()
                    showSetup = true
                }
            }
        }
    }

    var sidebar: some View {
        ScrollViewReader { proxy in
            List(selection: $selected) {
                Section {
                    ForEach(filteredBottles) { bottle in
                        Group {
                            if bottle.inFlight {
                                HStack {
                                    Text(bottle.settings.name)
                                    Spacer()
                                    ProgressView().controlSize(.small)
                                }
                                .opacity(0.5)
                            } else if !bottle.isAvailable {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                        .font(.caption)
                                    Text(bottle.settings.name)
                                    Spacer()
                                    Button {
                                        Task { await bottle.remove(delete: false) }
                                    } label: {
                                        Image(systemName: "xmark.circle")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("button.removeFromList.help")
                                }
                                .opacity(0.6)
                                .selectionDisabled(true)
                            } else {
                                BottleListEntry(
                                    bottle: bottle,
                                    selected: $selected,
                                    refresh: $triggerRefresh,
                                    toast: $toast
                                )
                            }
                        }
                        .id(bottle.url)
                    }
                }
            }
            .animation(.default, value: bottleVM.bottles)
            .animation(.default, value: bottleFilter)
            .listStyle(.sidebar)
            .searchable(text: $bottleFilter, placement: .sidebar)
            .onChange(of: newlyCreatedBottleURL) { _, url in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    selected = url
                    withAnimation {
                        proxy.scrollTo(url, anchor: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder
    var detail: some View {
        if let bottle = selected {
            if let bottle = bottleVM.bottles.first(where: { $0.url == bottle }) {
                BottleView(bottle: bottle)
                    .disabled(bottle.inFlight)
                    .id(bottle.url)
            }
        } else {
            if bottleVM.bottles.isEmpty || bottleVM.countActive() == 0, bottlesLoaded {
                VStack {
                    Text("main.createFirst")
                    Button {
                        showBottleCreation.toggle()
                    } label: {
                        HStack {
                            Image(systemName: "plus")
                            Text("button.createBottle")
                        }
                        .padding(6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                }
            }
        }
    }

    var filteredBottles: [Bottle] {
        if bottleFilter.isEmpty {
            bottleVM.bottles
                .sorted()
        } else {
            bottleVM.bottles
                .filter { $0.settings.name.localizedCaseInsensitiveContains(bottleFilter) }
                .sorted()
        }
    }
}

// MARK: - Process Close Confirmation

extension ContentView {
    @MainActor
    func showProcessCloseAlert(for bottle: Bottle) {
        let checkbox = NSButton(
            checkboxWithTitle: String(localized: "bottle.close.remember"),
            target: nil,
            action: nil
        )
        let alert = NSAlert()
        alert.messageText = String(localized: "bottle.close.confirm.title")
        alert.informativeText = String(localized: "bottle.close.confirm.message")
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "bottle.close.keepRunning"))
        let stopButton = alert.addButton(withTitle: String(localized: "bottle.close.stopBottle"))
        stopButton.hasDestructiveAction = true
        alert.accessoryView = checkbox

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            // Keep Running (default)
            if checkbox.state == .on {
                bottle.settings.closeWithProcessesPolicy = .alwaysKeepRunning
            }
        } else if response == .alertSecondButtonReturn {
            // Stop Bottle
            if checkbox.state == .on {
                bottle.settings.closeWithProcessesPolicy = .alwaysStop
            }
            Wine.killBottle(bottle: bottle)
            ProcessRegistry.shared.clearRegistry(for: bottle.url)
        }
    }
}

#Preview {
    ContentView(showSetup: .constant(false))
        .environmentObject(BottleVM.shared)
}
