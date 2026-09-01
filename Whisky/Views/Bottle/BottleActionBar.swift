//
//  BottleActionBar.swift
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

/// The four actions along the bottom of a bottle.
struct BottleActionBar: View {
    @ObservedObject var bottle: Bottle
    @Binding var showWinetricksSheet: Bool
    @Binding var programLoading: Bool
    @Binding var toast: ToastData?
    /// Called after a launch so the caller can refresh what it keeps in step
    /// with the prefix, the start menu among it.
    let onLaunch: () async -> Void

    /// The bar's four actions.
    ///
    /// Running a program is the reason the app exists, so it is the only
    /// prominent control here; the other three were visually identical to it
    /// before, which made opening a terminal look as important as launching a
    /// game.
    ///
    /// Liquid Glass where the system has it. GlassEffectContainer is macOS 26
    /// only and is what lets the capsules blend instead of stacking their own
    /// layers, so the older path is the same buttons in bordered styles, which
    /// still carries the emphasis.
    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 8) {
                buttons
            }
        } else {
            buttons
        }
    }

    @ViewBuilder
    private var buttons: some View {
        HStack {
            Spacer()
            Button("button.cDrive") {
                bottle.openCDrive()
            }
            .glassButton()
            .accessibilityIdentifier("bottle.openCDrive")
            Button("button.terminal") {
                bottle.openTerminal()
            }
            .glassButton()
            .accessibilityIdentifier("bottle.openTerminal")
            Button("button.winetricks") {
                showWinetricksSheet.toggle()
            }
            .glassButton()
            .accessibilityIdentifier("bottle.openWinetricks")
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
                                    LauncherFixes.detectAndApply(from: url, for: bottle)

                                    Telemetry.capture(.firstProgramLaunchAttempted)
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
                        await onLaunch()
                    }
                }
            }
            // Running a program is the reason the app exists, so it is
            // the only prominent control on this bar.
            .glassButton(prominent: true)
            .accessibilityIdentifier("bottle.runProgram")
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
}

private extension View {
    /// Glass on macOS 26, bordered before it. The emphasis is the point and it
    /// survives either way.
    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else {
            if prominent {
                buttonStyle(.borderedProminent)
            } else {
                buttonStyle(.bordered)
            }
        }
    }
}
