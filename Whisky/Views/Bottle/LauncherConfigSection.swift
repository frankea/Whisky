//
//  LauncherConfigSection.swift
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

struct LauncherConfigSection: View {
    @ObservedObject var bottle: Bottle
    @Binding var isExpanded: Bool
    @State private var showDiagnostics: Bool = false
    @State private var diagnosticReport: String = ""

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                // Enable launcher compatibility mode
                Toggle("Launcher Compatibility Mode", isOn: $bottle.settings.launcherCompatibilityMode)
                    .help("""
                    Enables automatic fixes for Steam, Rockstar, EA App, Epic Games, \
                    and other game launchers (frankea/Whisky#41)
                    """)

                if bottle.settings.launcherCompatibilityMode {
                    Divider()

                    // Detection mode selection
                    Picker("Detection Mode:", selection: $bottle.settings.launcherMode) {
                        Text("Automatic").tag(LauncherMode.auto)
                        Text("Manual").tag(LauncherMode.manual)
                    }
                    .pickerStyle(.segmented)
                    .help("""
                    Automatic: Detects launcher from executable path\n\
                    Manual: Use explicitly selected launcher type
                    """)

                    // Manual launcher selection (only shown in manual mode)
                    if bottle.settings.launcherMode == .manual {
                        Picker("Launcher Type:", selection: $bottle.settings.detectedLauncher) {
                            Text("None").tag(nil as LauncherType?)
                            ForEach(LauncherType.allCases) { launcher in
                                Text(launcher.rawValue).tag(launcher as LauncherType?)
                            }
                        }
                        .help("Manually select the launcher type for this bottle")

                        // Show fixes description if launcher selected
                        if let launcher = bottle.settings.detectedLauncher {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(.blue)
                                Text(launcher.fixesDescription)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    } else {
                        // Show currently detected launcher in auto mode
                        if let launcher = bottle.settings.detectedLauncher {
                            HStack {
                                Text("Detected:")
                                    .foregroundColor(.secondary)
                                Text(launcher.rawValue)
                                    .fontWeight(.medium)
                            }
                            .font(.caption)
                        }
                    }

                    Divider()

                    // Locale override
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("Locale Override:", selection: $bottle.settings.launcherLocale) {
                            ForEach(Locales.allCases, id: \.self) { locale in
                                Text(locale.pretty()).tag(locale)
                            }
                        }
                        .help("""
                        Steam and Chromium-based launchers require en_US locale \
                        to avoid steamwebhelper crashes
                        """)

                        if bottle.settings.launcherLocale != .auto {
                            Text("""
                            Forces \(bottle.settings.launcherLocale.pretty()) locale \
                            to fix steamwebhelper crashes
                            """)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }

                    // GPU spoofing
                    Toggle("GPU Spoofing", isOn: $bottle.settings.gpuSpoofing)
                        .help("""
                        Reports high-end GPU to pass launcher compatibility checks. \
                        Fixes EA App black screen and "GPU not supported" errors.
                        """)

                    if bottle.settings.gpuSpoofing {
                        Picker("GPU Vendor:", selection: $bottle.settings.gpuVendor) {
                            ForEach(GPUVendor.allCases, id: \.self) { vendor in
                                Text(vendor.modelName).tag(vendor)
                            }
                        }
                        .help("NVIDIA (recommended) provides best compatibility across launchers")
                    }

                    Divider()

                    // Network configuration
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Network Timeout:")
                            Spacer()
                            Text("\(bottle.settings.networkTimeout / 1_000)s")
                                .foregroundColor(.secondary)
                        }

                        Slider(
                            value: Binding(
                                get: { Double(bottle.settings.networkTimeout) },
                                set: { bottle.settings.networkTimeout = Int($0) }
                            ),
                            in: 30_000 ... 180_000,
                            step: 15_000
                        )

                        Text("Fixes Steam download stalls and connection timeouts")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Auto-enable DXVK
                    Toggle("Auto-Enable DXVK for Launchers", isOn: $bottle.settings.autoEnableDXVK)
                        .help("""
                        Automatically enables DXVK when launcher requires it \
                        (e.g., Rockstar Games Launcher)
                        """)

                    Divider()

                    // Diagnostics button
                    HStack {
                        Spacer()
                        Button("Generate Diagnostics Report") {
                            Task {
                                diagnosticReport = await LauncherDiagnostics.generateDiagnosticReport(for: bottle)
                                showDiagnostics = true
                            }
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                    }

                    // Configuration warnings
                    if let launcher = bottle.settings.detectedLauncher {
                        let warnings = LauncherDetection.validateBottleForLauncher(
                            bottle,
                            launcher: launcher
                        )

                        if !warnings.isEmpty {
                            Divider()

                            VStack(alignment: .leading, spacing: 4) {
                                Label("Configuration Warnings", systemImage: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .fontWeight(.medium)

                                ForEach(warnings, id: \.self) { warning in
                                    Text(warning)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.leading, 24)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        } label: {
            HStack {
                Label("Launcher Compatibility", systemImage: "gamecontroller.fill")
                    .font(.headline)

                if bottle.settings.launcherCompatibilityMode {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }

                if let launcher = bottle.settings.detectedLauncher {
                    Text("(\(launcher.rawValue))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .sheet(isPresented: $showDiagnostics) {
            DiagnosticsReportView(report: diagnosticReport)
        }
    }
}

/// View for displaying diagnostic report in a sheet
struct DiagnosticsReportView: View {
    let report: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Launcher Diagnostics Report")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            ScrollView {
                Text(report)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal)

            HStack {
                Spacer()

                Button("Copy to Clipboard") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                }
                .buttonStyle(.bordered)

                Button("Export to File") {
                    exportReport()
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .frame(width: 700, height: 600)
    }

    private func exportReport() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = "whisky-diagnostics-\(Date().timeIntervalSince1970).txt"

        if savePanel.runModal() == .OK, let url = savePanel.url {
            do {
                try report.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                // Handle error silently or show alert
            }
        }
    }
}
