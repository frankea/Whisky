//
//  GameConfigBannerView.swift
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

/// A compact contextual banner that appears when a game configuration match is found
/// for the current program. Shows the match title, an apply action, match explanation,
/// and a "Not this" dismissal button.
struct GameConfigBannerView: View {
    let matchResult: MatchResult
    @ObservedObject var bottle: Bottle
    let programURL: URL?
    @State private var isDismissed: Bool = false
    @State private var showDetail: Bool = false
    @State private var showExplanation: Bool = false

    var body: some View {
        if !isDismissed {
            bannerContent
                .sheet(isPresented: $showDetail) {
                    GameEntryDetailView(entry: matchResult.entry, bottle: bottle)
                        .frame(minWidth: 600, minHeight: 500)
                }
        }
    }

    private var bannerContent: some View {
        HStack(spacing: 8) {
            Image(systemName: "gamecontroller.fill")
                .foregroundStyle(Color.accentColor)

            Text("gameConfig.banner.available \(matchResult.entry.title)")
                .font(.callout)
                .lineLimit(1)

            Spacer()

            Button(String(localized: "gameConfig.banner.apply")) {
                showDetail = true
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)

            Button {
                showExplanation.toggle()
            } label: {
                Text("gameConfig.banner.why")
                    .font(.caption)
            }
            .controlSize(.small)
            .popover(isPresented: $showExplanation) {
                Text(matchResult.explanation)
                    .font(.caption)
                    .padding()
                    .frame(maxWidth: 280)
            }

            Button {
                withAnimation {
                    isDismissed = true
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(String(localized: "gameConfig.banner.notThis"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal)
    }
}
