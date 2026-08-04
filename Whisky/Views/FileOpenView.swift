//
//  FileOpenView.swift
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

import os.log
import SwiftUI
import WhiskyKit

private let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "FileOpenView")

struct FileOpenView: View {
    var fileURL: URL
    var currentBottle: URL?
    var bottles: [Bottle]
    @Binding var toast: ToastData?

    @State private var selection: URL = .init(filePath: "")
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Picker("run.bottle", selection: $selection) {
                    ForEach(bottles, id: \.self) {
                        Text($0.settings.name)
                            .tag($0.url)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .formStyle(.grouped)
            .navigationTitle(String(format: String(localized: "run.title"), fileURL.lastPathComponent))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("create.cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("button.run") {
                        run()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: ViewWidth.small)
        .onAppear {
            // Makes sure there are more than 0 bottles.
            // Otherwise, it will crash on the nil cascade
            if bottles.count <= 0 {
                dismiss()
                return
            }

            selection = bottles.first(where: { $0.url == currentBottle })?.url ?? bottles[0].url

            if bottles.count == 1 {
                // If the user only has one bottle
                // there's nothing for them to select
                run()
            }
        }
    }

    func run() {
        if let bottle = bottles.first(where: { $0.url == selection }) {
            Task.detached(priority: .userInitiated) {
                do {
                    // Auto-detect launcher and apply fixes if compatibility mode enabled
                    // This completes synchronously on MainActor, ensuring settings are
                    // persisted before Wine.runProgram() reads them
                    await MainActor.run {
                        LauncherFixes.detectAndApply(from: fileURL, for: bottle)
                        Telemetry.capture(.firstProgramLaunchAttempted)
                    }

                    if fileURL.pathExtension == "bat" {
                        try await Wine.runBatchFile(
                            url: fileURL,
                            bottle: bottle
                        )
                    } else {
                        try await Wine.runProgram(at: fileURL, bottle: bottle)
                    }
                } catch {
                    // Surface the failure on the presenting view's toast (the sheet
                    // dismisses immediately, so a local toast wouldn't be seen) —
                    // otherwise a launch error here, including DXMT's actionable
                    // payloadMissing, vanishes silently.
                    let errDesc = error.localizedDescription
                    logger.error(
                        "Failed to launch \(fileURL.lastPathComponent, privacy: .public): \(errDesc, privacy: .public)"
                    )
                    await MainActor.run {
                        withAnimation {
                            toast = ToastData(
                                message: String(localized: "status.launchFailed \(errDesc)"),
                                style: .error,
                                autoDismiss: false
                            )
                        }
                    }
                }
            }
            dismiss()
        } else {
            // onAppear seeds `selection` from `bottles`, so this should not
            // happen — but never leave the sheet stuck open on a stale selection.
            logger.error("Run requested but no bottle matched the selection")
            dismiss()
        }
    }
}
