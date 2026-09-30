//
//  DLLOverrideConfigSection.swift
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

/// Bottle-level DLL override configuration section for ``ConfigView``.
///
/// Displays managed overrides from DXVK toggle and launcher presets as read-only entries,
/// and provides the ``DLLOverrideEditor`` for editing custom bottle-level overrides.
struct DLLOverrideConfigSection: View {
    @ObservedObject var bottle: Bottle
    @Binding var isExpanded: Bool

    /// A managed override, what applies it, and the label shown beside it.
    private struct ManagedOverride {
        let entry: DLLOverrideEntry
        let source: DLLOverrideSource
        let label: String
    }

    var body: some View {
        Section("config.title.dllOverrides", isExpanded: $isExpanded) {
            DLLOverrideEditor(
                managedOverrides: computedManagedOverrides.map { (entry: $0.entry, source: $0.label) },
                customOverrides: $bottle.settings.dllOverrides,
                warnings: computedWarnings
            )
        }
    }

    /// Computes managed overrides from bottle state (graphics backend, launcher presets).
    private var computedManagedOverrides: [ManagedOverride] {
        var managed: [ManagedOverride] = []
        // Read once for both presets, as the launch path does: whether DXVK and
        // DXMT turn d3d12 off depends on what the runtime's builtin d3d12 is.
        let builtinD3D12IsD3DMetal = GPTKImporter.isDeployed()

        // The backend, not the legacy `dxvk` flag: the launch path only honours
        // that flag when no backend is set, so reading it here listed
        // overrides that were not the ones being applied.
        let backend = bottle.settings.graphicsBackend == .recommended
            ? GraphicsBackendResolver.resolve()
            : bottle.settings.graphicsBackend
        let preset = DLLOverrideResolver.managedPreset(
            for: backend, builtinD3D12IsD3DMetal: builtinD3D12IsD3DMetal
        )
        // Only DXVK and DXMT contribute a preset. Crediting the one that did is
        // what keeps a conflict warning on a DXMT bottle from naming DXVK.
        let backendSource: DLLOverrideSource = backend == .dxmt ? .dxmt : .dxvk
        for entry in preset {
            managed.append(ManagedOverride(entry: entry, source: backendSource, label: backend.displayName))
        }

        // Launcher managed entries (when launcher requires DXVK and autoEnableDXVK is on)
        if bottle.settings.launcherCompatibilityMode,
           bottle.settings.autoEnableDXVK,
           let launcher = bottle.settings.detectedLauncher,
           launcher.requiresDXVK {
            for entry in DLLOverrideResolver.dxvkPreset(builtinD3D12IsD3DMetal: builtinD3D12IsD3DMetal)
                where !managed.contains(where: { $0.entry.dllName == entry.dllName }) {
                managed.append(ManagedOverride(
                    entry: entry,
                    source: .launcher(launcher.displayName),
                    label: String(localized: "config.dllOverrides.source.launcher")
                ))
            }
        }

        return managed
    }

    /// Computes warnings using DLLOverrideResolver for custom overrides conflicting with managed ones.
    private var computedWarnings: [DLLOverrideWarning] {
        let managedEntries: [(entry: DLLOverrideEntry, source: DLLOverrideSource)] = computedManagedOverrides.map {
            ($0.entry, $0.source)
        }
        let resolver = DLLOverrideResolver(
            managed: managedEntries,
            bottleCustom: bottle.settings.dllOverrides,
            programCustom: []
        )
        return resolver.resolve().warnings
    }
}
