//
//  ResolutionConfigSection.swift
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

struct ResolutionConfigSection: View {
    @ObservedObject var bottle: Bottle
    @AppStorage("displayAdvancedMode") private var advancedMode: Bool = false
    @State private var hasRunningProcesses: Bool = false
    @State private var widthText: String = ""
    @State private var heightText: String = ""
    @State private var isLoadingRegistryState: Bool = true

    var body: some View {
        Section("config.title.display") {
            // Simple/Advanced segmented control
            Picker("", selection: $advancedMode) {
                Text("config.display.simple").tag(false)
                Text("config.display.advanced").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            // Simple mode: read-only summary
            if !advancedMode {
                virtualDesktopSummary
            }

            // Advanced mode: full controls
            if advancedMode {
                Toggle(isOn: $bottle.settings.virtualDesktopEnabled) {
                    VStack(alignment: .leading) {
                        Text("config.virtualDesktop")
                        Text("config.virtualDesktop.info")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: bottle.settings.virtualDesktopEnabled) { _, enabled in
                    persistVirtualDesktop(enabled: enabled)
                }

                if bottle.settings.virtualDesktopEnabled {
                    Picker("config.virtualDesktop.resolution", selection: $bottle.settings.resolutionPreset) {
                        ForEach(ResolutionPreset.allCases, id: \.self) { preset in
                            Text(presetLabel(preset)).tag(preset)
                        }
                    }
                    .onChange(of: bottle.settings.resolutionPreset) { _, _ in
                        syncCustomFields()
                        persistResolution()
                    }

                    if bottle.settings.resolutionPreset == .matchDisplay {
                        matchDisplayHint
                    }

                    if bottle.settings.resolutionPreset == .custom {
                        customResolutionFields
                    }

                    Text("config.virtualDesktop.nextLaunch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if hasRunningProcesses {
                    runningProcessWarning
                }
            }
        }
        .animation(.default, value: advancedMode)
        .animation(.default, value: bottle.settings.virtualDesktopEnabled)
        .task {
            await loadRegistryState()
            syncCustomFields()
            await checkRunningProcesses()
        }
    }

    // MARK: - Simple Mode Summary

    private var virtualDesktopSummary: some View {
        HStack {
            Text("config.virtualDesktop")
                .foregroundStyle(.secondary)
            Spacer()
            if bottle.settings.virtualDesktopEnabled {
                let res = currentResolutionSummary()
                Text(res)
                    .foregroundStyle(.secondary)
            } else {
                Text("config.virtualDesktop.off")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Match Display Hint

    private var matchDisplayHint: some View {
        HStack {
            Image(systemName: "display")
                .foregroundStyle(.secondary)
            if let screen = NSScreen.main {
                let pixelWidth = Int(screen.frame.width * screen.backingScaleFactor)
                let pixelHeight = Int(screen.frame.height * screen.backingScaleFactor)
                Text("config.virtualDesktop.matchDisplay \(pixelWidth) \(pixelHeight)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("config.virtualDesktop.matchDisplay.fallback")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Custom Resolution Fields

    private var customResolutionFields: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("config.virtualDesktop.width")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("1920", text: $widthText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .onChange(of: widthText) { _, newValue in
                        if let val = Int(newValue) {
                            bottle.settings.customResolutionWidth = min(max(val, 640), 7_680)
                        }
                    }
                    .onSubmit {
                        validateAndPersistCustom()
                    }
            }
            Text("\u{00D7}")
                .foregroundStyle(.secondary)
                .padding(.top, 12)
            VStack(alignment: .leading, spacing: 2) {
                Text("config.virtualDesktop.height")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("1080", text: $heightText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .onChange(of: heightText) { _, newValue in
                        if let val = Int(newValue) {
                            bottle.settings.customResolutionHeight = min(max(val, 480), 4_320)
                        }
                    }
                    .onSubmit {
                        validateAndPersistCustom()
                    }
            }
        }
    }

    // MARK: - Running Process Warning

    private var runningProcessWarning: some View {
        HStack {
            Image(systemName: "info.circle")
                .foregroundStyle(.blue)
            Text("config.virtualDesktop.processesRunning")
                .font(.caption)
            Spacer()
        }
        .padding(8)
        .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Helpers

    func currentResolutionSummary() -> String {
        let preset = bottle.settings.resolutionPreset
        if let dims = preset.dimensions {
            return "\(dims.width)x\(dims.height)"
        }
        if preset == .custom {
            return "\(bottle.settings.customResolutionWidth)x\(bottle.settings.customResolutionHeight)"
        }
        return effectiveResolutionString()
    }

    func presetLabel(_ preset: ResolutionPreset) -> String {
        switch preset {
        case .matchDisplay:
            String(localized: "config.virtualDesktop.matchDisplay.label")
        case .custom:
            String(localized: "config.virtualDesktop.custom")
        default:
            preset.label
        }
    }

    func syncCustomFields() {
        widthText = "\(bottle.settings.customResolutionWidth)"
        heightText = "\(bottle.settings.customResolutionHeight)"
    }

    func checkRunningProcesses() async {
        let wineserverActive = await Wine.isWineserverRunning(for: bottle)
        let trackedCount = ProcessRegistry.shared.getProcessCount(for: bottle)
        hasRunningProcesses = wineserverActive || trackedCount > 0
    }
}

// MARK: - Registry Persistence

extension ResolutionConfigSection {
    func persistVirtualDesktop(enabled: Bool) {
        Task {
            do {
                if enabled {
                    let res = effectiveResolutionString()
                    try await Wine.enableVirtualDesktop(bottle: bottle, resolution: res)
                } else {
                    try await Wine.disableVirtualDesktop(bottle: bottle)
                }
            } catch {
                bottle.settings.virtualDesktopEnabled = !enabled
            }
        }
    }

    func persistResolution() {
        guard bottle.settings.virtualDesktopEnabled else { return }
        Task {
            do {
                let res = effectiveResolutionString()
                try await Wine.enableVirtualDesktop(bottle: bottle, resolution: res)
            } catch {
                // Best effort; user will see "next launch" notice
            }
        }
    }

    func validateAndPersistCustom() {
        let width = min(max(Int(widthText) ?? 1_920, 640), 7_680)
        let height = min(max(Int(heightText) ?? 1_080, 480), 4_320)
        bottle.settings.customResolutionWidth = width
        bottle.settings.customResolutionHeight = height
        widthText = "\(width)"
        heightText = "\(height)"
        persistResolution()
    }

    func effectiveResolutionString() -> String {
        let preset = bottle.settings.resolutionPreset
        switch preset {
        case .matchDisplay:
            if let screen = NSScreen.main {
                let width = Int(screen.frame.width * screen.backingScaleFactor)
                let height = Int(screen.frame.height * screen.backingScaleFactor)
                return "\(width)x\(height)"
            }
            return "1920x1080"
        case .custom:
            return "\(bottle.settings.customResolutionWidth)x\(bottle.settings.customResolutionHeight)"
        default:
            if let dims = preset.dimensions {
                return "\(dims.width)x\(dims.height)"
            }
            return "1920x1080"
        }
    }

    func loadRegistryState() async {
        do {
            if let resolution = try await Wine.queryVirtualDesktop(bottle: bottle) {
                bottle.settings.virtualDesktopEnabled = true
                let parts = resolution.split(separator: "x")
                if parts.count == 2, let width = Int(parts[0]), let height = Int(parts[1]) {
                    matchRegistryToPreset(width: width, height: height)
                }
            } else {
                bottle.settings.virtualDesktopEnabled = false
            }
        } catch {
            // Registry query failed; leave defaults
        }
        isLoadingRegistryState = false
    }

    func matchRegistryToPreset(width: Int, height: Int) {
        for preset in ResolutionPreset.allCases {
            if let dims = preset.dimensions, dims.width == width, dims.height == height {
                bottle.settings.resolutionPreset = preset
                return
            }
        }
        bottle.settings.resolutionPreset = .custom
        bottle.settings.customResolutionWidth = width
        bottle.settings.customResolutionHeight = height
    }
}
