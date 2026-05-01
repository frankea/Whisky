//
//  RemediationCardView.swift
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

/// A card component displaying a single remediation action with confidence tier,
/// description, and guardrailed action buttons.
struct RemediationCardView: View {
    let action: RemediationAction
    let confidenceTier: ConfidenceTier
    var onAction: ((RemediationAction) -> Void)?

    @State private var showConfirmation: Bool = false
    @State private var showWhyDetails: Bool = false

    var body: some View {
        if action.category == .antiCheatUnsupported {
            antiCheatCard
        } else {
            standardCard
        }
    }
}

// MARK: - Standard Card

extension RemediationCardView {
    private var standardCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: title + confidence badge
            HStack {
                Text(action.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                confidenceBadge
            }

            // Body: what will change
            Text(action.whatWillChange)
                .font(.caption)
                .foregroundStyle(.secondary)

            // Footer: action button + undo path + applies next launch
            HStack {
                actionButton
                Spacer()
                footerInfo
            }

            // Expandable "Why" reasoning
            whySection
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .alert(
            "Confirm Action",
            isPresented: $showConfirmation
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Apply") {
                onAction?(action)
            }
        } message: {
            Text(confirmationMessage)
        }
    }
}

// MARK: - Anti-Cheat Card

extension RemediationCardView {
    private var antiCheatCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "shield.slash")
                    .foregroundStyle(.secondary)
                Text(action.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text("Not supported")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.gray.opacity(0.15), in: Capsule())
                    .foregroundStyle(.secondary)
            }

            Text("Not supported on macOS")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(action.description)
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Label("Try running the game in offline mode if available", systemImage: "wifi.slash")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Label("Check compatibility notes for this title", systemImage: "doc.text.magnifyingglass")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Confidence Badge

extension RemediationCardView {
    private var confidenceBadge: some View {
        Text(confidenceTier.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(badgeColor.opacity(0.15), in: Capsule())
            .foregroundStyle(badgeColor)
    }

    private var badgeColor: Color {
        switch confidenceTier {
        case .high:
            .green
        case .medium:
            .yellow
        case .low:
            .gray
        }
    }
}

// MARK: - Action Button

extension RemediationCardView {
    @ViewBuilder
    private var actionButton: some View {
        switch action.actionType {
        case .changeSetting:
            if action.risk == .low {
                Button("Apply") {
                    onAction?(action)
                }
                .controlSize(.small)
            } else {
                Button("Apply\u{2026}") {
                    showConfirmation = true
                }
                .controlSize(.small)
            }

        case .installVerb:
            Button("Install\u{2026}") {
                showConfirmation = true
            }
            .controlSize(.small)

        case .switchBackend:
            let backendName = action.settingValue ?? "backend"
            Button("Switch to \(backendName)\u{2026}") {
                showConfirmation = true
            }
            .controlSize(.small)

        case .informational:
            EmptyView()
        }
    }

    private var confirmationMessage: String {
        switch action.actionType {
        case .changeSetting:
            "This will change: \(action.whatWillChange)\n\nUndo: \(action.undoPath)"
        case .installVerb:
            """
            This will install \(action.winetricksVerb ?? "component") via Winetricks.\
            \n\n\(action.whatWillChange)\n\nUndo: \(action.undoPath)
            """
        case .switchBackend:
            "This will switch your graphics backend.\n\n\(action.whatWillChange)\n\nUndo: \(action.undoPath)"
        case .informational:
            ""
        }
    }
}

// MARK: - Footer Info

extension RemediationCardView {
    private var footerInfo: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if action.appliesNextLaunch {
                Label("Applies next launch", systemImage: "arrow.clockwise")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text("Undo: \(action.undoPath)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Why Section

extension RemediationCardView {
    private var whySection: some View {
        DisclosureGroup("Why", isExpanded: $showWhyDetails) {
            Text(action.description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
