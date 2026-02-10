// swiftlint:disable file_length
//
//  ConfigView.swift
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

import os
import SwiftUI
import WhiskyKit

private let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "ConfigView")

struct ConfigView: View {
    @ObservedObject var bottle: Bottle
    @State private var buildVersion: Int = 0
    @State private var retinaMode: Bool = false
    @State private var dpiConfig: Int = 96
    @State private var winVersionLoadingState: LoadingState = .loading
    @State private var buildVersionLoadingState: LoadingState = .loading
    @State private var retinaModeLoadingState: LoadingState = .loading
    @State private var dpiConfigLoadingState: LoadingState = .loading
    @State private var dpiSheetPresented: Bool = false
    @State private var showStabilityDiagnostics: Bool = false
    @State private var stabilityDiagnosticReport: String = ""
    @State private var showDiagnosticExportSheet: Bool = false
    @State private var showCrashDiagnosticsSheet: Bool = false
    @State private var latestDiagnosis: CrashDiagnosis?
    @State private var latestDiagnosisLogText: String = ""
    @State private var latestDiagnosisProgram: Program?
    @State private var isRepairingPrefix: Bool = false
    @State private var prefixRepairResult: PrefixRepairResult?
    @State private var gameConfigSnapshot: GameConfigSnapshot?
    @State private var showRevertConfirmation: Bool = false

    private enum PrefixRepairResult: Identifiable {
        case success
        case failure(String)

        var id: String {
            switch self {
            case .success: "success"
            case let .failure(msg): "failure:\(msg)"
            }
        }
    }

    @AppStorage("wineSectionExpanded") private var wineSectionExpanded: Bool = true
    @AppStorage("performanceSectionExpanded") private var performanceSectionExpanded: Bool = true
    @AppStorage("launcherSectionExpanded") private var launcherSectionExpanded: Bool = false
    @AppStorage("inputSectionExpanded") private var inputSectionExpanded: Bool = false
    @AppStorage("dllOverrideSectionExpanded") private var dllOverrideSectionExpanded: Bool = false
    @AppStorage("cleanupSectionExpanded") private var cleanupSectionExpanded: Bool = false

