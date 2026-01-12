//
//  MetalConfigSection.swift
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

import Metal
import SwiftUI
import WhiskyKit

struct MetalConfigSection: View {
    @ObservedObject var bottle: Bottle
    @Binding var isExpanded: Bool

    var body: some View {
        Section("config.title.metal", isExpanded: $isExpanded) {
            Toggle(isOn: $bottle.settings.metalHud) {
                Text("config.metalHud")
            }
            Toggle(isOn: $bottle.settings.metalTrace) {
                Text("config.metalTrace")
                Text("config.metalTrace.info")
            }
            if let device = MTLCreateSystemDefaultDevice() {
                // Represents the Apple family 9 GPU features that correspond to the Apple A17, M3, and M4 GPUs.
                if device.supportsFamily(.apple9) {
                    Toggle(isOn: $bottle.settings.dxrEnabled) {
                        Text("config.dxr")
                        Text("config.dxr.info")
                    }
                }
            }
            // Sequoia compatibility mode - helps with macOS 15.x issues
            Toggle(isOn: $bottle.settings.sequoiaCompatMode) {
                VStack(alignment: .leading) {
                    Text("config.sequoiaCompat")
                    Text("config.sequoiaCompat.info")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
