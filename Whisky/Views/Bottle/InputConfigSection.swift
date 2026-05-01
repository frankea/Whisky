//
//  InputConfigSection.swift
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
struct InputConfigSection: View {
    @ObservedObject var bottle: Bottle
    @Binding var isExpanded: Bool
    @StateObject private var controllerMonitor = ControllerMonitor()
    @State private var controllersExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                // Main toggle for controller compatibility mode
                Toggle("Controller Compatibility Mode", isOn: $bottle.settings.controllerCompatibilityMode)
                    .help("""
                    Enables workarounds for common game controller detection \
                    and mapping issues on macOS (frankea/Whisky#42)
                    """)

                if bottle.settings.controllerCompatibilityMode {
                    // Info notice about controller compatibility
                    controllerCompatInfoBanner

                    Divider()

                    // HIDAPI toggle
                    Toggle("Disable HIDAPI", isOn: $bottle.settings.disableHIDAPI)
                        .help("""
                        Sets SDL_JOYSTICK_HIDAPI=0 to force SDL to use alternative \
                        input backends. May improve detection for some controllers.
                        """)

                    // Background events toggle
                    Toggle("Allow Background Events", isOn: $bottle.settings.allowBackgroundEvents)
                        .help("""
                        Sets SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1 to enable \
                        controller input when the game window doesn't have focus.
                        """)

                    // Button mapping toggle (legacy)
                    Toggle(
                        "Disable Controller Mapping",
                        isOn: $bottle.settings.disableControllerMapping
                    )
                    .help("""
                    Sets SDL_GAMECONTROLLER_USE_BUTTON_LABELS=1 to preserve \
                    native button layouts for PlayStation and Switch controllers \
                    instead of converting to XInput format.
                    """)

                    // Native button labels toggle (new from Plan 02)
                    Toggle("Use Native Button Labels", isOn: $bottle.settings.useButtonLabels)
                        .help("""
                        Preserves physical button positions (Cross/Circle) for \
                        PlayStation controllers instead of XInput layout (A/B/X/Y).
                        """)

                    Divider()

                    // Connected Controllers subpanel
                    connectedControllersPanel

                    Divider()

                    // Helpful links/info
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "questionmark.circle")
                            .foregroundColor(.secondary)

                        Text("""
                        If controllers still don't work, try connecting via USB \
                        instead of Bluetooth, or check if the game has native \
                        controller support settings.
                        """)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.vertical, 8)
        } label: {
            HStack {
                Label("Controller & Input", systemImage: "gamecontroller")
                    .font(.headline)

                if bottle.settings.controllerCompatibilityMode {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }
        }
        .onAppear {
            controllerMonitor.startMonitoring()
        }
        .onDisappear {
            controllerMonitor.stopMonitoring()
        }
    }

    // MARK: - Info Banner

    private var controllerCompatInfoBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(.blue)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text("Controller Workarounds")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)

                Text("""
                These settings modify SDL environment variables to improve \
                controller detection and button mapping. Try different \
                combinations if your controller isn't working correctly.
                """)
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Connected Controllers Panel

    private var connectedControllersPanel: some View {
        DisclosureGroup(isExpanded: $controllersExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                if controllerMonitor.controllers.isEmpty {
                    emptyControllerState
                } else {
                    controllerList
                    bluetoothWarningBanner
                }

                controllerActionButtons

                // Last refreshed timestamp
                Text(
                    "Last refreshed: \(controllerMonitor.lastRefreshed, style: .relative) ago"
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        } label: {
            HStack(spacing: 6) {
                Label("Connected Controllers", systemImage: "gamecontroller.fill")
                    .font(.subheadline)
                    .fontWeight(.medium)

                if !controllerMonitor.controllers.isEmpty {
                    Text("\(controllerMonitor.controllers.count)")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyControllerState: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "gamecontroller")
                    .foregroundStyle(.secondary)
                Text("No controllers detected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text("Try connecting via USB or check System Settings > Bluetooth")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Controller List

    private var controllerList: some View {
        ForEach(controllerMonitor.controllers) { controller in
            controllerRow(controller)
        }
    }

    private func controllerRow(_ controller: ControllerInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Controller name
            Text(controller.name)
                .font(.callout)
                .fontWeight(.semibold)

            HStack(spacing: 12) {
                // Type badge
                HStack(spacing: 4) {
                    Image(systemName: controller.typeBadge.sfSymbol)
                        .font(.caption)
                    Text(controller.typeBadge.displayName)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)

                // Connection badge
                HStack(spacing: 4) {
                    Image(systemName: controller.connectionType.sfSymbol)
                        .font(.caption)
                    Text(controller.connectionType.rawValue)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)

                // Battery level
                if let level = controller.batteryLevel {
                    HStack(spacing: 4) {
                        Image(systemName: batterySymbol(level: level, state: controller.batteryState))
                            .font(.caption)
                        Text("Battery: \(Int(level * 100))%")
                            .font(.caption)
                        if controller.batteryState == "charging" {
                            Image(systemName: "bolt.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Bluetooth Warning Banner

    @ViewBuilder
    private var bluetoothWarningBanner: some View {
        let hasBluetoothController = controllerMonitor.controllers.contains {
            $0.connectionType == .bluetooth
        }

        if hasBluetoothController {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.caption)

                Text("Bluetooth dropouts can break input; USB is more reliable")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(6)
        }
    }

    // MARK: - Action Buttons

    private var controllerActionButtons: some View {
        HStack(spacing: 12) {
            Button {
                controllerMonitor.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.borderless)

            Button {
                copyControllerInfo()
            } label: {
                Label("Copy Controller Info", systemImage: "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .disabled(controllerMonitor.controllers.isEmpty)

            Spacer()

            // Test Input hint
            Text("Test Input: System Settings > Game Controllers")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Helpers

    private func batterySymbol(level: Float, state: String?) -> String {
        if state == "charging" {
            return "battery.100.bolt"
        }
        switch level {
        case 0.75...:
            return "battery.100"
        case 0.50 ..< 0.75:
            return "battery.75"
        case 0.25 ..< 0.50:
            return "battery.50"
        default:
            return "battery.25"
        }
    }

    private func copyControllerInfo() {
        var lines = ["Connected Controllers:"]
        for controller in controllerMonitor.controllers {
            lines.append("  - \(controller.name)")
            lines.append("    Type: \(controller.typeBadge.displayName)")
            lines.append("    Connection: \(controller.connectionType.rawValue)")
            if let level = controller.batteryLevel {
                let stateStr = controller.batteryState.map { " (\($0))" } ?? ""
                lines.append("    Battery: \(Int(level * 100))%\(stateStr)")
            }
            lines.append("    Product Category: \(controller.productCategory)")
        }
        lines.append("")
        lines.append("History:")
        for entry in controllerMonitor.recentHistory {
            lines.append(
                "  - \(entry.name) (\(entry.connectionType)) last seen: "
                    + "\(entry.lastSeen.formatted(.dateTime.month().day().hour().minute()))"
            )
        }

        let text = lines.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// swiftlint:enable type_body_length
