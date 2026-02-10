//
//  DiagnosticsView.swift
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

/// Main diagnostics view with summary-first layout of crash diagnosis results.
struct DiagnosticsView: View {
    let diagnosis: CrashDiagnosis?
    let logText: String
    let programName: String
    let bottleName: String
    let timestamp: Date

    var onAction: ((RemediationAction) -> Void)?
    var onAnalyze: (() -> Void)?

    @State private var activeCategoryFilter: CrashCategory?
    @State private var searchText: String = ""
    @State private var logFilterMode: LogFilterMode = .all
    @State private var isLogExpanded: Bool = false
    @State private var isOtherSuggestionsExpanded: Bool = false

    private var resolvedRemediations: [RemediationAction] {
        guard let diagnosis else { return [] }
        let (_, remediations) = PatternLoader.loadDefaults()
        return diagnosis.remediations(from: remediations)
    }

    private var primaryRemediations: [RemediationAction] {
        resolvedRemediations.filter { action in
            guard let diagnosis else { return false }
            let confidence = confidenceTier(for: action, diagnosis: diagnosis)
            return confidence != .low
        }
    }

    private var lowConfidenceRemediations: [RemediationAction] {
        resolvedRemediations.filter { action in
            guard let diagnosis else { return false }
            let confidence = confidenceTier(for: action, diagnosis: diagnosis)
            return confidence == .low
        }
    }

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width >= 700 {
                splitLayout
            } else {
                verticalLayout
            }
        }
    }

    // MARK: - Split Layout (>= 700pt)

    private var splitLayout: some View {
        HSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerSection
                    if let diagnosis, !diagnosis.isEmpty {
                        headlineDiagnosis(diagnosis)
                        categoryCountPills(diagnosis)
                        remediationCardsSection
                    } else {
                        emptyStateView
                    }
                }
                .padding()
            }
            .frame(minWidth: 320, idealWidth: 350, maxWidth: 420)

            LogViewerView(
                logText: logText,
                matches: diagnosis?.matches ?? [],
                filterMode: $logFilterMode,
                activeCategoryFilter: $activeCategoryFilter,
                searchText: $searchText
            )
        }
    }

    // MARK: - Vertical Layout (< 700pt)

    private var verticalLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                if let diagnosis, !diagnosis.isEmpty {
                    headlineDiagnosis(diagnosis)
                    categoryCountPills(diagnosis)
                    remediationCardsSection
                    logDisclosureSection
                } else {
                    emptyStateView
                    logDisclosureSection
                }
            }
            .padding()
        }
    }
}

// MARK: - Header

