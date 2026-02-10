//
//  AudioDeviceHistoryView.swift
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

/// Device change event log for Advanced audio diagnostics.
///
/// Displays events in reverse chronological order (newest first) with
/// event type icons, descriptions, transport type badges, and relative
/// timestamps.
struct AudioDeviceHistoryView: View {
    let history: AudioDeviceHistory

    private var reversedEvents: [AudioDeviceChangeEvent] {
        history.events.reversed()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if history.events.isEmpty {
                Text(String(localized: "audio.history.none"))
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach(reversedEvents) { event in
                    eventRow(event)
                }

                Button(String(localized: "audio.history.clear")) {
                    history.clear()
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
        }
    }

    private func eventRow(_ event: AudioDeviceChangeEvent) -> some View {
        HStack(spacing: 8) {
            Image(systemName: eventIcon(event.eventType))
                .foregroundStyle(eventColor(event.eventType))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(eventDescription(event))
                    .font(.caption)
                HStack(spacing: 4) {
                    Text(event.transportType.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                    Text(event.timestamp, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func eventIcon(_ eventType: AudioDeviceChangeEvent.EventType) -> String {
        switch eventType {
        case .defaultOutputChanged: "speaker.wave.2"
        case .disconnected: "speaker.slash"
        case .reconnected: "speaker.wave.3"
        case .sampleRateChanged: "waveform"
        }
    }

    private func eventColor(_ eventType: AudioDeviceChangeEvent.EventType) -> Color {
        switch eventType {
        case .defaultOutputChanged: .blue
        case .disconnected: .red
        case .reconnected: .green
        case .sampleRateChanged: .orange
        }
    }

    private func eventDescription(_ event: AudioDeviceChangeEvent) -> String {
        switch event.eventType {
        case .defaultOutputChanged:
            "Default output changed to \(event.deviceName)"
        case .disconnected:
            "\(event.deviceName) disconnected"
        case .reconnected:
            "\(event.deviceName) reconnected"
        case .sampleRateChanged:
            "Sample rate changed on \(event.deviceName)"
        }
    }
}