    var body: some View {
        Form {
            WineConfigSection(
                bottle: bottle,
                isExpanded: $wineSectionExpanded,
                buildVersion: $buildVersion,
                retinaMode: $retinaMode,
                dpiConfig: $dpiConfig,
                winVersionLoadingState: $winVersionLoadingState,
                buildVersionLoadingState: $buildVersionLoadingState,
                retinaModeLoadingState: $retinaModeLoadingState,
                dpiConfigLoadingState: $dpiConfigLoadingState,
                dpiSheetPresented: $dpiSheetPresented,
                onRetryBuildVersion: loadBuildName,
                onRetryRetinaMode: loadRetinaMode,
                onRetryDpi: loadDpi
            )
            LauncherConfigSection(bottle: bottle, isExpanded: $launcherSectionExpanded)
            InputConfigSection(bottle: bottle, isExpanded: $inputSectionExpanded)
            GraphicsConfigSection(bottle: bottle)
            AudioConfigSection(bottle: bottle)
            PerformanceConfigSection(bottle: bottle, isExpanded: $performanceSectionExpanded)
            DLLOverrideConfigSection(bottle: bottle, isExpanded: $dllOverrideSectionExpanded)
            gameConfigRevertSection
            Section("Diagnostics") {
                Text("Analyze Wine crash output for troubleshooting guidance")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Export Diagnostic Report\u{2026}") {
                    loadLatestDiagnosisAndExport()
                }
                .disabled(latestDiagnosis == nil && mostRecentlyDiagnosedProgram == nil)

                Button("View Latest Diagnosis") {
                    loadLatestDiagnosisAndView()
                }
                .disabled(mostRecentlyDiagnosedProgram == nil)
            }
            Section("Stability") {
                Button("Generate Stability Diagnostics") {
                    Task {
                        stabilityDiagnosticReport = await StabilityDiagnostics.generateDiagnosticReport(for: bottle)
                        showStabilityDiagnostics = true
                    }
                }
                .help("Generates a bounded, privacy-safe report for issue triage.")

                Button {
                    Task {
                        isRepairingPrefix = true
                        defer {
                            bottle.clearWineUsernameCache()
                            isRepairingPrefix = false
                        }
                        do {
                            try await Wine.repairPrefix(bottle: bottle)
                            // Validate immediately after repair to confirm directories were created
                            let result = WinePrefixValidation.validatePrefix(for: bottle)
                            if result.isValid {
                                prefixRepairResult = .success
                            } else {
                                prefixRepairResult = .failure(
                                    String(localized: "config.repairPrefix.validationFailed")
                                )
                            }
                        } catch {
                            prefixRepairResult = .failure(error.localizedDescription)
                        }
                    }
                } label: {
                    HStack {
                        Text("config.repairPrefix")
                        if isRepairingPrefix {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.leading, 4)
                        }
                    }
                }
                .disabled(isRepairingPrefix)
                .help("config.repairPrefix.help")
            }
            CleanupConfigSection(bottle: bottle, isExpanded: $cleanupSectionExpanded)
        }
        .formStyle(.grouped)
        .animation(.whiskyDefault, value: wineSectionExpanded)
        .animation(.whiskyDefault, value: launcherSectionExpanded)
        .animation(.whiskyDefault, value: inputSectionExpanded)
        .animation(.whiskyDefault, value: performanceSectionExpanded)
        .animation(.whiskyDefault, value: dllOverrideSectionExpanded)
        .animation(.whiskyDefault, value: cleanupSectionExpanded)
        .sheet(isPresented: $showStabilityDiagnostics) {
            DiagnosticsReportView(
                title: "Stability Diagnostics Report",
                report: stabilityDiagnosticReport,
                defaultFilenamePrefix: "whisky-stability-diagnostics"
            )
        }
        .sheet(isPresented: $showDiagnosticExportSheet) {
            if let diagnosis = latestDiagnosis, let program = latestDiagnosisProgram {
                DiagnosticExportSheet(
                    diagnosis: diagnosis,
                    bottle: bottle,
                    program: program,
                    logFileURL: program.settings.lastLogFileURL
                )
            }
        }
        .sheet(isPresented: $showCrashDiagnosticsSheet) {
            if let diagnosis = latestDiagnosis, let program = latestDiagnosisProgram {
                DiagnosticsView(
                    diagnosis: diagnosis,
                    logText: latestDiagnosisLogText,
                    programName: program.name,
                    bottleName: bottle.settings.name,
                    timestamp: program.settings.lastDiagnosisDate ?? Date()
                )
                .frame(minWidth: 600, minHeight: 400)
            }
        }
        .alert(item: $prefixRepairResult) { result in
            switch result {
            case .success:
                Alert(
                    title: Text("config.repairPrefix.success"),
                    message: Text("config.repairPrefix.successMessage"),
                    dismissButton: .default(Text("button.ok"))
                )
            case let .failure(message):
                Alert(
                    title: Text("config.repairPrefix.failed"),
                    message: Text(message),
                    dismissButton: .default(Text("button.ok"))
                )
            }
        }
        .bottomBar {
            HStack {
                Spacer()
                Button("config.controlPanel") {
                    Task(priority: .userInitiated) {
                        do {
                            try await Wine.control(bottle: bottle)
                        } catch {
                            logger.error("Failed to launch control: \(error.localizedDescription)")
                        }
                    }
                }
                Button("config.regedit") {
                    Task(priority: .userInitiated) {
                        do {
                            try await Wine.regedit(bottle: bottle)
                        } catch {
                            logger.error("Failed to launch regedit: \(error.localizedDescription)")
                        }
                    }
                }
                Button("config.winecfg") {
                    Task(priority: .userInitiated) {
                        do {
                            try await Wine.cfg(bottle: bottle)
                        } catch {
                            logger.error("Failed to launch winecfg: \(error.localizedDescription)")
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("tab.config")
        .onAppear {
            winVersionLoadingState = .success

            loadBuildName()
            loadRetinaMode()
            loadDpi()

            gameConfigSnapshot = GameConfigSnapshot.load(from: bottle.url)
        }
        .onChange(of: bottle.settings.windowsVersion) { _, newValue in
            if winVersionLoadingState == .success {
                winVersionLoadingState = .loading
                buildVersionLoadingState = .loading
                Task(priority: .userInitiated) {
                    do {
                        try await Wine.changeWinVersion(bottle: bottle, win: newValue)
                        winVersionLoadingState = .success
                        bottle.settings.windowsVersion = newValue
                        loadBuildName()
                    } catch {
                        logger.error("Failed to change Windows version: \(error.localizedDescription)")
                        winVersionLoadingState = .failed
                    }
                }
            }
        }
        .onChange(of: dpiConfig) {
            if dpiConfigLoadingState == .success {
                Task(priority: .userInitiated) {
                    dpiConfigLoadingState = .modifying
                    do {
                        try await Wine.changeDpiResolution(bottle: bottle, dpi: dpiConfig)
                        dpiConfigLoadingState = .success
                    } catch {
                        logger.error("Failed to change DPI resolution: \(error.localizedDescription)")
                        dpiConfigLoadingState = .failed
                    }
                }
            }
        }
    }
}

// MARK: - Loading Functions

extension ConfigView {
    func loadBuildName() {
        buildVersionLoadingState = .loading
        Task(priority: .userInitiated) {
            do {
                if let buildVersionString = try await Wine.buildVersion(bottle: bottle) {
                    buildVersion = Int(buildVersionString) ?? 0
                } else {
                    buildVersion = 0
                }

                buildVersionLoadingState = .success
            } catch {
                logger.error("Failed to load build version: \(error.localizedDescription)")
                buildVersionLoadingState = .failed
            }
        }
    }

    func loadRetinaMode() {
        retinaModeLoadingState = .loading
        Task(priority: .userInitiated) {
            do {
                retinaMode = try await Wine.retinaMode(bottle: bottle)
                retinaModeLoadingState = .success
            } catch {
                logger.error("Failed to get retina mode: \(error.localizedDescription)")
                retinaModeLoadingState = .failed
            }
        }
    }

    func loadDpi() {
        dpiConfigLoadingState = .loading
        Task(priority: .userInitiated) {
            do {
                // Wine.dpiResolution returns nil if registry key doesn't exist (expected for unedited DPI)
                // It throws only on actual Wine/registry errors
                dpiConfig = try await Wine.dpiResolution(bottle: bottle) ?? 0
                dpiConfigLoadingState = .success
            } catch {
                logger.error("Failed to load DPI resolution: \(error.localizedDescription)")
                dpiConfigLoadingState = .failed
            }
        }
    }
}

// MARK: - Game Config Revert

extension ConfigView {
    @ViewBuilder
    var gameConfigRevertSection: some View {
        if let snapshot = gameConfigSnapshot {
            Section(String(localized: "gameConfig.revert.title")) {
                HStack {
                    Image(systemName: "gamecontroller.fill")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        let timeAgo = snapshot.timestamp.formatted(
                            .relative(presentation: .named)
                        )
                        Text("gameConfig.revert.applied \(snapshot.appliedEntryId) \(timeAgo)")
                            .font(.callout)
                        if let verbs = snapshot.installedVerbs, !verbs.isEmpty {
                            Text(
                                "gameConfig.revert.verbsRemain \(verbs.joined(separator: ", "))"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                Button(role: .destructive) {
                    showRevertConfirmation = true
                } label: {
                    Text("gameConfig.revert.button")
                }
                .alert(
                    String(localized: "gameConfig.revert.confirm.title"),
                    isPresented: $showRevertConfirmation
                ) {
                    Button(
                        String(localized: "gameConfig.revert.confirm.revert"),
                        role: .destructive
                    ) {
                        revertGameConfig(snapshot)
                    }
                    Button("button.cancel", role: .cancel) {}
                } message: {
                    Text("gameConfig.revert.confirm.message")
                }
            }
        }
    }

    func revertGameConfig(_ snapshot: GameConfigSnapshot) {
        do {
            let remainingVerbs = try GameConfigApplicator.revert(bottle: bottle, snapshot: snapshot)
            try GameConfigSnapshot.delete(from: bottle.url)
            gameConfigSnapshot = nil
            if !remainingVerbs.isEmpty {
                logger.info(
                    "Config reverted; installed components remain: \(remainingVerbs.joined(separator: ", "))"
                )
            }
        } catch {
            logger.error("Failed to revert game config: \(error.localizedDescription)")
        }
    }
}

// MARK: - Diagnostics Helpers

extension ConfigView {
    var mostRecentlyDiagnosedProgram: Program? {
        bottle.programs
            .filter { $0.settings.lastDiagnosisDate != nil }
            .max { ($0.settings.lastDiagnosisDate ?? .distantPast) < ($1.settings.lastDiagnosisDate ?? .distantPast) }
    }

    func loadLatestDiagnosisAndExport() {
        guard let program = mostRecentlyDiagnosedProgram,
              let logURL = program.settings.lastLogFileURL
        else { return }
        Task {
            guard let diagnosis = await Wine.classifyLastRun(logFileURL: logURL, exitCode: 1) else { return }
            latestDiagnosis = diagnosis
            latestDiagnosisProgram = program
            showDiagnosticExportSheet = true
        }
    }

    func loadLatestDiagnosisAndView() {
        guard let program = mostRecentlyDiagnosedProgram,
              let logURL = program.settings.lastLogFileURL
        else { return }
        Task {
            guard let diagnosis = await Wine.classifyLastRun(logFileURL: logURL, exitCode: 1) else { return }
            latestDiagnosis = diagnosis
            latestDiagnosisProgram = program
            latestDiagnosisLogText = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
            showCrashDiagnosticsSheet = true
        }
    }
}

// swiftlint:enable file_length
