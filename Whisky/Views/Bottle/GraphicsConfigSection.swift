//
//  GraphicsConfigSection.swift
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

import Metal
import SwiftUI
import WhiskyKit

struct GraphicsConfigSection: View {
    @ObservedObject var bottle: Bottle
    @AppStorage("graphicsAdvancedMode") private var advancedMode: Bool = false
    @State private var hasRunningProcesses: Bool = false

    private var resolvedBackend: GraphicsBackend {
        if bottle.settings.graphicsBackend == .recommended {
            return GraphicsBackendResolver.resolve()
        }
        return bottle.settings.graphicsBackend
    }

    var body: some View {
        Section("config.title.graphics") {
            let d3dMetalReadiness = D3DMetalReadiness.current()

            // Simple/Advanced segmented control
            Picker("", selection: $advancedMode) {
                Text("config.graphics.simple").tag(false)
                Text("config.graphics.advanced").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            // Backend picker -- always visible
            BackendPickerView(
                selection: $bottle.settings.graphicsBackend,
                resolvedBackend: resolvedBackend,
                isBackendAvailable: { backend in
                    WhiskyWineInstaller.isBackendAvailable(backend)
                },
                d3dMetalReadiness: d3dMetalReadiness,
                chromiumPrograms: chromiumProgramNames
            )

            chromiumOnExplicitBackendNotice

            // Said once, after an update put a bottle the old Steam profile had
            // switched to DXVK back on Recommended (#276).
            if bottle.settings.launcherBackendResetNotice {
                launcherBackendResetNotice
            }

            // A bottle explicitly set to D3DMetal that can't run it silently
            // degrades to WineD3D at launch, so say so (issue #146). An imported
            // payload the engine can't run is explained whatever the bottle is
            // set to, since importing it looks like it should have been enough
            // (#358).
            if (bottle.settings.graphicsBackend == .d3dMetal && !d3dMetalReadiness.isAvailable)
                || d3dMetalReadiness == .engineNotCapable {
                d3dMetalNotice(d3dMetalReadiness)
            }

            // Running process warning banner
            if hasRunningProcesses {
                runningProcessWarning
            }

            // MetalFX rides on D3DMetal's DLSS bridge and Metal 4 is D3DMetal's
            // own command-encoding backend, so both are meaningless under any
            // other backend rather than merely inactive.
            if resolvedBackend == .d3dMetal {
                Toggle(isOn: $bottle.settings.metalFX) {
                    VStack(alignment: .leading) {
                        Text("config.metalFX")
                        Text("config.metalFX.info")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $bottle.settings.metal4Enabled) {
                    VStack(alignment: .leading) {
                        Text("config.metal4")
                        Text("config.metal4.info")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                // Frame generation reaches MetalFX through the same DLSS bridge
                // as upscaling, so it has nothing to switch on without it.
                Toggle(isOn: $bottle.settings.frameGeneration) {
                    VStack(alignment: .leading) {
                        Text("config.frameGeneration")
                        Text("config.frameGeneration.info")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!bottle.settings.metalFX)
            }

            // The Sequoia compatibility toggle is gone: everything it set is a
            // platform-layer fix applied on every supported macOS, so the
            // switch changed nothing in either position.

            // "Advanced settings active" badge in Simple mode
            if !advancedMode, hasAdvancedSettingsConfigured {
                advancedSettingsBadge
            }

            // Per-program override note in Simple mode
            if !advancedMode, !programsWithGraphicsOverrides.isEmpty {
                programOverridesBadge
            }

            // Advanced mode content
            if advancedMode {
                // DXVK settings subsection
                DXVKSettingsView(
                    bottle: bottle,
                    resolvedBackend: resolvedBackend,
                    bottleURL: bottle.url
                )

                // Metal settings subsection (migrated from MetalConfigSection)
                VStack(alignment: .leading, spacing: 8) {
                    Text("config.metal.title")
                        .font(.headline)
                    Toggle(isOn: $bottle.settings.metalHud) {
                        Text("config.metalHud")
                    }
                    Toggle(isOn: $bottle.settings.metalTrace) {
                        Text("config.metalTrace")
                        Text("config.metalTrace.info")
                    }
                    if let device = MTLCreateSystemDefaultDevice() {
                        if device.supportsFamily(.apple9) {
                            Toggle(isOn: $bottle.settings.dxrEnabled) {
                                Text("config.dxr")
                                Text("config.dxr.info")
                            }
                        }
                    }
                    Toggle(isOn: $bottle.settings.metalValidation) {
                        Text("config.metalValidation")
                    }
                }

                // Per-program override info
                if !programsWithGraphicsOverrides.isEmpty {
                    programOverridesInfo
                }
            }
        }
        .animation(.default, value: advancedMode)
        .onChange(of: bottle.settings.graphicsBackend) {
            // Picking a backend answers the notice.
            if bottle.settings.launcherBackendResetNotice {
                bottle.settings.launcherBackendResetNotice = false
            }
        }
        .task {
            await checkRunningProcesses()
        }
    }

    // MARK: - Launcher Backend Reset Notice

    private var launcherBackendResetNotice: some View {
        HStack {
            Image(systemName: "info.circle")
                .foregroundStyle(.blue)
            Text("config.graphics.backend.launcherReset")
                .font(.caption)
            Spacer()
            Button {
                bottle.settings.launcherBackendResetNotice = false
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("config.graphics.backend.launcherReset.dismiss")
            .accessibilityLabel("config.graphics.backend.launcherReset.dismiss")
        }
    }

    // MARK: - D3DMetal Notice

    /// A warning when this bottle is set to D3DMetal and can't run it, or a
    /// note when it is set to something else; either way it names what is
    /// missing and, when that is the engine, links to the engine releases.
    private func d3dMetalNotice(_ readiness: D3DMetalReadiness) -> some View {
        let isWarning = bottle.settings.graphicsBackend == .d3dMetal
        return HStack(alignment: .top) {
            Image(systemName: isWarning ? "exclamationmark.triangle" : "info.circle")
                .foregroundStyle(isWarning ? Color.orange : Color.blue)
            VStack(alignment: .leading, spacing: 4) {
                Text(d3dMetalNoticeKey(readiness, isWarning: isWarning))
                    .font(.caption)
                if readiness.needsCapableEngine, let url = D3DMetalReadiness.engineReleasesURL {
                    Link("gptk.engineReleases", destination: url)
                        .font(.caption)
                }
            }
            Spacer()
        }
    }

    private func d3dMetalNoticeKey(_ readiness: D3DMetalReadiness, isWarning: Bool) -> LocalizedStringKey {
        guard isWarning else { return "config.graphics.backend.d3dMetal.engineNote" }
        switch readiness {
        case .engineNotCapable:
            return "config.graphics.backend.d3dMetal.warning.needsEngine"
        case .payloadAndEngineMissing:
            return "config.graphics.backend.d3dMetal.warning.needsPayloadAndEngine"
        case .payloadNotDeployed:
            return "config.graphics.backend.d3dMetal.warning.needsSetup"
        case .payloadMissing, .available:
            return "config.graphics.backend.d3dMetal.warning.needsPayload"
        }
    }

    // MARK: - Running Process Warning

    private var runningProcessWarning: some View {
        HStack {
            Image(systemName: "info.circle")
                .foregroundStyle(.blue)
            Text("config.graphics.nextLaunchInfo")
                .font(.caption)
            Spacer()
            Button("config.graphics.stopBottle") {
                Wine.killBottle(bottle: bottle)
                Task {
                    // Brief delay for wineserver to stop
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    await checkRunningProcesses()
                }
            }
            .font(.caption)
            .foregroundStyle(.red)
        }
        .padding(8)
        .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Running Process Check

    private func checkRunningProcesses() async {
        let wineserverActive = await Wine.isWineserverRunning(for: bottle)
        let trackedCount = ProcessRegistry.shared.getProcessCount(for: bottle)
        hasRunningProcesses = wineserverActive || trackedCount > 0
    }

    // MARK: - Advanced Settings Badge

    private var hasAdvancedSettingsConfigured: Bool {
        // Default dxvkAsync is true; check if any advanced-only settings differ from defaults
        !bottle.settings.dxvkAsync
            || bottle.settings.dxvkHud != .off
            || bottle.settings.metalHud
            || bottle.settings.metalTrace
            || bottle.settings.metalValidation
            || bottle.settings.dxrEnabled
    }

    private var advancedSettingsBadge: some View {
        HStack {
            Image(systemName: "gearshape.2")
                .foregroundStyle(.secondary)
            Text("config.graphics.advancedActive")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("config.graphics.showAdvanced") {
                advancedMode = true
            }
            .font(.caption)
        }
    }

    // MARK: - Per-Program Override Info

    private var programsWithGraphicsOverrides: [Program] {
        bottle.programs.filter { $0.settings.overrides?.graphicsBackend != nil }
    }

    private var programOverridesBadge: some View {
        HStack {
            Image(systemName: "slider.horizontal.3")
                .foregroundStyle(.secondary)
            Text("config.graphics.programOverridesActive")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("config.graphics.showAdvanced") {
                advancedMode = true
            }
            .font(.caption)
        }
    }

    private var programOverridesInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("config.graphics.programOverrides")
                .font(.headline)
            ForEach(programsWithGraphicsOverrides) { program in
                HStack {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(.blue)
                        .font(.caption)
                    Text(program.name)
                        .font(.callout)
                    Spacer()
                    Text(
                        program.settings.overrides?.graphicsBackend?.displayName
                            ?? String(localized: "config.graphics.inherited")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            Text("config.graphics.programOverrides.hint")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Chromium Programs

extension GraphicsConfigSection {
    /// The launchers, Chromium front ends, and Electron and NW.js apps among
    /// the bottle's programs, by name, each once: the programs Recommended
    /// runs on DXVK (#372). Read from each program's scan, not its files.
    var chromiumProgramNames: [String] {
        var seen = Set<String>()
        return bottle.programs
            .compactMap { program in program.dxvkSteering?.listedName(executable: program.url) }
            .filter { seen.insert($0).inserted }
    }

    /// Recommended would run these on DXVK; an explicit D3DMetal or DXMT does not.
    @ViewBuilder
    var chromiumOnExplicitBackendNotice: some View {
        let names = chromiumProgramNames
        if [.d3dMetal, .dxmt].contains(bottle.settings.graphicsBackend), !names.isEmpty {
            Text("config.graphics.chromiumOnExplicitBackend \(ListFormatter.localizedString(byJoining: names))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
