//
//  WineConfigSection.swift
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

struct WineConfigSection: View {
    private static let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "ConfigView")
    @ObservedObject var bottle: Bottle
    @Binding var isExpanded: Bool
    @Binding var buildVersion: Int
    @Binding var retinaMode: Bool
    @Binding var dpiConfig: Int
    @Binding var winVersionLoadingState: LoadingState
    @Binding var buildVersionLoadingState: LoadingState
    @Binding var retinaModeLoadingState: LoadingState
    @Binding var dpiConfigLoadingState: LoadingState
    @Binding var dpiSheetPresented: Bool
    var onRetryBuildVersion: (() -> Void)?
    var onRetryRetinaMode: (() -> Void)?
    var onRetryDpi: (() -> Void)?

    var body: some View {
        Section("config.title.wine", isExpanded: $isExpanded) {
            SettingItemView(title: "config.winVersion", loadingState: winVersionLoadingState) {
                Picker("config.winVersion", selection: $bottle.settings.windowsVersion) {
                    ForEach(WinVersion.allCases.reversed(), id: \.self) {
                        Text($0.pretty())
                    }
                }
            }
            SettingItemView(
                title: "config.buildVersion",
                loadingState: buildVersionLoadingState,
                onRetry: onRetryBuildVersion
            ) {
                TextField("config.buildVersion", value: $buildVersion, formatter: NumberFormatter())
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(PlainTextFieldStyle())
                    .onSubmit {
                        buildVersionLoadingState = .modifying
                        Task(priority: .userInitiated) {
                            do {
                                try await Wine.changeBuildVersion(bottle: bottle, version: buildVersion)
                                buildVersionLoadingState = .success
                            } catch {
                                Self.logger.error("Failed to change build version: \(error.localizedDescription)")
                                buildVersionLoadingState = .failed
                            }
                        }
                    }
            }
            SettingItemView(
                title: "config.retinaMode",
                loadingState: retinaModeLoadingState,
                onRetry: onRetryRetinaMode
            ) {
                Toggle("config.retinaMode", isOn: $retinaMode)
                    .onChange(of: retinaMode) { _, newValue in
                        Task(priority: .userInitiated) {
                            retinaModeLoadingState = .modifying
                            do {
                                try await Wine.changeRetinaMode(bottle: bottle, retinaMode: newValue)
                                retinaModeLoadingState = .success
                            } catch {
                                Self.logger.error("Failed to change retina mode: \(error.localizedDescription)")
                                retinaModeLoadingState = .failed
                            }
                        }
                    }
            }
            Picker("config.enhancedSync", selection: $bottle.settings.enhancedSync) {
                Text("config.enhancedSync.none").tag(EnhancedSync.none)
                Text("config.enhancedSync.esync").tag(EnhancedSync.esync)
                Text("config.enhancedSync.msync").tag(EnhancedSync.msync)
            }
            SettingItemView(
                title: "config.dpi",
                loadingState: dpiConfigLoadingState,
                onRetry: onRetryDpi
            ) {
                Button("config.inspect") {
                    dpiSheetPresented = true
                }
                .sheet(isPresented: $dpiSheetPresented) {
                    DPIConfigSheetView(
                        dpiConfig: $dpiConfig,
                        isRetinaMode: $retinaMode,
                        presented: $dpiSheetPresented
                    )
                }
            }
            Toggle(isOn: $bottle.settings.avxEnabled) {
                VStack(alignment: .leading) {
                    Text("config.avx")
                    if bottle.settings.avxEnabled {
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .symbolRenderingMode(.multicolor)
                                .font(.subheadline)
                            Text("config.avx.warning")
                                .fontWeight(.light)
                                .font(.subheadline)
                        }
                    }
                }
            }
        }
    }
}
