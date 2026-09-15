//
//  BottleCreationView.swift
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

struct BottleCreationView: View {
    @Binding var newlyCreatedBottleURL: URL?

    @State private var newBottleName: String = ""
    @State private var newBottleVersion: WinVersion = .win10
    @State private var selectedRuntimeIdentifier: String = WineRuntime.defaultIdentifier
    @State private var availableRuntimes = WineRuntime.availableRuntimes
    @State private var newBottleURL: URL = UserDefaults.standard.url(forKey: "defaultBottleLocation")
        ?? BottleData.defaultBottleDir
    @State private var nameValid: Bool = false
    @State private var locationIssue: BottleLocationValidation.ValidationResult?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                TextField("create.name", text: $newBottleName)
                    .onChange(of: newBottleName) { _, name in
                        nameValid = !name.isEmpty
                    }
                    .accessibilityIdentifier("create.nameField")

                Picker("create.win", selection: $newBottleVersion) {
                    ForEach(WinVersion.allCases.reversed(), id: \.self) {
                        Text($0.pretty())
                    }
                }

                Picker("Wine Runtime", selection: $selectedRuntimeIdentifier) {
                    ForEach(availableRuntimes) { runtime in
                        Text(runtime.name).tag(runtime.id)
                    }
                }

                ActionView(
                    text: "create.path",
                    subtitle: newBottleURL.prettyPath(),
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
                            newBottleURL = url
                            // Probing here is what makes macOS ask, while the sheet
                            // is still up and the request has visible cause.
                            locationIssue = validate(url)
                        }
                    }
                }

                if let locationIssue {
                    locationWarning(locationIssue)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("create.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("create.cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("create.cancelButton")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("create.create") {
                        submit()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!nameValid || locationIssue != nil)
                    .accessibilityIdentifier("create.createButton")
                }
            }
            .onSubmit {
                submit()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: ViewWidth.small)
        .onAppear {
            availableRuntimes = WineRuntime.availableRuntimes
            if !availableRuntimes.contains(where: { $0.id == selectedRuntimeIdentifier }) {
                selectedRuntimeIdentifier = WineRuntime.defaultIdentifier
            }
        }
    }

    @ViewBuilder
    private func locationWarning(_ issue: BottleLocationValidation.ValidationResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("create.location.problem", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(bottleLocationRefusal(issue) ?? "")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if case .accessDenied = issue, let settings = Self.filesAndFoldersSettingsURL {
                    Button("create.location.openPrivacySettings") { openURL(settings) }
                }
                Button("create.location.checkAgain") { locationIssue = validate(newBottleURL) }
            }
        }
        .padding(.vertical, 4)
    }

    private func validate(_ url: URL) -> BottleLocationValidation.ValidationResult? {
        let result = BottleLocationValidation.validate(at: url)
        return result == .valid ? nil : result
    }

    /// Nothing can re-present the consent prompt once it has been answered, so
    /// Settings is the only way back from a refusal.
    private static let filesAndFoldersSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"
    )

    func submit() {
        // The default location never passes through the panel, so it is probed
        // here or not at all.
        guard let issue = validate(newBottleURL) else {
            newlyCreatedBottleURL = BottleVM.shared.createNewBottle(
                bottleName: newBottleName,
                winVersion: newBottleVersion,
                bottleURL: newBottleURL,
                runtimeIdentifier: selectedRuntimeIdentifier
            )
            dismiss()
            return
        }
        locationIssue = issue
    }

}

#Preview {
    BottleCreationView(newlyCreatedBottleURL: .constant(nil))
}
