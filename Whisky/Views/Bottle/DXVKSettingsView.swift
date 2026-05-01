//
//  DXVKSettingsView.swift
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

import AppKit
import SwiftUI
import WhiskyKit

struct DXVKSettingsView: View {
    @ObservedObject var bottle: Bottle
    let resolvedBackend: GraphicsBackend
    let bottleURL: URL

    @State private var confExists: Bool = false

    private var isDXVKActive: Bool {
        resolvedBackend == .dxvk
    }

    private var confURL: URL {
        bottleURL.appending(path: "dxvk.conf")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("config.dxvk.title")
                    .font(.headline)
                if !isDXVKActive {
                    Text("config.dxvk.inactive")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.15), in: Capsule())
                }
            }

            // DXVK Async toggle
            Toggle(isOn: $bottle.settings.dxvkAsync) {
                Text("config.dxvk.async")
            }
            .disabled(!isDXVKActive)

            // DXVK HUD preset picker
            Picker("config.dxvkHud", selection: $bottle.settings.dxvkHud) {
                Text("config.dxvkHud.off").tag(DXVKHUD.off)
                Text("config.dxvkHud.fps").tag(DXVKHUD.fps)
                Text("config.dxvkHud.partial").tag(DXVKHUD.partial)
                Text("config.dxvkHud.full").tag(DXVKHUD.full)
            }
            .disabled(!isDXVKActive)

            // dxvk.conf management
            dxvkConfManagement
        }
    }

    // MARK: - dxvk.conf Management

    private var dxvkConfManagement: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack {
                Text("config.dxvk.confFile")
                    .font(.subheadline)
                Spacer()
                Text(
                    confExists
                        ? confURL.lastPathComponent
                        : String(localized: "config.dxvk.confNotFound")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Button("config.dxvk.openInEditor") {
                    if !confExists {
                        createDefaultConf()
                    }
                    NSWorkspace.shared.open(confURL)
                }
                Button("config.dxvk.revealInFinder") {
                    NSWorkspace.shared.activateFileViewerSelecting([confURL])
                }
                .disabled(!confExists)
                Button("config.dxvk.reset", role: .destructive) {
                    try? FileManager.default.removeItem(at: confURL)
                    confExists = false
                }
                .disabled(!confExists)
            }
            .font(.caption)
        }
        .disabled(!isDXVKActive)
        .onAppear {
            confExists = FileManager.default.fileExists(atPath: confURL.path(percentEncoded: false))
        }
    }

    // MARK: - Default Config Creation

    private func createDefaultConf() {
        let defaultContent = """
        # DXVK Configuration
        # See: https://github.com/doitsujin/dxvk/blob/master/dxvk.conf
        #
        # Uncomment and modify settings as needed.
        # dxgi.maxFrameLatency = 1
        # d3d11.maxFeatureLevel = 11_1
        """
        try? defaultContent.write(to: confURL, atomically: true, encoding: .utf8)
        confExists = true
    }
}
