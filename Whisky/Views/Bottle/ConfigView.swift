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

import SwiftUI
import WhiskyKit
import os

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
    @AppStorage("wineSectionExpanded") private var wineSectionExpanded: Bool = true
    @AppStorage("dxvkSectionExpanded") private var dxvkSectionExpanded: Bool = true
    @AppStorage("metalSectionExpanded") private var metalSectionExpanded: Bool = true
    @AppStorage("performanceSectionExpanded") private var performanceSectionExpanded: Bool = true

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
                dpiSheetPresented: $dpiSheetPresented
            )
            DXVKConfigSection(bottle: bottle, isExpanded: $dxvkSectionExpanded)
            MetalConfigSection(bottle: bottle, isExpanded: $metalSectionExpanded)
            PerformanceConfigSection(bottle: bottle, isExpanded: $performanceSectionExpanded)
        }
        .formStyle(.grouped)
        .animation(.whiskyDefault, value: wineSectionExpanded)
        .animation(.whiskyDefault, value: dxvkSectionExpanded)
        .animation(.whiskyDefault, value: metalSectionExpanded)
        .animation(.whiskyDefault, value: performanceSectionExpanded)
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

            Task(priority: .userInitiated) {
                do {
                    retinaMode = try await Wine.retinaMode(bottle: bottle)
                    retinaModeLoadingState = .success
                } catch {
                    logger.error("Failed to get retina mode: \(error.localizedDescription)")
                    retinaModeLoadingState = .failed
                }
            }
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
}
