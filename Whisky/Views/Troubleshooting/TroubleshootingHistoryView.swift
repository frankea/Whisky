//
//  TroubleshootingHistoryView.swift
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

/// Per-bottle or per-program troubleshooting history list.
///
/// Shows completed troubleshooting sessions with outcome badges, relative timestamps,
/// and primary findings. Each row expands to show fix details and offers a
/// "Reopen as template" action to start a new session with the same symptom category.
struct TroubleshootingHistoryView: View {
    let bottleURL: URL
    let programURL: URL?

    @State private var history: TroubleshootingHistory = .init()
    @State private var expandedEntryId: UUID?
    @State private var templateEntry: TroubleshootingHistoryEntry?

    var body: some View {
        Group {
            if filteredEntries.isEmpty {
                ContentUnavailableView(
                    String(localized: "troubleshooting.history.empty"),
                    systemImage: "clock.arrow.circlepath"
                )
            } else {
                ForEach(filteredEntries) { entry in
                    entryRow(entry)
                }
            }
        }
        .onAppear {
            history = TroubleshootingHistory.load(from: bottleURL)
        }
    }

    private var filteredEntries: [TroubleshootingHistoryEntry] {
        let recent = history.recentEntries
        if let programURL {
            let programName = programURL.deletingPathExtension().lastPathComponent
            return recent.filter { $0.programName == programName }
        }
        return recent
    }
}

// MARK: - Entry Row

extension TroubleshootingHistoryView {
    private func entryRow(_ entry: TroubleshootingHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedEntryId = expandedEntryId == entry.id ? nil : entry.id
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: entry.symptomCategory.sfSymbol)
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.symptomCategory.displayTitle)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                        if let finding = entry.primaryFindings.first {
                            Text(finding)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                    outcomeBadge(entry.outcome)
                    Text(entry.completedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(minWidth: 60, alignment: .trailing)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expandedEntryId == entry.id {
                expandedContent(entry)
            }
        }
    }
}

// MARK: - Outcome Badge

extension TroubleshootingHistoryView {
    private func outcomeBadge(_ outcome: TroubleshootingSession.SessionOutcome) -> some View {
        Text(outcomeLabel(outcome))
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(outcomeColor(outcome).opacity(0.15))
            )
            .foregroundStyle(outcomeColor(outcome))
    }

    private func outcomeLabel(_ outcome: TroubleshootingSession.SessionOutcome) -> String {
        switch outcome {
        case .resolved: String(localized: "troubleshooting.history.resolved")
        case .unresolved: String(localized: "troubleshooting.history.unresolved")
        case .abandoned: String(localized: "troubleshooting.history.abandoned")
        }
    }

    private func outcomeColor(_ outcome: TroubleshootingSession.SessionOutcome) -> Color {
        switch outcome {
        case .resolved: .green
        case .unresolved: .orange
        case .abandoned: .gray
        }
    }
}

// MARK: - Expanded Content

extension TroubleshootingHistoryView {
    private func expandedContent(_ entry: TroubleshootingHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !entry.fixResults.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Fixes attempted:")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    ForEach(entry.fixResults, id: \.self) { result in
                        HStack(spacing: 4) {
                            Image(systemName: "wrench.and.screwdriver")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(result)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Button {
                    templateEntry = entry
                } label: {
                    Label(
                        String(localized: "troubleshooting.history.reopenTemplate"),
                        systemImage: "doc.on.doc"
                    )
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    exportSessionReport(entry)
                } label: {
                    Label(
                        String(localized: "troubleshooting.history.exportReport"),
                        systemImage: "square.and.arrow.up"
                    )
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.leading, 28)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func exportSessionReport(_ entry: TroubleshootingHistoryEntry) {
        var lines: [String] = [
            "=== Troubleshooting Session Report ===",
            "Date: \(entry.completedAt.formatted())",
            "Category: \(entry.symptomCategory.displayTitle)",
            "Outcome: \(entry.outcome.rawValue)",
            "Bottle: \(entry.bottleName)"
        ]

        if let programName = entry.programName {
            lines.append("Program: \(programName)")
        }

        if !entry.primaryFindings.isEmpty {
            lines.append("\n--- Findings ---")
            for finding in entry.primaryFindings {
                lines.append("- \(finding)")
            }
        }

        if !entry.fixResults.isEmpty {
            lines.append("\n--- Fixes ---")
            for result in entry.fixResults {
                lines.append("- \(result)")
            }
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }
}
