//
//  SymptomPickerView.swift
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

/// Grid of 8 symptom categories with SF Symbols and descriptions.
///
/// Uses an adaptive 2-column grid for wider views. The "Other" category
/// is shown at the bottom with reduced visual weight per locked decision.
struct SymptomPickerView: View {
    @ObservedObject var engine: TroubleshootingFlowEngine

    /// Primary categories exclude "other" for separate rendering.
    private var primaryCategories: [SymptomCategory] {
        SymptomCategory.allCases.filter { $0 != .other }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What problem are you experiencing?")
                .font(.title3)
                .fontWeight(.medium)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 12)],
                spacing: 12
            ) {
                ForEach(primaryCategories, id: \.self) { category in
                    categoryCard(category, isOther: false)
                }
            }

            // "Other" option with reduced visual weight
            categoryCard(.other, isOther: true)
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Category Card

extension SymptomPickerView {
    private func categoryCard(_ category: SymptomCategory, isOther: Bool) -> some View {
        Button {
            engine.selectCategory(category)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: category.sfSymbol)
                    .font(.title2)
                    .foregroundStyle(isOther ? .tertiary : .secondary)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.displayTitle)
                        .font(.headline)
                        .foregroundStyle(isOther ? .secondary : .primary)
                    Text(categoryDescription(category))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        Color.secondary.opacity(isOther ? 0.1 : 0.2),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func categoryDescription(_ category: SymptomCategory) -> String {
        switch category {
        case .launchCrash:
            "Program fails to start or crashes within seconds"
        case .launcherIssues:
            "Steam, EA App, Epic Games, or Rockstar launcher problems"
        case .graphics:
            "Black screen, flickering, visual artifacts, or low frame rate"
        case .audio:
            "No sound, crackling, popping, or wrong output device"
        case .controllerInput:
            "Controller not detected or buttons mapped incorrectly"
        case .installDependencies:
            "Missing .NET, VC++, DirectX, or Winetricks components"
        case .networkDownload:
            "Download timeouts, Steam stalls, or connection failures"
        case .performanceStability:
            "Stuttering, frame drops, or hangs after playing for a while"
        case .other:
            "Describe your issue and we will try to help"
        }
    }
}
