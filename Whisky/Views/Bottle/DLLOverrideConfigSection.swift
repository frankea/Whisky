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

    var body: some View {
        Section("config.title.dllOverrides", isExpanded: $isExpanded) {
            DLLOverrideEditor(
                managedOverrides: computedManagedOverrides,
                customOverrides: $bottle.settings.dllOverrides,
                warnings: computedWarnings
            )
        }
    }

    /// Computes managed overrides from bottle state (DXVK toggle, launcher presets).
    private var computedManagedOverrides: [(entry: DLLOverrideEntry, source: String)] {
        var managed: [(entry: DLLOverrideEntry, source: String)] = []

        // DXVK managed entries
        if bottle.settings.dxvk {
            for entry in DLLOverrideResolver.dxvkPreset {
                managed.append((
                    entry: entry,
                    source: String(localized: "config.dllOverrides.source.dxvk")
                ))
            }
        }

        // Launcher managed entries (when launcher requires DXVK and autoEnableDXVK is on)
        if bottle.settings.launcherCompatibilityMode,
           bottle.settings.autoEnableDXVK,
           let launcher = bottle.settings.detectedLauncher,
           launcher.requiresDXVK {
            for entry in DLLOverrideResolver.dxvkPreset {
                // Avoid duplicates if DXVK is also enabled
                if !managed.contains(where: { $0.entry.dllName == entry.dllName }) {
                    managed.append((
                        entry: entry,
                        source: String(localized: "config.dllOverrides.source.launcher")
                    ))
                }
            }
        }

        return managed
    }

    /// Computes warnings using DLLOverrideResolver for custom overrides conflicting with managed ones.
    private var computedWarnings: [DLLOverrideWarning] {
        let managedEntries: [(entry: DLLOverrideEntry, source: DLLOverrideSource)] = computedManagedOverrides.map {
            ($0.entry, .dxvk)
        }
        let resolver = DLLOverrideResolver(
            managed: managedEntries,
            bottleCustom: bottle.settings.dllOverrides,
            programCustom: []
        )
        return resolver.resolve().warnings
    }
}
