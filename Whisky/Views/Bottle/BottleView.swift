//
//  BottleView.swift
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
import UniformTypeIdentifiers
import WhiskyKit

enum BottleStage {
    case config
    case programs
    case processes
    case gameConfigs
}

struct BottleView: View {
    @ObservedObject var bottle: Bottle
    @State private var path = NavigationPath()
    @State private var programLoading: Bool = false
    @State private var showWinetricksSheet: Bool = false
    @State private var showDuplicate: Bool = false
    @State private var toast: ToastData?

    private let gridLayout = [GridItem(.adaptive(minimum: 100, maximum: .infinity))]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVGrid(columns: gridLayout, alignment: .center) {
                    ForEach(bottle.pinnedPrograms, id: \.id) { pinnedProgram in
                        PinView(
                            bottle: bottle,
                            program: pinnedProgram.program,
                            pin: pinnedProgram.pin,
                            path: $path,
                            toast: $toast
                        )
                    }
                    PinAddView(bottle: bottle)
                }
                .padding()
                Form {
                    NavigationLink(value: BottleStage.programs) {
                        Label("tab.programs", systemImage: "list.bullet")
                    }
                    NavigationLink(value: BottleStage.config) {
                        Label("tab.config", systemImage: "gearshape")
                    }
                    NavigationLink(value: BottleStage.processes) {
                        HStack {
                            Label("tab.processes", systemImage: "hockey.puck.circle")
                            let count = ProcessRegistry.shared.getProcessCount(for: bottle)
                            if count > 0 {
                                Text("\(count)")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.blue.opacity(0.15))
                                    .clipShape(Capsule())
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    NavigationLink(value: BottleStage.gameConfigs) {
                        Label("tab.gameConfigs", systemImage: "gamecontroller")
                    }
                }
                .formStyle(.grouped)
                .scrollDisabled(true)
            }
            .bottomBar {
                HStack {
                    Spacer()
                    Button("button.cDrive") {
                        bottle.openCDrive()
                    }
                    Button("button.terminal") {
                        bottle.openTerminal()
                    }
                    Button("button.winetricks") {
                        showWinetricksSheet.toggle()
                    }
                    Button("button.run") {
                        let panel = NSOpenPanel()
                        panel.allowsMultipleSelection = false
                        panel.canChooseDirectories = false
                        panel.canChooseFiles = true
                        panel.allowedContentTypes = [
                            UTType.exe,
                            UTType(exportedAs: "com.microsoft.msi-installer"),
                            UTType(exportedAs: "com.microsoft.bat"),
                            UTType(exportedAs: "com.microsoft.msix-package"),
                            UTType(exportedAs: "com.microsoft.appx-package"),
                            UTType(exportedAs: "com.microsoft.application-reference"),
                            UTType(exportedAs: "com.microsoft.windows-internet-shortcut")
                        ]
                        panel.directoryURL = bottle.url.appending(path: "drive_c")
                        panel.begin { result in
                            programLoading = true
                            Task(priority: .userInitiated) {
                                if result == .OK {
                                    if let url = panel.urls.first {
                                        do {
                                            // Auto-detect launcher and apply fixes if compatibility mode enabled
                                            // This completes synchronously on MainActor, ensuring settings are
                                            // persisted before Wine.runProgram() reads them
                                            LauncherDetection.detectAndApplyLauncherFixes(from: url, for: bottle)

                                            if url.pathExtension == "bat" {
                                                try await Wine.runBatchFile(url: url, bottle: bottle)
                                            } else {
                                                try await Wine.runProgram(at: url, bottle: bottle)
                                            }
                                            await MainActor.run {
                                                withAnimation {
                                                    toast = ToastData(
                                                        message: String(
                                                            localized: "status.launched \(url.lastPathComponent)"
                                                        ),
                                                        style: .success
                                                    )
                                                }
                                            }
                                        } catch {
                                            let errDesc = error.localizedDescription
                                            await MainActor.run {
                                                withAnimation {
                                                    toast = ToastData(
                                                        message: String(
                                                            localized: "status.launchFailed \(errDesc)"
                                                        ),
                                                        style: .error,
                                                        autoDismiss: false
                                                    )
                                                }
                                            }
                                        }
                                        await MainActor.run {
                                            programLoading = false
                                        }
                                    }
                                } else {
                                    await MainActor.run {
                                        programLoading = false
                                    }
                                }
                                await MainActor.run {
                                    updateStartMenu()
                                }
                            }
                        }
                    }
                    .disabled(programLoading)
                    if programLoading {
                        Spacer()
                            .frame(width: 10)
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .padding()
            }
            .onAppear {
                updateStartMenu()
            }
            .disabled(!bottle.isAvailable)
            .navigationTitle(bottle.settings.name)
            .navigationSubtitle(
                bottle.settings.graphicsBackend == .recommended
                    ? String(
                        localized: "bottle.subtitle.autoBackend \(GraphicsBackendResolver.resolve().displayName)"
                    )
                    : ""
            )
            .toast($toast)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("button.duplicateBottle", systemImage: "doc.on.doc") {
                        showDuplicate = true
                    }
                    .disabled(bottle.inFlight)
                }
            }
            .sheet(isPresented: $showWinetricksSheet) {
                WinetricksView(bottle: bottle)
            }
            .sheet(isPresented: $showDuplicate) {
                RenameView(
                    "duplicate.bottle.title",
                    name: nextDuplicateName(
                        baseName: bottle.settings.name,
                        existingNames: BottleVM.shared.bottles.map(\.settings.name)
                    )
                ) { newName in
                    Task {
                        do {
                            _ = try await bottle.duplicate(newName: newName)
                            await MainActor.run {
                                withAnimation {
                                    toast = ToastData(
                                        message: String(
                                            format: String(localized: "status.duplicateSuccess %@"),
                                            newName
                                        ),
                                        style: .success
                                    )
                                }
                            }
                        } catch {
                            await MainActor.run {
                                withAnimation {
                                    toast = ToastData(
                                        message: String(
                                            format: String(localized: "status.duplicateFailed %@"),
                                            error.localizedDescription
                                        ),
                                        style: .error
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .onChange(of: bottle.settings) { oldValue, newValue in
                guard oldValue != newValue else { return }
                // Trigger a reload
                BottleVM.shared.bottles = BottleVM.shared.bottles
            }
            .navigationDestination(for: BottleStage.self) { stage in
                switch stage {
                case .config:
                    ConfigView(bottle: bottle)
                case .programs:
                    ProgramsView(
                        bottle: bottle, path: $path
                    )
                case .processes:
                    RunningProcessesView(bottle: bottle)
                case .gameConfigs:
                    GameConfigurationView(bottle: bottle)
                }
            }
            .navigationDestination(for: Program.self) { program in
                ProgramView(program: program)
            }
        }
    }

    private func updateStartMenu() {
        bottle.updateInstalledPrograms()

        let startMenuPrograms = bottle.getStartMenuPrograms()
        for startMenuProgram in startMenuPrograms {
            for program in bottle.programs where
                // For some godforsaken reason "foo/bar" != "foo/Bar" so...
                program.url.path().caseInsensitiveCompare(startMenuProgram.url.path()) == .orderedSame {
                program.pinned = true
                guard !bottle.settings.pins.contains(where: { $0.url == program.url }) else { return }
                bottle.settings.pins.append(PinnedProgram(
                    name: program.url.deletingPathExtension().lastPathComponent,
                    url: program.url
                ))
            }
        }
    }
}
