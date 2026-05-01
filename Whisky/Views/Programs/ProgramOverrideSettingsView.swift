// swiftlint:disable file_length
//
//  ProgramOverrideSettingsView.swift
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

// swiftlint:disable type_body_length

/// Per-program override settings view with inherit/override toggle pattern.
///
/// Each overrideable group defaults to "Inherit from bottle" with a toggle
/// to switch to "Override", revealing controls with the current inherited value
/// as the starting value (copy-on-enable).
struct ProgramOverrideSettingsView: View {
    @ObservedObject var bottle: Bottle
    @ObservedObject var program: Program
    @Binding var isExpanded: Bool

    @State private var showResetConfirmation = false
    @State private var showDiagnosticsSheet = false
    @State private var activeDiagnosis: CrashDiagnosis?
    @State private var activeLogText: String = ""
    @State private var gameMatch: MatchResult?
    @State private var showGameConfigDetail: Bool = false
    @State private var recommendedDependencies: [DependencyDefinition] = []

    var body: some View {
        dependencyBadgeSection
        gameConfigSection
        Section("program.overrides.title", isExpanded: $isExpanded) {
            graphicsGroup
            syncGroup
            performanceGroup
            inputGroup
            displayGroup
            dllOverridesGroup
            winetricksSection
            resetButton
        }
        diagnosticsSection
        audioTroubleshootingSection
            .task {
                await loadGameMatch()
                await loadRecommendedDependencies()
            }
            .sheet(isPresented: $showGameConfigDetail) {
                if let match = gameMatch {
                    GameEntryDetailView(entry: match.entry, bottle: bottle)
                        .frame(minWidth: 600, minHeight: 500)
                }
            }
            .sheet(isPresented: $showDiagnosticsSheet) {
                if let diagnosis = activeDiagnosis {
                    DiagnosticsView(
                        diagnosis: diagnosis,
                        logText: activeLogText,
                        programName: program.name,
                        bottleName: bottle.settings.name,
                        timestamp: Date()
                    )
                    .frame(minWidth: 600, minHeight: 400)
                }
            }
    }

    // MARK: - Diagnostics Section

