//
//  DependencyConfigSection.swift
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

/// Dependencies section for the bottle Config view.
///
/// Shows 4 standard Windows components (Visual C++ Runtime, .NET Framework,
/// DirectX, DirectX Audio) with installation status, confidence indicator,
/// last-checked timestamp, and Install action. Manages its own state and
/// presents ``DependencyInstallSheet`` via a sheet binding.
struct DependencyConfigSection: View {
    @ObservedObject var bottle: Bottle

    @State private var statuses: [DependencyStatus] = []
    @State private var isLoading: Bool = true
    @State private var selectedDependency: DependencyDefinition?

    var body: some View {
        Section {
            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking installed dependencies\u{2026}")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(statuses) { status in
                    dependencyRow(status)
                }
            }
        } header: {
            HStack {
                Label("Dependencies", systemImage: "shippingbox")
                Spacer()
                Button {
                    loadDependencies()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .disabled(isLoading)
                .help("Re-check all dependency statuses")
            }
        }
        .onAppear {
            loadDependencies()
        }
        .sheet(item: $selectedDependency) { definition in
            DependencyInstallSheet(definition: definition, bottle: bottle)
                .frame(minWidth: 500, minHeight: 400)
        }
    }

    // MARK: - Row View

    @ViewBuilder
    private func dependencyRow(_ depStatus: DependencyStatus) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(depStatus.definition.displayName)
                        .font(.body)
                    Text(depStatus.definition.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                statusBadge(depStatus.status)

                if depStatus.confidence == .cached || depStatus.confidence == .heuristic {
                    Text("(\(depStatus.confidence.rawValue))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if !isInstalled(depStatus.status) {
                    Button("Install") {
                        selectedDependency = depStatus.definition
                    }
                    .controlSize(.small)
                }
            }

            dependencyRowDetails(depStatus)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func dependencyRowDetails(_ depStatus: DependencyStatus) -> some View {
        HStack(spacing: 4) {
            if let lastChecked = depStatus.lastChecked {
                Text("Checked ")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                +
                Text(lastChecked, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                +
                Text(" ago")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            DisclosureGroup {
                Text(depStatus.definition.winetricksVerbs.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } label: {
                Text("Details")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 200)
        }
    }

    // MARK: - Status Badge

    @ViewBuilder
    private func statusBadge(_ status: DependencyInstallStatus) -> some View {
        switch status {
        case .installed:
            Label("Installed", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .notInstalled:
            Label("Not Installed", systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        case .partiallyInstalled:
            Label("Partially Installed", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.yellow)
        case .unknown:
            Label("Unknown", systemImage: "questionmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.gray)
        }
    }

    // MARK: - Helpers

    private func isInstalled(_ status: DependencyInstallStatus) -> Bool {
        if case .installed = status { return true }
        return false
    }

    private func loadDependencies() {
        isLoading = true
        Task {
            let results = await DependencyManager.checkDependencies(for: bottle)
            await MainActor.run {
                statuses = results
                isLoading = false
            }
        }
    }
}