extension DiagnosticsView {
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(programName)
                    .font(.headline)
                HStack(spacing: 4) {
                    Text(bottleName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\u{2022}")
                        .foregroundStyle(.tertiary)
                    Text(timestamp, style: .relative)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}

// MARK: - Headline Diagnosis

extension DiagnosticsView {
    private func headlineDiagnosis(_ diagnosis: CrashDiagnosis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if let category = diagnosis.primaryCategory {
                    Image(systemName: category.sfSymbol)
                        .font(.title2)
                        .foregroundStyle(colorForCategory(category))
                }

                VStack(alignment: .leading, spacing: 2) {
                    if let headline = diagnosis.headline {
                        Text(headline)
                            .font(.title3)
                            .fontWeight(.semibold)
                    }

                    if let confidence = diagnosis.primaryConfidence {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(colorForConfidence(confidence))
                                .frame(width: 8, height: 8)
                            Text("\(confidence.displayName) confidence")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Expandable "Why this diagnosis" reasoning
            if let primaryCategory = diagnosis.primaryCategory {
                let matchCount = diagnosis.categoryCounts[primaryCategory] ?? 0
                DisclosureGroup("Why this diagnosis") {
                    Text(whyReasoning(diagnosis: diagnosis, matchCount: matchCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.controlBackgroundColor))
        )
    }

    private func whyReasoning(diagnosis: CrashDiagnosis, matchCount: Int) -> String {
        guard let category = diagnosis.primaryCategory,
              let confidence = diagnosis.primaryConfidence
        else {
            return "No strong patterns detected."
        }

        let matchedLines = diagnosis.matches
            .filter { $0.pattern.category == category }
            .prefix(3)
            .map { "Line \($0.lineIndex + 1): \($0.lineText.prefix(80))" }
            .joined(separator: "\n")

        return """
        \(matchCount) pattern(s) matched for \(category.displayName) \
        with \(confidence.displayName.lowercased()) confidence.
        \(matchedLines)
        """
    }
}

// MARK: - Category Count Pills

extension DiagnosticsView {
    private func categoryCountPills(_ diagnosis: CrashDiagnosis) -> some View {
        let sortedCategories = diagnosis.categoryCounts
            .sorted { $0.value > $1.value }

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sortedCategories, id: \.key) { category, count in
                    Button {
                        if activeCategoryFilter == category {
                            activeCategoryFilter = nil
                            logFilterMode = .all
                        } else {
                            activeCategoryFilter = category
                            logFilterMode = .category(category)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: category.sfSymbol)
                                .font(.caption2)
                            Text("\(category.displayName): \(count)")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(
                                    activeCategoryFilter == category
                                        ? colorForCategory(category).opacity(0.2)
                                        : Color(.controlBackgroundColor)
                                )
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    activeCategoryFilter == category
                                        ? colorForCategory(category)
                                        : Color.secondary.opacity(0.3),
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Remediation Cards

extension DiagnosticsView {
    private var remediationCardsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(primaryRemediations) { action in
                RemediationCardView(
                    action: action,
                    confidenceTier: diagnosis.map { confidenceTier(for: action, diagnosis: $0) } ?? .low,
                    onAction: onAction
                )
            }

            if !lowConfidenceRemediations.isEmpty {
                DisclosureGroup(
                    isExpanded: $isOtherSuggestionsExpanded
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(lowConfidenceRemediations) { action in
                            RemediationCardView(
                                action: action,
                                confidenceTier: .low,
                                onAction: onAction
                            )
                        }
                    }
                } label: {
                    Text("Other things to try")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Log Section

extension DiagnosticsView {
    private var logDisclosureSection: some View {
        DisclosureGroup(isExpanded: $isLogExpanded) {
            LogViewerView(
                logText: logText,
                matches: diagnosis?.matches ?? [],
                filterMode: $logFilterMode,
                activeCategoryFilter: $activeCategoryFilter,
                searchText: $searchText
            )
            .frame(minHeight: 300)
        } label: {
            Text("Raw Log Output")
                .font(.subheadline)
        }
    }
}

// MARK: - Empty State

extension DiagnosticsView {
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No diagnosis available")
                .font(.headline)
            Text("Run the program to generate a crash diagnosis, or analyze the latest log.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let onAnalyze {
                Button("Analyze latest log") {
                    onAnalyze()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Helpers

extension DiagnosticsView {
    private func confidenceTier(for action: RemediationAction, diagnosis: CrashDiagnosis) -> ConfidenceTier {
        var bestConfidence: Double = 0
        for match in diagnosis.matches {
            guard let actionIds = match.pattern.remediationActionIds,
                  actionIds.contains(action.id)
            else {
                continue
            }
            bestConfidence = max(bestConfidence, match.pattern.confidence)
        }
        return ConfidenceTier(score: bestConfidence)
    }

    func colorForCategory(_ category: CrashCategory) -> Color {
        switch category {
        case .coreCrashFatal:
            .red
        case .graphics:
            .orange
        case .dependenciesLoading:
            .blue
        case .prefixFilesystem:
            .purple
        case .networkingLaunchers:
            .cyan
        case .antiCheatUnsupported:
            .gray
        case .otherUnknown:
            .secondary
        }
    }

    func colorForConfidence(_ tier: ConfidenceTier) -> Color {
        switch tier {
        case .high:
            .green
        case .medium:
            .yellow
        case .low:
            .gray
        }
    }
}
