// swiftlint:disable file_length
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

import os.log
import SwiftUI
import WhiskyKit

private let launcherConfigLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.franke.Whisky",
    category: "LauncherConfig"
)

struct LauncherConfigSection: View {
    @ObservedObject var bottle: Bottle
    @Binding var isExpanded: Bool
    @State private var overridesExpanded: Bool = false

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
                    launcherCompatibilityControls
                }
            }
            .padding(.vertical, 8)
        } label: {
            launcherSectionLabel
        }
    }

    // MARK: - Section Label

    private var launcherSectionLabel: some View {
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
}

// MARK: - Launcher Compatibility Controls

extension LauncherConfigSection {
    @ViewBuilder
    private var launcherCompatibilityControls: some View {
        // Security notice about CEF sandbox
        cefSecurityNotice

        Divider()

        // Detection mode selection
        detectionModeControls

        Divider()

        // Locale override
        localeControls

        // GPU spoofing
        gpuSpoofingControls

        Divider()

        // Network configuration
        networkControls

        // Auto-enable DXVK
        Toggle("Auto-Enable DXVK for Launchers", isOn: $bottle.settings.autoEnableDXVK)
            .help("""
            Automatically enables DXVK when launcher requires it \
            (e.g., Rockstar Games Launcher)
            """)

        Divider()

        // Active Environment Overrides provenance display
        ActiveEnvironmentOverrides(
            launcher: bottle.settings.detectedLauncher,
            isExpanded: $overridesExpanded
        )

        Divider()

        // Link to Diagnostics section (replaces inline diagnostics button)
        HStack {
            Spacer()
            Button {
                NotificationCenter.default.post(
                    name: .openDiagnosticsSection,
                    object: nil
                )
            } label: {
                Label("View Diagnostics", systemImage: "stethoscope")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Spacer()
        }

        // Configuration warnings
        configurationWarnings
    }

    private var cefSecurityNotice: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundColor(.orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text("Security Note")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)

                Text("""
                Launcher compatibility disables the Chromium sandbox (required for Wine). \
                This allows Steam, Epic, EA App, and Rockstar launchers to function, but \
                embedded browser content runs with full process privileges. Only use with \
                trusted launchers from reputable companies.
                """)
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }

    @ViewBuilder
    private var detectionModeControls: some View {
        Picker("Detection Mode:", selection: $bottle.settings.launcherMode) {
            Text("Automatic").tag(LauncherMode.auto)
            Text("Manual").tag(LauncherMode.manual)
        }
        .pickerStyle(.segmented)
        .help("""
        Automatic: Detects launcher from executable path\n\
        Manual: Use explicitly selected launcher type
        """)

        if bottle.settings.launcherMode == .manual {
            Picker("Launcher Type:", selection: $bottle.settings.detectedLauncher) {
                Text("None").tag(nil as LauncherType?)
                ForEach(LauncherType.allCases) { launcher in
                    Text(launcher.rawValue).tag(launcher as LauncherType?)
                }
            }
            .help("Manually select the launcher type for this bottle")

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
    }

    private var localeControls: some View {
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
    }

    @ViewBuilder
    private var gpuSpoofingControls: some View {
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
    }

    private var networkControls: some View {
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
    }

    @ViewBuilder
    private var configurationWarnings: some View {
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

// MARK: - Active Environment Overrides (Provenance Display)

/// Expandable provenance display showing launcher and platform environment overrides.
///
/// Displays all managed environment variables with their reasons, grouped by
/// ``FixCategory``. Launcher-specific fixes and macOS compatibility fixes are
/// shown in separate subsections. All entries are non-editable (marked with lock icon).
private struct ActiveEnvironmentOverrides: View {
    let launcher: LauncherType?
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroup("Active Environment Overrides", isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                if let launcher {
                    launcherFixesSection(launcher)
                }

                platformFixesSection
            }
            .padding(.top, 4)
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }

    // MARK: - Launcher Fixes

    @ViewBuilder
    private func launcherFixesSection(_ launcher: LauncherType) -> some View {
        let details = launcher.fixDetails()
        let grouped = Dictionary(grouping: details, by: \.category)
        let sortedCategories = grouped.keys.sorted { $0.rawValue < $1.rawValue }

        VStack(alignment: .leading, spacing: 8) {
            Label("\(launcher.displayName) Fixes", systemImage: "gamecontroller")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.primary)

            ForEach(sortedCategories, id: \.self) { category in
                if let fixes = grouped[category] {
                    categoryGroup(category: category, fixes: fixes, provenance: nil)
                }
            }
        }
    }

    // MARK: - Platform Fixes

    @ViewBuilder
    private var platformFixesSection: some View {
        let activeFixes = MacOSCompatibilityFixes.activeFixes()
        let grouped = Dictionary(grouping: activeFixes, by: \.category)
        let sortedCategories = grouped.keys.sorted { $0.rawValue < $1.rawValue }

        if !activeFixes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Platform Fixes", systemImage: "desktopcomputer")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                ForEach(sortedCategories, id: \.self) { category in
                    if let fixes = grouped[category] {
                        macOSCategoryGroup(category: category, fixes: fixes)
                    }
                }
            }
        }
    }

    // MARK: - Category Group Views

    private func categoryGroup(
        category: FixCategory,
        fixes: [LauncherFixDetail],
        provenance: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(categoryDisplayName(category))
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            ForEach(fixes, id: \.key) { fix in
                fixRow(key: fix.key, value: fix.value, reason: fix.reason)
            }
        }
    }

    private func macOSCategoryGroup(
        category: FixCategory,
        fixes: [MacOSFix]
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(categoryDisplayName(category))
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            ForEach(fixes, id: \.key) { fix in
                fixRow(
                    key: fix.key,
                    value: fix.value,
                    reason: "Applied because macOS >= \(fix.appliesFrom.description): \(fix.reason)"
                )
            }
        }
    }

    // MARK: - Individual Fix Row

    private func fixRow(key: String, value: String, reason: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.caption2)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(key)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.primary)
                    +
                    Text("=")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    +
                    Text(value)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.primary)

                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, 8)
    }

    // MARK: - Helpers

    private func categoryDisplayName(_ category: FixCategory) -> String {
        switch category {
        case .locale: "Locale"
        case .sandbox: "Sandbox"
        case .graphics: "Graphics"
        case .network: "Network"
        case .threading: "Threading"
        case .compatibility: "Compatibility"
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted to navigate to the Diagnostics section in ConfigView.
    static let openDiagnosticsSection = Notification.Name(
        "com.isaacmarovitz.Whisky.openDiagnosticsSection"
    )
}

// MARK: - Diagnostics Report View (Shared)

/// View for displaying diagnostic report in a sheet (shared across the Whisky app target).
struct DiagnosticsReportView: View {
    let title: String
    let report: String
    let defaultFilenamePrefix: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(title)
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
        savePanel.nameFieldStringValue = "\(defaultFilenamePrefix)-\(Date().timeIntervalSince1970).txt"

        if savePanel.runModal() == .OK, let url = savePanel.url {
            do {
                try report.write(to: url, atomically: true, encoding: .utf8)
                launcherConfigLogger.info("Diagnostics report exported successfully to: \(url.path)")
            } catch {
                launcherConfigLogger.error("Failed to export diagnostics report: \(error.localizedDescription)")

                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "Failed to Export Diagnostics Report"
                alert.informativeText = """
                An error occurred while saving the diagnostics report:

                \(error.localizedDescription)

                Please try again or choose a different location.
                """
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }
}

// swiftlint:enable file_length