    private var diagnosticsSection: some View {
        Section("Diagnostics") {
            DiagnosisHistoryView(
                bottle: bottle,
                program: program,
                onViewDetails: { entry in
                    viewDiagnosisDetails(for: entry)
                },
                onReanalyze: { entry in
                    viewDiagnosisDetails(for: entry)
                },
                onAnalyzeLastRun: {
                    analyzeLastRun()
                }
            )

            if let lastDate = program.settings.lastDiagnosisDate {
                HStack {
                    Text("Last analyzed:")
                    Text(lastDate, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func viewDiagnosisDetails(for entry: DiagnosisHistoryEntry) {
        let logURL = Wine.logsFolder.appendingPathComponent(entry.logFileRef)
        Task {
            guard let diagnosis = await Wine.classifyLastRun(
                logFileURL: logURL,
                exitCode: 1
            )
            else { return }
            activeLogText = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
            activeDiagnosis = diagnosis
            showDiagnosticsSheet = true
        }
    }

    private func analyzeLastRun() {
        guard let logURL = program.settings.lastLogFileURL else { return }
        Task {
            guard let diagnosis = await Wine.classifyLastRun(
                logFileURL: logURL,
                exitCode: 1
            )
            else { return }
            activeLogText = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
            activeDiagnosis = diagnosis
            showDiagnosticsSheet = true
        }
    }

    // MARK: - Audio Troubleshooting Section

    private var audioTroubleshootingSection: some View {
        Section("Audio") {
            Button("Troubleshoot Audio\u{2026}") {
                NotificationCenter.default.post(
                    name: .openAudioTroubleshooting,
                    object: nil
                )
            }
            .help("Open audio diagnostics and troubleshooting for this bottle")
        }
    }

    // MARK: - Dependency Badge

    @ViewBuilder
    private var dependencyBadgeSection: some View {
        if !recommendedDependencies.isEmpty {
            Section {
                ForEach(recommendedDependencies, id: \.id) { definition in
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(String(localized: "dependency.missing.banner \(definition.displayName)"))
                            .font(.callout)
                        Spacer()
                        Button(String(localized: "dependency.install")) {
                            NotificationCenter.default.post(
                                name: .openDependenciesSection,
                                object: nil
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .controlSize(.small)
                        Button(String(localized: "steam.stall.dismiss")) {
                            DependencyManager.dismissRecommendation(definition.id, for: program)
                            recommendedDependencies.removeAll { $0.id == definition.id }
                        }
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private nonisolated func loadRecommendedDependencies() async {
        let deps = await DependencyManager.recommendedDependencies(for: program, bottle: bottle)
        await MainActor.run {
            recommendedDependencies = deps
        }
    }

    // MARK: - Game Config Suggestion

    @ViewBuilder
    private var gameConfigSection: some View {
        if let match = gameMatch {
            Section(String(localized: "gameConfig.banner.recommended")) {
                GameConfigBannerView(
                    matchResult: match,
                    bottle: bottle,
                    programURL: program.url
                )

                Button {
                    showGameConfigDetail = true
                } label: {
                    HStack {
                        Text(match.entry.title)
                            .font(.subheadline)
                        Spacer()
                        Text(match.entry.rating.displayName)
                            .font(.caption)
                            .foregroundStyle(ratingColor(match.entry.rating))
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private nonisolated func loadGameMatch() async {
        let exeName = await program.url.lastPathComponent
        let exeURL = await program.url
        let steamAppId = SteamAppManifest.findAppIdForProgram(at: exeURL)

        let metadata = ProgramMetadata(
            exeName: exeName,
            exeURL: exeURL,
            steamAppId: steamAppId
        )

        let entries = GameDBLoader.loadDefaults()
        let match = GameMatcher.bestMatch(metadata: metadata, against: entries)

        await MainActor.run {
            gameMatch = match
        }
    }

    private func ratingColor(_ rating: CompatibilityRating) -> Color {
        switch rating {
        case .works: .green
        case .playable: .yellow
        case .unverified: .gray
        case .broken: .red
        case .notSupported: .red
        }
    }

    // MARK: - Graphics / DXVK Group

    private var graphicsGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(
                "program.overrides.graphics",
                isOn: graphicsOverrideBinding
            )
            if hasGraphicsOverride {
                // Backend picker
                Picker("config.graphics.backend", selection: graphicsBackendBinding) {
                    ForEach(GraphicsBackend.allCases, id: \.self) { backend in
                        Text(backend.displayName).tag(backend)
                    }
                }

                // DXVK sub-controls only when backend is DXVK
                let overriddenBackend = program.settings.overrides?.graphicsBackend ?? .recommended
                if overriddenBackend == .dxvk {
                    graphicsControls
                }

                // "Takes effect next launch" note
                Text("config.graphics.nextLaunch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                inheritedSummary(
                    "\(bottle.settings.graphicsBackend.displayName), "
                        + "DXVK Async \(bottle.settings.dxvkAsync ? "On" : "Off"), "
                        + "HUD \(hudDescription(bottle.settings.dxvkHud))"
                )
            }
        }
    }

    @ViewBuilder
    private var graphicsControls: some View {
        Toggle("config.dxvk.async", isOn: dxvkAsyncBinding)
        Picker("config.dxvkHud", selection: dxvkHudBinding) {
            Text("config.dxvkHud.full").tag(DXVKHUD.full)
            Text("config.dxvkHud.partial").tag(DXVKHUD.partial)
            Text("config.dxvkHud.fps").tag(DXVKHUD.fps)
            Text("config.dxvkHud.off").tag(DXVKHUD.off)
        }
    }

    // MARK: - Sync Group

    private var syncGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(
                "program.overrides.sync",
                isOn: syncOverrideBinding
            )
            if hasSyncOverride {
                Picker("config.enhancedSync", selection: enhancedSyncBinding) {
                    Text("config.enhancedSync.none").tag(EnhancedSync.none)
                    Text("config.enhancedSync.esync").tag(EnhancedSync.esync)
                    Text("config.enhancedSync.msync").tag(EnhancedSync.msync)
                }
            } else {
                inheritedSummary(syncDescription(bottle.settings.enhancedSync))
            }
        }
    }

    // MARK: - Performance Group

    private var performanceGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(
                "program.overrides.performance",
                isOn: performanceOverrideBinding
            )
            if hasPerformanceOverride {
                performanceControls
            } else {
                inheritedSummary(
                    "\(bottle.settings.performancePreset.description()), "
                        + "Shader Cache \(bottle.settings.shaderCacheEnabled ? "On" : "Off"), "
                        + "Force D3D11 \(bottle.settings.forceD3D11 ? "On" : "Off")"
                )
            }
        }
    }

    @ViewBuilder
    private var performanceControls: some View {
        Picker("config.performancePreset", selection: performancePresetBinding) {
            ForEach(PerformancePreset.allCases, id: \.self) { preset in
                Text(preset.description()).tag(preset)
            }
        }
        Toggle("config.shaderCache", isOn: shaderCacheBinding)
        Toggle("config.forceD3D11", isOn: forceD3D11Binding)
    }

    // MARK: - Input Group

    private var inputGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(
                "program.overrides.input",
                isOn: inputOverrideBinding
            )
            if hasInputOverride {
                inputControls
            } else {
                inheritedSummary(
                    "Controller Compat \(bottle.settings.controllerCompatibilityMode ? "On" : "Off"), "
                        + "Native Labels \(bottle.settings.useButtonLabels ? "On" : "Off")"
                )
            }
        }
    }

    @ViewBuilder
    private var inputControls: some View {
        Toggle("config.controllerCompat", isOn: controllerCompatBinding)
        Toggle("config.disableHIDAPI", isOn: disableHIDAPIBinding)
        Toggle("config.allowBackgroundEvents", isOn: allowBackgroundBinding)
        Toggle("config.disableControllerMapping", isOn: disableControllerMappingBinding)
        Toggle("config.useButtonLabels", isOn: useButtonLabelsBinding)
    }

    // MARK: - Display Group

    private var displayGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(
                "program.overrides.display",
                isOn: displayOverrideBinding
            )
            if hasDisplayOverride {
                displayControls
            } else {
                if bottle.settings.virtualDesktopEnabled {
                    let preset = bottle.settings.resolutionPreset
                    let resText = preset.dimensions.map { "\($0.width)x\($0.height)" }
                        ?? (preset == .custom
                            ? "\(bottle.settings.customResolutionWidth)x\(bottle.settings.customResolutionHeight)"
                            : String(localized: "config.virtualDesktop.matchDisplay.label"))
                    inheritedSummary(
                        String(localized: "program.overrides.display.enabled") + " " + resText
                    )
                } else {
                    inheritedSummary(String(localized: "config.virtualDesktop.off"))
                }
            }
        }
    }

    @ViewBuilder
    private var displayControls: some View {
        Toggle("config.virtualDesktop", isOn: virtualDesktopEnabledBinding)
        if program.settings.overrides?.virtualDesktopEnabled == true {
            Picker("config.virtualDesktop.resolution", selection: displayPresetBinding) {
                ForEach(ResolutionPreset.allCases, id: \.self) { preset in
                    Text(preset.label).tag(preset)
                }
            }
            if program.settings.overrides?.resolutionPreset == .custom {
                HStack {
                    TextField(
                        "1920",
                        value: displayCustomWidthBinding,
                        format: .number
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    Text("\u{00D7}")
                        .foregroundStyle(.secondary)
                    TextField(
                        "1080",
                        value: displayCustomHeightBinding,
                        format: .number
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                }
            }
        }
        Text("programOverride.display.info")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    // MARK: - DLL Overrides Group

    private var dllOverridesGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(
                "program.overrides.dll",
                isOn: dllOverrideBinding
            )
            if hasDLLOverride {
                DLLOverrideEditor(
                    managedOverrides: computedManagedOverrides,
                    customOverrides: programDLLOverridesBinding,
                    warnings: computedDLLWarnings
                )
            } else {
                inheritedSummary(
                    "\(bottle.settings.dllOverrides.count) "
                        + String(localized: "program.overrides.dll.customCount")
                )
            }
        }
    }

    // MARK: - Winetricks Verbs Section (Read-Only)

    private var winetricksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("program.overrides.winetricks.title")
                .font(.headline)
            Text("program.overrides.winetricks.subtitle")
                .font(.caption)
                .foregroundStyle(.secondary)

            let verbs = installedVerbs
            if verbs.isEmpty {
                Text("program.overrides.winetricks.none")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach(verbs, id: \.self) { verb in
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Text(verb)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Toggle(
                            "program.overrides.winetricks.usedByProgram",
                            isOn: verbTagBinding(for: verb)
                        )
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        Text("program.overrides.winetricks.usedByProgram")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Reset Button

    private var resetButton: some View {
        Button(role: .destructive) {
            showResetConfirmation = true
        } label: {
            Text("program.overrides.reset")
        }
        .alert(
            "program.overrides.reset",
            isPresented: $showResetConfirmation
        ) {
            Button("program.overrides.reset", role: .destructive) {
                program.settings.overrides = nil
            }
            Button("button.cancel", role: .cancel) {}
        } message: {
            Text("program.overrides.reset.confirm")
        }
    }

    // MARK: - Helper Views

    private func inheritedSummary(_ text: String) -> some View {
        HStack {
            Text("program.overrides.inherited")
                .foregroundStyle(.secondary)
                .font(.caption)
            Text(text)
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    // MARK: - Computed Properties

    private var hasGraphicsOverride: Bool {
        program.settings.overrides?.graphicsBackend != nil
    }

    private var hasSyncOverride: Bool {
        program.settings.overrides?.enhancedSync != nil
    }

    private var hasPerformanceOverride: Bool {
        program.settings.overrides?.performancePreset != nil
    }

    private var hasInputOverride: Bool {
        program.settings.overrides?.controllerCompatibilityMode != nil
    }

    private var hasDisplayOverride: Bool {
        program.settings.overrides?.virtualDesktopEnabled != nil
    }

    private var hasDLLOverride: Bool {
        program.settings.overrides?.dllOverrides != nil
    }

    private var installedVerbs: [String] {
        let cache = WinetricksVerbCache.load(from: bottle.url)
        return (cache?.installedVerbs ?? []).sorted()
    }

    private var computedManagedOverrides: [(entry: DLLOverrideEntry, source: String)] {
        var managed: [(entry: DLLOverrideEntry, source: String)] = []
        if bottle.settings.graphicsBackend == .dxvk {
            for entry in DLLOverrideResolver.dxvkPreset {
                managed.append((
                    entry: entry,
                    source: String(localized: "config.dllOverrides.source.dxvk")
                ))
            }
        }
        return managed
    }

    private var computedDLLWarnings: [DLLOverrideWarning] {
        let managedEntries: [(entry: DLLOverrideEntry, source: DLLOverrideSource)] = computedManagedOverrides.map {
            ($0.entry, .dxvk)
        }
        let programDLLs = program.settings.overrides?.dllOverrides ?? []
        let resolver = DLLOverrideResolver(
            managed: managedEntries,
            bottleCustom: bottle.settings.dllOverrides,
            programCustom: programDLLs
        )
        return resolver.resolve().warnings
    }

    // MARK: - Override Group Toggle Bindings

    private var graphicsOverrideBinding: Binding<Bool> {
        Binding(
            get: { hasGraphicsOverride },
            set: { isOn in
                ensureOverrides()
                if isOn {
                    program.settings.overrides?.graphicsBackend = bottle.settings.graphicsBackend
                    program.settings.overrides?.dxvk = bottle.settings.dxvk
                    program.settings.overrides?.dxvkAsync = bottle.settings.dxvkAsync
                    program.settings.overrides?.dxvkHud = bottle.settings.dxvkHud
                } else {
                    program.settings.overrides?.graphicsBackend = nil
                    program.settings.overrides?.dxvk = nil
                    program.settings.overrides?.dxvkAsync = nil
                    program.settings.overrides?.dxvkHud = nil
                }
            }
        )
    }

    private var syncOverrideBinding: Binding<Bool> {
        Binding(
            get: { hasSyncOverride },
            set: { isOn in
                ensureOverrides()
                if isOn {
                    program.settings.overrides?.enhancedSync = bottle.settings.enhancedSync
                } else {
                    program.settings.overrides?.enhancedSync = nil
                }
            }
        )
    }

    private var performanceOverrideBinding: Binding<Bool> {
        Binding(
            get: { hasPerformanceOverride },
            set: { isOn in
                ensureOverrides()
                if isOn {
                    program.settings.overrides?.performancePreset = bottle.settings.performancePreset
                    program.settings.overrides?.shaderCacheEnabled = bottle.settings.shaderCacheEnabled
                    program.settings.overrides?.forceD3D11 = bottle.settings.forceD3D11
                } else {
                    program.settings.overrides?.performancePreset = nil
                    program.settings.overrides?.shaderCacheEnabled = nil
                    program.settings.overrides?.forceD3D11 = nil
                }
            }
        )
    }

    private var inputOverrideBinding: Binding<Bool> {
        Binding(
            get: { hasInputOverride },
            set: { isOn in
                ensureOverrides()
                if isOn {
                    program.settings.overrides?.controllerCompatibilityMode =
                        bottle.settings.controllerCompatibilityMode
                    program.settings.overrides?.disableHIDAPI = bottle.settings.disableHIDAPI
                    program.settings.overrides?.allowBackgroundEvents = bottle.settings.allowBackgroundEvents
                    program.settings.overrides?.disableControllerMapping = bottle.settings.disableControllerMapping
                    program.settings.overrides?.useButtonLabels = bottle.settings.useButtonLabels
                } else {
                    program.settings.overrides?.controllerCompatibilityMode = nil
                    program.settings.overrides?.disableHIDAPI = nil
                    program.settings.overrides?.allowBackgroundEvents = nil
                    program.settings.overrides?.disableControllerMapping = nil
                    program.settings.overrides?.useButtonLabels = nil
                }
            }
        )
    }

    private var displayOverrideBinding: Binding<Bool> {
        Binding(
            get: { hasDisplayOverride },
            set: { isOn in
                ensureOverrides()
                if isOn {
                    program.settings.overrides?.virtualDesktopEnabled = bottle.settings.virtualDesktopEnabled
                    program.settings.overrides?.resolutionPreset = bottle.settings.resolutionPreset
                    program.settings.overrides?.customResolutionWidth = bottle.settings.customResolutionWidth
                    program.settings.overrides?.customResolutionHeight = bottle.settings.customResolutionHeight
                } else {
                    program.settings.overrides?.virtualDesktopEnabled = nil
                    program.settings.overrides?.resolutionPreset = nil
                    program.settings.overrides?.customResolutionWidth = nil
                    program.settings.overrides?.customResolutionHeight = nil
                }
            }
        )
    }

    private var dllOverrideBinding: Binding<Bool> {
        Binding(
            get: { hasDLLOverride },
            set: { isOn in
                ensureOverrides()
                if isOn {
                    program.settings.overrides?.dllOverrides = bottle.settings.dllOverrides
                } else {
                    program.settings.overrides?.dllOverrides = nil
                }
            }
        )
    }

    // MARK: - Individual Setting Bindings

    private var graphicsBackendBinding: Binding<GraphicsBackend> {
        Binding(
            get: { program.settings.overrides?.graphicsBackend ?? bottle.settings.graphicsBackend },
            set: { program.settings.overrides?.graphicsBackend = $0 }
        )
    }

    private var dxvkBinding: Binding<Bool> {
        Binding(
            get: { program.settings.overrides?.dxvk ?? bottle.settings.dxvk },
            set: { program.settings.overrides?.dxvk = $0 }
        )
    }

    private var dxvkAsyncBinding: Binding<Bool> {
        Binding(
            get: { program.settings.overrides?.dxvkAsync ?? bottle.settings.dxvkAsync },
            set: { program.settings.overrides?.dxvkAsync = $0 }
        )
    }

    private var dxvkHudBinding: Binding<DXVKHUD> {
        Binding(
            get: { program.settings.overrides?.dxvkHud ?? bottle.settings.dxvkHud },
            set: { program.settings.overrides?.dxvkHud = $0 }
        )
    }

    private var enhancedSyncBinding: Binding<EnhancedSync> {
        Binding(
            get: { program.settings.overrides?.enhancedSync ?? bottle.settings.enhancedSync },
            set: { program.settings.overrides?.enhancedSync = $0 }
        )
    }

    private var performancePresetBinding: Binding<PerformancePreset> {
        Binding(
            get: { program.settings.overrides?.performancePreset ?? bottle.settings.performancePreset },
            set: { program.settings.overrides?.performancePreset = $0 }
        )
    }

    private var shaderCacheBinding: Binding<Bool> {
        Binding(
            get: { program.settings.overrides?.shaderCacheEnabled ?? bottle.settings.shaderCacheEnabled },
            set: { program.settings.overrides?.shaderCacheEnabled = $0 }
        )
    }

    private var forceD3D11Binding: Binding<Bool> {
        Binding(
            get: { program.settings.overrides?.forceD3D11 ?? bottle.settings.forceD3D11 },
            set: { program.settings.overrides?.forceD3D11 = $0 }
        )
    }

    private var controllerCompatBinding: Binding<Bool> {
        Binding(
            get: { program.settings.overrides?.controllerCompatibilityMode ?? false },
            set: { program.settings.overrides?.controllerCompatibilityMode = $0 }
        )
    }

    private var disableHIDAPIBinding: Binding<Bool> {
        Binding(
            get: { program.settings.overrides?.disableHIDAPI ?? false },
            set: { program.settings.overrides?.disableHIDAPI = $0 }
        )
    }

    private var allowBackgroundBinding: Binding<Bool> {
        Binding(
            get: { program.settings.overrides?.allowBackgroundEvents ?? false },
            set: { program.settings.overrides?.allowBackgroundEvents = $0 }
        )
    }

    private var disableControllerMappingBinding: Binding<Bool> {
        Binding(
            get: { program.settings.overrides?.disableControllerMapping ?? false },
            set: { program.settings.overrides?.disableControllerMapping = $0 }
        )
    }

    private var useButtonLabelsBinding: Binding<Bool> {
        Binding(
            get: { program.settings.overrides?.useButtonLabels ?? false },
            set: { program.settings.overrides?.useButtonLabels = $0 }
        )
    }

    private var virtualDesktopEnabledBinding: Binding<Bool> {
        Binding(
            get: { program.settings.overrides?.virtualDesktopEnabled ?? false },
            set: { program.settings.overrides?.virtualDesktopEnabled = $0 }
        )
    }

    private var displayPresetBinding: Binding<ResolutionPreset> {
        Binding(
            get: { program.settings.overrides?.resolutionPreset ?? .r1920x1080 },
            set: { program.settings.overrides?.resolutionPreset = $0 }
        )
    }

    private var displayCustomWidthBinding: Binding<Int> {
        Binding(
            get: { program.settings.overrides?.customResolutionWidth ?? 1_920 },
            set: { program.settings.overrides?.customResolutionWidth = min(max($0, 640), 7_680) }
        )
    }

    private var displayCustomHeightBinding: Binding<Int> {
        Binding(
            get: { program.settings.overrides?.customResolutionHeight ?? 1_080 },
            set: { program.settings.overrides?.customResolutionHeight = min(max($0, 480), 4_320) }
        )
    }

    private var programDLLOverridesBinding: Binding<[DLLOverrideEntry]> {
        Binding(
            get: { program.settings.overrides?.dllOverrides ?? [] },
            set: { program.settings.overrides?.dllOverrides = $0 }
        )
    }

    private func verbTagBinding(for verb: String) -> Binding<Bool> {
        Binding(
            get: {
                program.settings.overrides?.taggedVerbs?.contains(verb) ?? false
            },
            set: { isTagged in
                ensureOverrides()
                if program.settings.overrides?.taggedVerbs == nil {
                    program.settings.overrides?.taggedVerbs = []
                }
                if isTagged {
                    if !(program.settings.overrides?.taggedVerbs?.contains(verb) ?? false) {
                        program.settings.overrides?.taggedVerbs?.append(verb)
                    }
                } else {
                    program.settings.overrides?.taggedVerbs?.removeAll { $0 == verb }
                }
            }
        )
    }

    // MARK: - Helpers

    private func ensureOverrides() {
        if program.settings.overrides == nil {
            program.settings.overrides = ProgramOverrides()
        }
    }

    private func hudDescription(_ hud: DXVKHUD) -> String {
        switch hud {
        case .full: "Full"
        case .partial: "Partial"
        case .fps: "FPS"
        case .off: "Off"
        }
    }

    private func syncDescription(_ sync: EnhancedSync) -> String {
        switch sync {
        case .none: "None"
        case .esync: "ESync"
        case .msync: "MSync"
        }
    }
}

// swiftlint:enable type_body_length

extension Notification.Name {
    /// Posted to navigate to the Dependencies section in ConfigView.
    static let openDependenciesSection = Notification.Name(
        "com.isaacmarovitz.Whisky.openDependenciesSection"
    )
}
