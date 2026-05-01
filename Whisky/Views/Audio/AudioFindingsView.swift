//
//  AudioFindingsView.swift
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

/// Findings list with fix cards matching the Phase 5 remediation card pattern.
///
/// Displays audio diagnostic findings with confidence badges, expandable details,
/// and optional fix action buttons.
struct AudioFindingsView: View {
    let findings: [AudioFinding]
    var onApplyFix: ((String) -> Void)?

    @State private var showAllFindings: Bool = false

    private var visibleFindings: [AudioFinding] {
        if showAllFindings || findings.count <= 5 {
            return findings
        }
        return Array(findings.prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Findings")
                .font(.headline)

            ForEach(visibleFindings) { finding in
                findingCard(finding)
            }

            if findings.count > 5, !showAllFindings {
                Button("Show all findings (\(findings.count))") {
                    showAllFindings = true
                }
                .font(.caption)
            }

            technicalDetailsSection
        }
    }

    // MARK: - Finding Card

    private func findingCard(_ finding: AudioFinding) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: confidence badge + description
            HStack {
                confidenceDot(finding.confidence)
                Text(finding.description)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                confidenceBadge(finding.confidence)
            }

            // Expandable details
            DisclosureGroup("Details") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(finding.evidence)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let action = finding.suggestedAction {
                        Text(action)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fontWeight(.medium)
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // Fix button
            if finding.suggestedAction != nil {
                Button("Fix") {
                    onApplyFix?(finding.id)
                }
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Confidence Badge

    private func confidenceDot(_ tier: ConfidenceTier) -> some View {
        Circle()
            .fill(badgeColor(tier))
            .frame(width: 8, height: 8)
    }

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
        case .high:
            .green
        case .medium:
            .yellow
        case .low:
            .gray
        }
    }

    // MARK: - Technical Details

    private var technicalDetailsSection: some View {
        DisclosureGroup("Technical details") {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(findings) { finding in
                    Text("[\(finding.id)] \(finding.evidence)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
