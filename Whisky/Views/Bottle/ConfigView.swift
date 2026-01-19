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
    @State private var isRepairingPrefix: Bool = false
    @State private var prefixRepairResult: PrefixRepairResult?

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
    @AppStorage("dxvkSectionExpanded") private var dxvkSectionExpanded: Bool = true
    @AppStorage("metalSectionExpanded") private var metalSectionExpanded: Bool = true
    @AppStorage("performanceSectionExpanded") private var performanceSectionExpanded: Bool = true
    @AppStorage("launcherSectionExpanded") private var launcherSectionExpanded: Bool = false
    @AppStorage("inputSectionExpanded") private var inputSectionExpanded: Bool = false

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
            DXVKConfigSection(bottle: bottle, isExpanded: $dxvkSectionExpanded)
            MetalConfigSection(bottle: bottle, isExpanded: $metalSectionExpanded)
            PerformanceConfigSection(bottle: bottle, isExpanded: $performanceSectionExpanded)
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
        }
        .formStyle(.grouped)
        .animation(.whiskyDefault, value: wineSectionExpanded)
        .animation(.whiskyDefault, value: launcherSectionExpanded)
        .animation(.whiskyDefault, value: inputSectionExpanded)
        .animation(.whiskyDefault, value: dxvkSectionExpanded)
        .animation(.whiskyDefault, value: metalSectionExpanded)
        .animation(.whiskyDefault, value: performanceSectionExpanded)
        .sheet(isPresented: $showStabilityDiagnostics) {
            DiagnosticsReportView(
                title: "Stability Diagnostics Report",
                report: stabilityDiagnosticReport,
                defaultFilenamePrefix: "whisky-stability-diagnostics"
            )
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
                dpiConfig = try await Wine.dpiResolution(bottle: bottle) ?? 0
                dpiConfigLoadingState = .success
            } catch {
                logger.debug("DPI resolution not set in registry: \(error.localizedDescription)")
                // If DPI has not yet been edited, there will be no registry entry
                dpiConfigLoadingState = .success
            }
        }
    }
}
