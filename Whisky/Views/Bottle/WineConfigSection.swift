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

enum RetinaModeState: Equatable {
    case enabled, disabled, unknown
}

struct WineConfigSection: View {
    private static let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "ConfigView")
    @ObservedObject var bottle: Bottle
    @Binding var isExpanded: Bool
    @Binding var buildVersion: String
    @Binding var retinaModeState: RetinaModeState
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
                TextField(
                    "config.buildVersion.notSet",
                    text: $buildVersion
                )
                .multilineTextAlignment(.trailing)
                .textFieldStyle(PlainTextFieldStyle())
                .onSubmit {
                    guard let version = Int(buildVersion) else { return }
                    buildVersionLoadingState = .modifying
                    Task(priority: .userInitiated) {
                        do {
                            try await Wine.changeBuildVersion(bottle: bottle, version: version)
                            buildVersionLoadingState = .success
                        } catch {
                            Self.logger.error(
                                "Failed to change build version: \(error.localizedDescription)"
                            )
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
                VStack(alignment: .trailing, spacing: 4) {
                    Picker("config.retinaMode", selection: $retinaModeState) {
                        Text("config.retinaMode.on").tag(RetinaModeState.enabled)
                        Text("config.retinaMode.off").tag(RetinaModeState.disabled)
                        Text("config.retinaMode.unknown").tag(RetinaModeState.unknown)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: retinaModeState) { oldValue, newValue in
                        guard newValue != .unknown, newValue != oldValue else { return }
                        let boolValue = newValue == .enabled
                        Task(priority: .userInitiated) {
                            retinaModeLoadingState = .modifying
                            do {
                                try await Wine.changeRetinaMode(
                                    bottle: bottle, retinaMode: boolValue
                                )
                                retinaModeLoadingState = .success
                            } catch {
                                Self.logger.error(
                                    "Failed to change retina mode: \(error.localizedDescription)"
                                )
                                retinaModeLoadingState = .failed
                            }
                        }
                    }
                    if retinaModeState == .unknown {
                        Text("config.retinaMode.unknownHint")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                        isRetinaMode: Binding(
                            get: { retinaModeState == .enabled },
                            set: { _ in }
                        ),
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
