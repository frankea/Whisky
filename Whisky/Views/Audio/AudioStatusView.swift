//
//  AudioStatusView.swift
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

/// Displays the current audio health status with device baseline information.
struct AudioStatusView: View {
    let audioStatus: AudioStatus
    let lastTestedDate: Date?
    let defaultDeviceName: String?
    let transportType: AudioTransportType?
    let sampleRate: Double?
    let channelCount: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            statusLine
            baselineInfoRow
        }
    }

    // MARK: - Status Line

    private var statusLine: some View {
        HStack(spacing: 6) {
            Image(systemName: audioStatus.sfSymbol)
                .foregroundStyle(statusColor)
            Text(audioStatus.displayName)
                .fontWeight(.medium)
            if let issueText = primaryIssueText {
                Text("\u{2014} \(issueText)")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var primaryIssueText: String? {
        switch audioStatus {
        case let .degraded(primaryIssue):
            primaryIssue
        case let .broken(primaryIssue):
            primaryIssue
        default:
            nil
        }
    }

    private var statusColor: Color {
        switch audioStatus.tintColor {
        case "green": .green
        case "orange": .orange
        case "red": .red
        default: .secondary
        }
    }

    // MARK: - Baseline Info Row

    private var baselineInfoRow: some View {
        HStack(spacing: 8) {
            if let name = defaultDeviceName {
                Text(name)
            }
            if let transport = transportType, transport != .unknown {
                Text(transport.displayName)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            }
            if let rate = sampleRate, rate > 0 {
                Text("\(Int(rate)) Hz")
            }
            if let channels = channelCount, channels > 0 {
                Text("\(channels)ch")
            }
            if let date = lastTestedDate {
                Spacer()
                HStack(spacing: 4) {
                    Text("Last tested")
                    Text(date, style: .relative)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
