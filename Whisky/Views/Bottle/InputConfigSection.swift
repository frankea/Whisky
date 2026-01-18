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

struct InputConfigSection: View {
    @ObservedObject var bottle: Bottle
    @Binding var isExpanded: Bool

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

                    // Button mapping toggle
                    Toggle("Use Native Button Labels", isOn: $bottle.settings.disableControllerMapping)
                        .help("""
                        Sets SDL_GAMECONTROLLER_USE_BUTTON_LABELS=1 to preserve \
                        native button layouts for PlayStation and Switch controllers \
                        instead of converting to XInput format.
                        """)

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
    }
}
