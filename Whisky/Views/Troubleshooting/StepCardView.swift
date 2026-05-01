//
//  StepCardView.swift
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

/// Renders a single flow step node as a card with evidence and confidence display.
///
/// Handles check, info, branch, and verify node types with appropriate layouts.
/// Evidence from check results is displayed using the node's `evidenceMap`
/// to produce user-facing labels. Confidence badges use the Phase 5
/// ``ConfidenceTier`` color scheme (green/yellow/gray).
struct StepCardView: View {
    let node: FlowStepNode
    let checkResult: CheckResult?
    let isRunning: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader
            cardBody
            if isRunning {
                runningIndicator
            }
            if let checkResult {
                evidenceSection(checkResult)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
    }
}

// MARK: - Header

extension StepCardView {
    private var cardHeader: some View {
        HStack(spacing: 10) {
            nodeTypeIcon
                .frame(width: 28, height: 28)
            if let title = node.title {
                Text(title)
                    .font(.headline)
            }
            Spacer()
            if let checkResult, let confidence = checkResult.confidence {
                confidenceBadge(confidence)
            }
        }
    }

    @ViewBuilder
    private var nodeTypeIcon: some View {
        switch node.type {
        case .check:
            Image(systemName: "magnifyingglass.circle.fill")
                .foregroundStyle(.blue)
                .font(.title3)
        case .info:
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.secondary)
                .font(.title3)
        case .branch:
            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(.purple)
                .font(.title3)
        case .fix:
            Image(systemName: "wrench.and.screwdriver.fill")
                .foregroundStyle(.orange)
                .font(.title3)
        case .verify:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)
        }
    }
}

// MARK: - Body

extension StepCardView {
    @ViewBuilder
    private var cardBody: some View {
        if let description = node.description {
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Running Indicator

extension StepCardView {
    private var runningIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Running check\u{2026}")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Evidence Section

extension StepCardView {
    private func evidenceSection(_ result: CheckResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()

            // Summary line
            HStack(spacing: 6) {
                Image(systemName: outcomeIcon(result.outcome))
                    .foregroundStyle(outcomeColor(result.outcome))
                    .font(.caption)
                Text(result.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Evidence key-value pairs using evidenceMap for labels
            if !result.evidence.isEmpty {
                ForEach(
                    Array(result.evidence.sorted(by: { $0.key < $1.key })),
                    id: \.key
                ) { key, value in
                    HStack(alignment: .top, spacing: 4) {
                        Text(evidenceLabel(for: key) + ":")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                        Text(value)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func evidenceLabel(for key: String) -> String {
        node.evidenceMap?[key] ?? key
    }

    private func outcomeIcon(_ outcome: CheckOutcome) -> String {
        switch outcome {
        case .pass: "checkmark.circle.fill"
        case .fail: "xmark.circle.fill"
        case .alreadyConfigured: "checkmark.seal.fill"
        case .unknown: "questionmark.circle"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    private func outcomeColor(_ outcome: CheckOutcome) -> Color {
        switch outcome {
        case .pass, .alreadyConfigured: .green
        case .fail: .red
        case .unknown: .orange
        case .error: .red
        }
    }
}

// MARK: - Confidence Badge

extension StepCardView {
    private func confidenceBadge(_ tier: ConfidenceTier) -> some View {
        Text(tier.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(badgeColor(tier).opacity(0.15), in: Capsule())
            .foregroundStyle(badgeColor(tier))
    }

    private func badgeColor(_ tier: ConfidenceTier) -> Color {
        switch tier {
        case .high: .green
        case .medium: .yellow
        case .low: .gray
        }
    }
}
