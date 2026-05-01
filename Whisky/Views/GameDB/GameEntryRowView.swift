//
//  GameEntryRowView.swift
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

/// A list row displaying a game database entry with rating badge, tags, and a note.
struct GameEntryRowView: View {
    let entry: GameDBEntry

    var body: some View {
        HStack(spacing: 10) {
            ratingBadge
            titleArea
            Spacer()
            tagsArea
            noteArea
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    // MARK: - Rating Badge

    private var ratingBadge: some View {
        Text(entry.rating.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(ratingForegroundColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(ratingBackgroundColor)
            .clipShape(Capsule())
    }

    private var ratingBackgroundColor: Color {
        switch entry.rating {
        case .works:
            .green
        case .playable:
            .orange
        case .unverified:
            .gray
        case .broken:
            .red
        case .notSupported:
            Color(.darkGray)
        }
    }

    private var ratingForegroundColor: Color {
        .white
    }

    // MARK: - Title Area

    private var titleArea: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.title)
                .font(.headline)
            if let subtitle = entry.subtitle ?? entry.store {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Tags Area

    private var tagsArea: some View {
        HStack(spacing: 4) {
            if let backendTag = recommendedBackendTag {
                tagView(backendTag)
            }
            if let constraintTags = constraintTagLabels {
                ForEach(constraintTags, id: \.self) { tag in
                    tagView(tag)
                }
            }
            if entry.antiCheat != nil {
                antiCheatTag
            }
        }
    }

    private func tagView(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .padding(4)
            .background(.blue.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var recommendedBackendTag: String? {
        guard let variant = entry.defaultVariant else { return nil }
        guard let backend = variant.settings.graphicsBackend else { return nil }
        switch backend {
        case .d3dMetal:
            return "D3DMetal"
        case .dxvk:
            return "DXVK"
        case .wined3d:
            return "WineD3D"
        case .recommended:
            return nil
        }
    }

    private var constraintTagLabels: [String]? {
        var tags: [String] = []

        if let cpuArchs = entry.constraints?.cpuArchitectures,
           cpuArchs.count == 1, cpuArchs.first == "arm64" {
            tags.append(String(localized: "gamedb.tag.appleSilicon"))
        }

        if let minWine = entry.constraints?.minWineVersion {
            tags.append("Wine \(minWine)+")
        }

        return tags.isEmpty ? nil : tags
    }

    private var antiCheatTag: some View {
        Label(entry.antiCheat ?? "", systemImage: "exclamationmark.triangle")
            .font(.caption)
            .padding(4)
            .background(.yellow.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Note Area

    @ViewBuilder
    private var noteArea: some View {
        if let note = entry.notes?.first {
            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: 200, alignment: .trailing)
        }
    }
}
