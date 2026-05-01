//
//  DiagnosisHistoryView.swift
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

/// View showing per-program crash diagnosis history with view/re-analyze/clear actions
/// and an enhanced logging section with WINEDEBUG preset picker.
struct DiagnosisHistoryView: View {
    @ObservedObject var bottle: Bottle
    @ObservedObject var program: Program

    var onViewDetails: ((DiagnosisHistoryEntry) -> Void)?
    var onReanalyze: ((DiagnosisHistoryEntry) -> Void)?
    var onAnalyzeLastRun: (() -> Void)?
    var onRerunWithPreset: ((WineDebugPreset) -> Void)?

    @State private var history = DiagnosisHistory()
    @State private var showClearConfirmation = false
    @State private var selectedPreset: WineDebugPreset = .normal

    private var historyURL: URL {
        bottle.url
            .appending(path: "Program Settings")
            .appending(path: program.name)
            .appendingPathExtension("diagnosis-history.plist")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            historySection
            enhancedLoggingSection
        }
        .onAppear {
            loadHistory()
            selectedPreset = program.settings.activeWineDebugPreset ?? .normal
        }
    }
}

// MARK: - History Section

extension DiagnosisHistoryView {
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Crash Diagnosis History")
                .font(.headline)

            if history.isEmpty {
                emptyHistoryView
            } else {
                historyEntryList
                clearButton
            }
        }
    }

    private var emptyHistoryView: some View {
        VStack(spacing: 8) {
            Text("No crash diagnoses recorded")
                .foregroundStyle(.secondary)
                .font(.callout)

            if let onAnalyzeLastRun {
                Button("Analyze last run") {
                    onAnalyzeLastRun()
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var historyEntryList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(history.entries.reversed().enumerated()), id: \.offset) { _, entry in
                historyEntryRow(entry)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(.controlBackgroundColor))
                    )
            }
        }
    }
}

// MARK: - Entry Row

extension DiagnosisHistoryView {
    private func historyEntryRow(_ entry: DiagnosisHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: entry.primaryCategory.sfSymbol)
                    .foregroundStyle(colorForCategory(entry.primaryCategory))
                    .font(.body)
                Text(entry.primaryCategory.displayName)
                    .font(.body)
                    .fontWeight(.medium)
                Spacer()
                confidenceBadge(entry.confidenceTier)
            }

            Text(entry.timestamp, style: .relative)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !entry.topSignatures.isEmpty {
                Text(entry.topSignatures.prefix(2).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            HStack(spacing: 8) {
                if let onViewDetails {
                    Button("View Details") {
                        onViewDetails(entry)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if let onReanalyze {
                    Button("Re-analyze") {
                        onReanalyze(entry)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private func confidenceBadge(_ tier: ConfidenceTier) -> some View {
        Text(tier.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(colorForConfidence(tier).opacity(0.15))
            )
            .foregroundStyle(colorForConfidence(tier))
    }

    private var clearButton: some View {
        Button("Clear diagnostics history", role: .destructive) {
            showClearConfirmation = true
        }
        .font(.caption)
        .alert("Clear diagnostics history?", isPresented: $showClearConfirmation) {
            Button("Clear", role: .destructive) {
                clearHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all crash diagnosis records for this program.")
        }
    }
}

// MARK: - Enhanced Logging Section

extension DiagnosisHistoryView {
    private var enhancedLoggingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Enhanced Logging")
                .font(.headline)

            Picker("WINEDEBUG Preset", selection: $selectedPreset) {
                ForEach(WineDebugPreset.allCases, id: \.self) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
            .onChange(of: selectedPreset) { _, newValue in
                program.settings.activeWineDebugPreset = newValue == .normal ? nil : newValue
            }

            Text(selectedPreset.presetDescription)
                .font(.caption)
                .foregroundStyle(.secondary)

            if selectedPreset == .verbose {
                Label("Generates large logs", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if selectedPreset != .normal, let onRerunWithPreset {
                Button("Re-run with enhanced logging") {
                    onRerunWithPreset(selectedPreset)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - Helpers

extension DiagnosisHistoryView {
    private func loadHistory() {
        history = DiagnosisHistory.load(from: historyURL)
    }

    private func clearHistory() {
        var mutableHistory = history
        mutableHistory.clear()
        try? mutableHistory.save(to: historyURL)
        history = mutableHistory
    }

    private func colorForCategory(_ category: CrashCategory) -> Color {
        switch category {
        case .coreCrashFatal: .red
        case .graphics: .orange
        case .dependenciesLoading: .blue
        case .prefixFilesystem: .purple
        case .networkingLaunchers: .cyan
        case .antiCheatUnsupported: .gray
        case .otherUnknown: .secondary
        }
    }

    private func colorForConfidence(_ tier: ConfidenceTier) -> Color {
        switch tier {
        case .high: .green
        case .medium: .yellow
        case .low: .gray
        }
    }
}
