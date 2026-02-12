//
//  TroubleshootingEntryBanner.swift
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

/// Compact banner for proactive troubleshooting suggestions or session resume prompts.
///
/// Shows as a tappable horizontal bar with an icon and message. Used in ProgramView
/// and ConfigView to surface active sessions or suggest troubleshooting when
/// strong failure signals are detected.
struct TroubleshootingEntryBanner: View {
    let bannerType: BannerType
    let action: () -> Void

    /// The type of troubleshooting banner to display.
    enum BannerType {
        /// Prompt to resume a paused troubleshooting session.
        case resumeSession
        /// Proactive suggestion that a troubleshooting guide is available.
        case proactiveSuggestion

        var icon: String {
            switch self {
            case .resumeSession: "play.circle"
            case .proactiveSuggestion: "lightbulb"
            }
        }

        var message: String {
            switch self {
            case .resumeSession: String(localized: "troubleshooting.entry.resumeSession")
            case .proactiveSuggestion: String(localized: "troubleshooting.entry.proactive")
            }
        }

        var tintColor: Color {
            switch self {
            case .resumeSession: .blue
            case .proactiveSuggestion: .orange
            }
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: bannerType.icon)
                    .foregroundStyle(bannerType.tintColor)
                Text(bannerType.message)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.controlBackgroundColor))
            )
        }
        .buttonStyle(.plain)
    }
}
