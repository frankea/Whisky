//
//  AudioDeviceListView.swift
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

/// Full device list for Advanced audio diagnostics.
///
/// Displays all output devices with transport type badge, sample rate,
/// channel count, and default device indicator. Sorted with the default
/// device first, then alphabetical by name.
struct AudioDeviceListView: View {
    let devices: [AudioDeviceInfo]

    private var sortedDevices: [AudioDeviceInfo] {
        devices.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault {
                return lhs.isDefault
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        if devices.isEmpty {
            Text(String(localized: "audio.devices.none"))
                .foregroundStyle(.secondary)
                .font(.callout)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(sortedDevices) { device in
                    deviceRow(device)
                }
            }
        }
    }

    private func deviceRow(_ device: AudioDeviceInfo) -> some View {
        HStack(spacing: 8) {
            Text(device.name)
                .fontWeight(device.isDefault ? .semibold : .regular)

            if device.isDefault {
                Text(String(localized: "audio.devices.default"))
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.15), in: Capsule())
                    .foregroundStyle(.blue)
            }

            Text(device.transportType.displayName)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15), in: Capsule())

            Spacer()

            Text("\(Int(device.sampleRate)) Hz")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("\(device.outputChannelCount)ch")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
