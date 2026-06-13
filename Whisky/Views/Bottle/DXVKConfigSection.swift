//
//  DXVKConfigSection.swift
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

struct DXVKConfigSection: View {
    @ObservedObject var bottle: Bottle
    @Binding var isExpanded: Bool

    var body: some View {
        Section("config.title.dxvk", isExpanded: $isExpanded) {
            Toggle(isOn: $bottle.settings.dxvk) {
                VStack(alignment: .leading) {
                    Text("config.dxvk")
                    Text("config.dxvk.info")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Toggle(isOn: $bottle.settings.dxvkAsync) {
                VStack(alignment: .leading) {
                    Text("config.dxvk.async")
                    Text("config.dxvk.async.info")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!bottle.settings.dxvk)
            VStack(alignment: .leading, spacing: 2) {
                Picker("config.dxvkHud", selection: $bottle.settings.dxvkHud) {
                    Text("config.dxvkHud.full").tag(DXVKHUD.full)
                    Text("config.dxvkHud.partial").tag(DXVKHUD.partial)
                    Text("config.dxvkHud.fps").tag(DXVKHUD.fps)
                    Text("config.dxvkHud.off").tag(DXVKHUD.off)
                }
                Text("config.dxvkHud.info")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(!bottle.settings.dxvk)
        }
    }
}
