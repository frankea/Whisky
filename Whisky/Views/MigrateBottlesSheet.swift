//
//  MigrateBottlesSheet.swift
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

/// Lets the user import bottles created by the archived original Whisky app, which this
/// fork doesn't see automatically because it uses a different bundle identifier. Bottles
/// are referenced in place (not copied), so the import is non-destructive.
struct MigrateBottlesSheet: View {
    @EnvironmentObject var bottleVM: BottleVM
    @Environment(\.dismiss) private var dismiss

    @State private var rows: [Row] = []
    @State private var didLoad = false

    private struct Row: Identifiable {
        let bottle: LegacyBottleImport.DiscoveredBottle
        var isSelected: Bool
        var id: URL {
            bottle.url
        }
    }

    private var selectedCount: Int {
        rows.filter(\.isSelected).count
    }

    private var allSelected: Bool {
        !rows.isEmpty && rows.allSatisfy(\.isSelected)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 460, height: 420)
        .onAppear(perform: loadIfNeeded)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Import Bottles from the Original Whisky")
                .font(.headline)
            Text(
                """
                These bottles were created by the archived original Whisky app. Importing references \
                them in place — your files aren't moved or copied, and the original app keeps working.
                """
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        if rows.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("No bottles from the original Whisky were found.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach($rows) { $row in
                    Toggle(isOn: $row.isSelected) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.bottle.name)
                            Text(row.bottle.url.path(percentEncoded: false))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if !rows.isEmpty {
                Button(allSelected ? "Deselect All" : "Select All", action: toggleAll)
            }
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Import Selected", action: importSelected)
                .keyboardShortcut(.defaultAction)
                .disabled(selectedCount == 0)
        }
        .padding()
    }

    private func toggleAll() {
        let target = !allSelected
        for index in rows.indices {
            rows[index].isSelected = target
        }
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        rows = LegacyBottleImport
            .importableBottles(existingPaths: bottleVM.bottlesList.paths)
            .map { Row(bottle: $0, isSelected: true) }
    }

    private func importSelected() {
        for url in rows.filter(\.isSelected).map(\.bottle.url)
            where !bottleVM.bottlesList.paths.contains(url) {
            bottleVM.bottlesList.paths.append(url)
        }
        bottleVM.loadBottles()
        dismiss()
    }
}
