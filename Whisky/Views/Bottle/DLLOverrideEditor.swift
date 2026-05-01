//
//  DLLOverrideEditor.swift
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

/// Reusable DLL override table editor with managed (read-only) display and custom (editable) entries.
///
/// Used at both bottle and program levels to display managed overrides (from DXVK toggle,
/// launcher presets) and allow editing of custom user overrides.
struct DLLOverrideEditor: View {
    /// Managed overrides (read-only display with source labels).
    let managedOverrides: [(entry: DLLOverrideEntry, source: String)]
    /// Custom overrides (editable by the user).
    @Binding var customOverrides: [DLLOverrideEntry]
    /// Warnings from DLLOverrideResolver for conflict display.
    let warnings: [DLLOverrideWarning]

    @State private var newDLLName: String = ""
    @State private var newDLLMode: DLLOverrideMode = .nativeThenBuiltin

    var body: some View {
        managedSection
        customSection
        addRow
        presetsMenu
    }

    // MARK: - Managed Overrides Section

    @ViewBuilder
    private var managedSection: some View {
        if !managedOverrides.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("config.dllOverrides.managed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(managedOverrides, id: \.entry.dllName) { item in
                    HStack {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text(item.entry.dllName)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Text(item.entry.mode.displayName)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text(item.source)
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Custom Overrides Section

    @ViewBuilder
    private var customSection: some View {
        if !customOverrides.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("config.dllOverrides.custom")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(Array(customOverrides.enumerated()), id: \.element.dllName) { index, entry in
                    HStack {
                        Text(entry.dllName)
                            .font(.system(.body, design: .monospaced))
                        warningIcon(for: entry.dllName)
                        Spacer()
                        Picker("", selection: modeBinding(at: index)) {
                            ForEach(DLLOverrideMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 200)
                        Button {
                            customOverrides.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Add Row

    private var addRow: some View {
        HStack {
            TextField("config.dllOverrides.placeholder", text: $newDLLName)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 120)
                .onChange(of: newDLLName) {
                    // Strip .dll suffix if the user types it
                    if newDLLName.lowercased().hasSuffix(".dll") {
                        newDLLName = String(newDLLName.dropLast(4))
                    }
                }
            Picker("", selection: $newDLLMode) {
                ForEach(DLLOverrideMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .labelsHidden()
            .frame(width: 200)
            Button {
                addEntry()
            } label: {
                Image(systemName: "plus.circle.fill")
            }
            .buttonStyle(.plain)
            .disabled(newDLLName.trimmingCharacters(in: .whitespaces).isEmpty || entryExists(newDLLName))
        }
    }

    // MARK: - Presets Menu

    private var presetsMenu: some View {
        Menu("config.dllOverrides.presets") {
            Button("config.dllOverrides.preset.dxvk") {
                applyDXVKPreset()
            }
        }
    }

    // MARK: - Helpers

    private func modeBinding(at index: Int) -> Binding<DLLOverrideMode> {
        Binding(
            get: {
                guard index < customOverrides.count else { return .nativeThenBuiltin }
                return customOverrides[index].mode
            },
            set: { newMode in
                guard index < customOverrides.count else { return }
                let entry = customOverrides[index]
                customOverrides[index] = DLLOverrideEntry(dllName: entry.dllName, mode: newMode)
            }
        )
    }

    @ViewBuilder
    private func warningIcon(for dllName: String) -> some View {
        if let warning = warnings.first(where: { $0.dllName == dllName }) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.caption)
                .help(warning.message)
        }
    }

    private func entryExists(_ name: String) -> Bool {
        let normalizedName = name.lowercased().trimmingCharacters(in: .whitespaces)
        return customOverrides.contains { $0.dllName == normalizedName }
            || managedOverrides.contains { $0.entry.dllName == normalizedName }
    }

    private func addEntry() {
        let name = newDLLName.lowercased().trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !entryExists(name) else { return }
        customOverrides.append(DLLOverrideEntry(dllName: name, mode: newDLLMode))
        newDLLName = ""
    }

    private func applyDXVKPreset() {
        for preset in DLLOverrideResolver.dxvkPreset {
            if let existingIndex = customOverrides.firstIndex(where: { $0.dllName == preset.dllName }) {
                customOverrides[existingIndex] = preset
            } else {
                customOverrides.append(preset)
            }
        }
    }
}
