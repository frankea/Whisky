//
//  GameVariantPickerView.swift
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

/// A picker view for selecting between multiple game configuration variants.
///
/// Each variant is displayed as a selectable card with label, description,
/// and optional constraint information. The selected card has a highlighted
/// border following the BackendPickerView selection card pattern.
struct GameVariantPickerView: View {
    let variants: [GameConfigVariant]
    @Binding var selected: GameConfigVariant?

    var body: some View {
        VStack(spacing: 10) {
            ForEach(variants, id: \.id) { variant in
                variantCard(variant, isSelected: selected?.id == variant.id)
            }
        }
    }

    private func variantCard(_ variant: GameConfigVariant, isSelected: Bool) -> some View {
        Button {
            selected = variant
        } label: {
            variantCardContent(variant, isSelected: isSelected)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? Color.accentColor : Color(.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color.secondary.opacity(0.3),
                            lineWidth: isSelected ? 2 : 1
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private func variantCardContent(
        _ variant: GameConfigVariant,
        isSelected: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(variant.label)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(isSelected ? .white : .primary)
                Spacer()
                if variant.isDefault == true {
                    defaultBadge(isSelected: isSelected)
                }
            }

            if let whenToUse = variant.whenToUse {
                Text(whenToUse)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                    .lineLimit(2)
            }

            if let constraints = constraintSummary(variant) {
                Text(constraints)
                    .font(.caption2)
                    .foregroundStyle(
                        isSelected ? Color.white.opacity(0.7) : Color.secondary.opacity(0.6)
                    )
            }
        }
    }

    private func defaultBadge(isSelected: Bool) -> some View {
        Text("gameConfig.variant.default")
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                isSelected ? Color.white.opacity(0.3) : Color.green.opacity(0.15),
                in: Capsule()
            )
            .foregroundStyle(isSelected ? .white : .green)
    }

    /// Builds a short constraint summary for the variant card caption.
    private func constraintSummary(_ variant: GameConfigVariant) -> String? {
        var parts: [String] = []

        if let backend = variant.settings.graphicsBackend {
            parts.append(backend.displayName)
        }

        if let sync = variant.settings.enhancedSync {
            let syncName = switch sync {
            case .none: "No Sync"
            case .esync: "ESync"
            case .msync: "MSync"
            }
            parts.append(syncName)
        }

        return parts.isEmpty ? nil : parts.joined(separator: " \u{2022} ")
    }
}
