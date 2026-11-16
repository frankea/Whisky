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
    /// Read from the runtime's version plist when the picker appears, not on
    /// every redraw. Assumed until then, so a runtime that implements it never
    /// shows the caption, even for a frame.
    @State private var runtimeImplementsEnhancedSync = true

    var body: some View {
        Section("config.title.wine", isExpanded: $isExpanded) {
            SettingItemView(
                title: "config.winVersion",
                description: "config.winVersion.info",
                loadingState: winVersionLoadingState
            ) {
                Picker("config.winVersion", selection: $bottle.settings.windowsVersion) {
                    ForEach(WinVersion.allCases.reversed(), id: \.self) {
                        Text($0.pretty())
                    }
                }
            }
            SettingItemView(
                title: "config.buildVersion",
                description: "config.buildVersion.info",
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
                description: "config.retinaMode.info",
                loadingState: retinaModeLoadingState,
                onRetry: onRetryRetinaMode
            ) {
                VStack(alignment: .trailing, spacing: 4) {
                    Picker("config.retinaMode", selection: retinaModeBinding) {
                        Text("config.retinaMode.on").tag(RetinaModeState.enabled)
                        Text("config.retinaMode.off").tag(RetinaModeState.disabled)
                        Text("config.retinaMode.unknown").tag(RetinaModeState.unknown)
                    }
                    .pickerStyle(.segmented)
                    if retinaModeState == .unknown {
                        Text("config.retinaMode.unknownHint")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Picker("config.enhancedSync", selection: $bottle.settings.enhancedSync) {
                    Text("config.enhancedSync.none").tag(EnhancedSync.none)
                    Text("config.enhancedSync.esync").tag(EnhancedSync.esync)
                    Text("config.enhancedSync.msync").tag(EnhancedSync.msync)
                }
                Text("config.enhancedSync.description")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !runtimeImplementsEnhancedSync {
                    Text("config.enhancedSync.runtimeUnsupported")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .task {
                runtimeImplementsEnhancedSync = WhiskyWineInstaller.runtimeImplementsEnhancedSync()
            }
            SettingItemView(
                title: "config.dpi",
                description: "config.dpi.info",
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

    /// The picker's selection. It writes from the setter rather than an
    /// `onChange(of: retinaModeState)`, because loading assigns the state too
    /// and that must not write the value it just read back to the registry.
    private var retinaModeBinding: Binding<RetinaModeState> {
        Binding(
            get: { retinaModeState },
            set: { newValue in
                guard newValue != retinaModeState else { return }
                retinaModeState = newValue
                guard newValue != .unknown else { return }
                saveRetinaMode(newValue == .enabled)
            }
        )
    }

    private func saveRetinaMode(_ enabled: Bool) {
        Task(priority: .userInitiated) {
            retinaModeLoadingState = .modifying
            do {
                try await Wine.changeRetinaMode(bottle: bottle, retinaMode: enabled)
                retinaModeLoadingState = .success
            } catch {
                Self.logger.error("Failed to change retina mode: \(error.localizedDescription)")
                retinaModeLoadingState = .failed
            }
        }
    }
}
