//
//  PerformanceConfigSection.swift
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

struct PerformanceConfigSection: View {
    @ObservedObject var bottle: Bottle
    @Binding var isExpanded: Bool

    var body: some View {
        Section("config.title.performance", isExpanded: $isExpanded) {
            Picker("config.performancePreset", selection: $bottle.settings.performancePreset) {
                ForEach(PerformancePreset.allCases, id: \.self) { preset in
                    Text(preset.description()).tag(preset)
                }
            }
            // Show description of current preset
            if bottle.settings.performancePreset != .balanced {
                HStack {
                    Image(systemName: presetIcon(for: bottle.settings.performancePreset))
                        .foregroundColor(.secondary)
                    Text(presetDescription(for: bottle.settings.performancePreset))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Toggle(isOn: $bottle.settings.shaderCacheEnabled) {
                VStack(alignment: .leading) {
                    Text("config.shaderCache")
                    Text("config.shaderCache.info")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Toggle(isOn: $bottle.settings.forceD3D11) {
                VStack(alignment: .leading) {
                    Text("config.forceD3D11")
                    Text("config.forceD3D11.info")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            // Install VC++ Runtime button for Unity games
            if !bottle.settings.vcRedistInstalled {
                Button {
                    Task {
                        await Winetricks.runCommand(command: "vcrun2019", bottle: bottle)
                        bottle.settings.vcRedistInstalled = true
                    }
                } label: {
                    HStack {
                        Image(systemName: "wrench.and.screwdriver")
                        VStack(alignment: .leading) {
                            Text("config.installVcRedist")
                            Text("config.installVcRedist.info")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } else {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("config.vcRedistInstalled")
                }
            }
        }
    }

    // MARK: - Performance Preset Helpers

    func presetIcon(for preset: PerformancePreset) -> String {
        switch preset {
        case .balanced:
            return "scale.3d"
        case .performance:
            return "bolt.fill"
        case .quality:
            return "sparkles"
        case .unity:
            return "cube.fill"
        }
    }

    func presetDescription(for preset: PerformancePreset) -> String {
        switch preset {
        case .balanced:
            return String(localized: "config.preset.balanced.desc")
        case .performance:
            return String(localized: "config.preset.performance.desc")
        case .quality:
            return String(localized: "config.preset.quality.desc")
        case .unity:
            return String(localized: "config.preset.unity.desc")
        }
    }
}
