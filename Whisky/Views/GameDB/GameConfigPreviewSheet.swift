//
//  GameConfigPreviewSheet.swift
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

/// A sheet that shows a before/after diff of what settings will change when
/// applying a game configuration variant, with winetricks preflight and apply action.
struct GameConfigPreviewSheet: View {
    let entry: GameDBEntry
    let variant: GameConfigVariant
    @ObservedObject var bottle: Bottle
    let programURL: URL?
    @Environment(\.dismiss) private var dismiss
    @State private var changes: [ConfigChange] = []
    @State private var missingVerbs: [String] = []
    @State private var installedVerbs: Set<String> = []
    @State private var isApplying: Bool = false
    @State private var applyError: String?
    @State private var stalenessResult: StalenessResult?
    @State private var includeWinetricks: Bool = true
    @AppStorage("gameConfigSkipPreview") private var skipPreview: Bool = false
    @Binding var toast: ToastData?

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    stalenessWarning
                    applyTargetSection
                    changesSection
                    winetricksSection
                    restartNote
                    errorBanner
                }
                .padding()
            }
            sheetFooter
        }
        .frame(minWidth: 480, idealWidth: 520, minHeight: 400, idealHeight: 600)
        .task {
            await loadPreviewData()
        }
    }
}

// MARK: - Header

extension GameConfigPreviewSheet {
    private var sheetHeader: some View {
        VStack(spacing: 4) {
            Text("gameConfig.preview.title")
                .font(.headline)
            Text(entry.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}

// MARK: - Staleness Warning

extension GameConfigPreviewSheet {
    @ViewBuilder
    private var stalenessWarning: some View {
        if let result = stalenessResult, result.isStale, let message = result.warningMessage {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 2) {
                    Text("gameConfig.preview.staleConfig")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(10)
            .background(.yellow.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Apply Target

extension GameConfigPreviewSheet {
    private var applyTargetSection: some View {
        HStack {
            Text("gameConfig.preview.applyTo")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(bottle.settings.name)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Changes Section

extension GameConfigPreviewSheet {
    @ViewBuilder
    private var changesSection: some View {
        if changes.isEmpty {
            Text("gameConfig.preview.noChanges")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            changesGroupedByCategory
        }
    }

    private var changesGroupedByCategory: some View {
        let grouped = Dictionary(grouping: changes, by: \.category)
        let sortedKeys = grouped.keys.sorted()

        return VStack(alignment: .leading, spacing: 12) {
            ForEach(sortedKeys, id: \.self) { category in
                if let categoryChanges = grouped[category] {
                    changeCategorySection(category, changes: categoryChanges)
                }
            }
        }
    }

    private func changeCategorySection(
        _ category: String,
        changes: [ConfigChange]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(category)
                .font(.subheadline)
                .fontWeight(.semibold)

            ForEach(Array(changes.enumerated()), id: \.offset) { _, change in
                changeRow(change)
            }
        }
    }

    private func changeRow(_ change: ConfigChange) -> some View {
        HStack(spacing: 8) {
            if change.isHighImpact {
                Image(systemName: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            Text(change.settingName)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(change.currentValue)
                .font(.caption)
                .strikethrough()
                .foregroundStyle(.red.opacity(0.8))
            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(change.newValue)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.green)
        }
    }
}

// MARK: - Winetricks Section

extension GameConfigPreviewSheet {
    @ViewBuilder
    private var winetricksSection: some View {
        if let verbs = variant.winetricksVerbs, !verbs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("gameConfig.preview.winetricksRequired")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                ForEach(verbs, id: \.self) { verb in
                    verbRow(verb)
                }

                Toggle("gameConfig.preview.installComponents", isOn: $includeWinetricks)
                    .font(.caption)

                if !includeWinetricks {
                    Text("gameConfig.preview.incomplete")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                Text("gameConfig.preview.winetricksNote")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.controlBackgroundColor))
            )
        }
    }

    private func verbRow(_ verb: String) -> some View {
        HStack(spacing: 6) {
            if installedVerbs.contains(verb) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            } else {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
            Text(verb)
                .font(.caption)
            Spacer()
            Text(
                installedVerbs.contains(verb)
                    ? String(localized: "gameConfig.preview.winetricksInstalled")
                    : String(localized: "gameConfig.preview.winetricksMissing")
            )
            .font(.caption2)
            .foregroundStyle(installedVerbs.contains(verb) ? .green : .orange)
        }
    }
}

// MARK: - Restart Note

extension GameConfigPreviewSheet {
    @ViewBuilder
    private var restartNote: some View {
        let hasBackendChange = changes.contains { $0.category == "Graphics" && $0.settingName == "Graphics Backend" }
        if hasBackendChange {
            HStack(spacing: 6) {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(.blue)
                Text("gameConfig.preview.restartNote")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Error Banner

extension GameConfigPreviewSheet {
    @ViewBuilder
    private var errorBanner: some View {
        if let error = applyError {
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            .padding(8)
            .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Footer

extension GameConfigPreviewSheet {
    private var sheetFooter: some View {
        HStack {
            Toggle("gameConfig.preview.dontShowAgain", isOn: $skipPreview)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("gameConfig.preview.cancel", role: .cancel) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("gamedb.preview.cancelButton")

            Button("gameConfig.preview.applyButton") {
                Task {
                    await applyConfiguration()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isApplying)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("gamedb.preview.applyButton")
        }
        .padding()
        .background(.bar)
    }
}

// MARK: - Data Loading

extension GameConfigPreviewSheet {
    private func loadPreviewData() async {
        // Load preview changes
        changes = GameConfigApplicator.previewChanges(variant: variant, bottle: bottle)

        // Load installed verbs
        let result = await Winetricks.loadInstalledVerbs(for: bottle)
        installedVerbs = result.verbs
        missingVerbs = GameConfigApplicator.pendingWinetricksVerbs(
            variant: variant,
            installedVerbs: result.verbs
        )

        // Check staleness
        if let testedWith = variant.testedWith {
            stalenessResult = StalenessChecker.check(testedWith: testedWith)
        }
    }
}

// MARK: - Apply Action

extension GameConfigPreviewSheet {
    private func applyConfiguration() async {
        isApplying = true
        applyError = nil

        do {
            let snapshot = try GameConfigApplicator.apply(
                entry: entry,
                variant: variant,
                to: bottle,
                programURL: programURL
            )

            dismiss()

            toast = ToastData(
                message: String(localized: "gameConfig.apply.success \(entry.title)"),
                style: .success
            )

            // Schedule undo availability check -- snapshot is saved to bottle
            _ = snapshot // Snapshot saved to bottle directory for future revert
        } catch {
            applyError = String(localized: "gameConfig.apply.failed \(error.localizedDescription)")
            isApplying = false
        }
    }
}
