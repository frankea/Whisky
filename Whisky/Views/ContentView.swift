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
    @EnvironmentObject var bottleVM: BottleVM
    @Binding var showSetup: Bool

    @State var selected: URL?
    @State var showBottleCreation: Bool = false
    @State var bottlesLoaded: Bool = false
    @State var showBottleSelection: Bool = false
    @State var newlyCreatedBottleURL: URL?
    @State var openedFileURL: URL?
    @State var triggerRefresh: Bool = false
    @State var refreshAnimation: Angle = .degrees(0)

    @State var toast: ToastData?
    @State var corruptRegistryBackupURL: URL?

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
            if alert.isRuntimeMissing {
                Button("bottle.creation.failed.runSetup") {
                    showSetup = true
                }
            }
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
        .alert(
            "bottle.registry.corrupt.title",
            isPresented: Binding(
                get: { corruptRegistryBackupURL != nil },
                set: { if !$0 { corruptRegistryBackupURL = nil } }
            ),
            presenting: corruptRegistryBackupURL
        ) { _ in
            Button("button.ok", role: .cancel) {}
        } message: { url in
            Text(String(
                format: String(localized: "bottle.registry.corrupt.message"),
                url.prettyPath()
            ))
        }
        .alert(
            "bottle.orphaned.title",
            isPresented: Binding(
                get: { !bottleVM.orphanedBottles.isEmpty },
                set: { if !$0 { bottleVM.orphanedBottles = [] } }
            )
        ) {
            Button("bottle.orphaned.reimport") {
                bottleVM.reimportOrphanedBottles()
            }
            Button("button.cancel", role: .cancel) {}
        } message: {
            Text(String(
                format: String(localized: "bottle.orphaned.message"),
                bottleVM.orphanedBottles.map(\.name).joined(separator: ", ")
            ))
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showBottleCreation.toggle()
                } label: {
                    Image(systemName: "plus")
                        .help("button.createBottle")
                }
                .accessibilityIdentifier("toolbar.createBottle")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    bottleVM.loadBottles()
                    if let bottle = bottleVM.bottles.first(where: { $0.url == selected }) {
                        Task { await bottle.updateInstalledPrograms() }
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
                bottles: bottleVM.bottles,
                toast: $toast
            )
        }
        .onChange(of: selected) { oldValue, _ in
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
            if QuickLaunch.handle(url) { return }
            openedFileURL = url
        }
        .dropDestination(for: URL.self) { urls, _ in
            // A Finder drop of anything the Run panel would accept opens the
            // same run-this-file flow, wherever on the window it lands.
            let runnable = ["exe", "msi", "bat", "msix", "appx", "url"]
            guard let url = urls.first(where: { runnable.contains($0.pathExtension.lowercased()) })
            else { return false }
            openedFileURL = url
            return true
        }
        .task {
            bottleVM.loadBottles()
            bottlesLoaded = true

            // Surface a registry that couldn't be read and was moved aside at
            // startup, so the reset bottle list doesn't pass silently (#61).
            corruptRegistryBackupURL = bottleVM.bottlesList.corruptRegistryBackupURL

            // Offer re-import for bottle folders the registry doesn't know
            // about — pairs with the corrupt-registry backup above: after a
            // registry reset the scan offers everything back (issue #145).
            bottleVM.scanForOrphanedBottles()

            // Deliberately does not select a bottle. The library is the landing
            // screen, and restoring a prefix selection would put the plumbing in
            // front of the thing people opened the app to do.

            // Skip the first-launch setup sheet and update check under UI testing:
            // tests run without a runtime, so this would otherwise drop a modal
            // sheet over the main window and race every toolbar interaction.
            guard !WhiskyApp.isUITesting else { return }

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
}
