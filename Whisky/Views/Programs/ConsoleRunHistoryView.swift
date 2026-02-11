//
//  ConsoleRunHistoryView.swift
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

/// Displays the run history for a program with last run, previous runs, and management actions.
///
/// Each entry shows start time, duration, exit code, and running status. Users can select
/// a run to view its console output in ``ConsoleLogView``, delete individual entries,
/// or clean up old logs.
struct ConsoleRunHistoryView: View {
    let program: Program
    let bottle: Bottle
    @Binding var selectedRunId: UUID?

    @State private var history = RunLogHistory()
    @State private var refreshTimer: Timer?

    var body: some View {
        Group {
            if history.entries.isEmpty {
                emptyStateView
            } else {
                runHistoryContent
            }
        }
        .onAppear { loadHistory() }
        .onDisappear { stopRefreshTimer() }
        .task { startRefreshTimer() }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("console.noRuns")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("console.noRuns.detail")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: - Run History Content

    private var runHistoryContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let lastRun = history.entries.last {
                lastRunSection(lastRun)
            }

            if history.entries.count > 1 {
                previousRunsSection
            }

            actionsToolbar
        }
    }

    // MARK: - Last Run

    private func lastRunSection(_ entry: RunLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("console.lastRun")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

            Button {
                selectedRunId = entry.id
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.programName)
                            .font(.headline)
                        Text(entry.startTime, style: .date)
                            + Text(" ")
                            + Text(entry.startTime, style: .time)
                    }

                    Spacer()

                    if entry.isRunning {
                        runningBadge
                    } else {
                        exitCodeBadge(entry.exitCode)
                    }

                    if let duration = entry.duration {
                        durationLabel(duration)
                    }

                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(selectedRunId == entry.id
                              ? Color.accentColor.opacity(0.15)
                              : Color.clear)
                )
            }
            .buttonStyle(.plain)

            if !entry.isRunning, let exitCode = entry.exitCode {
                exitedFooter(exitCode: exitCode)
                    .padding(.horizontal, 8)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Previous Runs

    private var previousRunsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("console.previousRuns")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 8)

            ForEach(previousEntries) { entry in
                Button {
                    selectedRunId = entry.id
                } label: {
                    HStack {
                        Text(entry.startTime, style: .date)
                            + Text(" ")
                            + Text(entry.startTime, style: .time)

                        Spacer()

                        if entry.isRunning {
                            runningBadge
                        } else {
                            exitCodeBadge(entry.exitCode)
                        }

                        if let duration = entry.duration {
                            durationLabel(duration)
                        }

                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(selectedRunId == entry.id
                                  ? Color.accentColor.opacity(0.15)
                                  : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("console.deleteRun", role: .destructive) {
                        deleteEntry(entry)
                    }
                }
            }
        }
    }

    /// Previous entries in reverse chronological order (excluding the last/most recent entry).
    private var previousEntries: [RunLogEntry] {
        guard history.entries.count > 1 else { return [] }
        return Array(history.entries.dropLast().reversed())
    }

    // MARK: - Actions Toolbar

    private var actionsToolbar: some View {
        HStack(spacing: 12) {
            Button {
                selectedRunId = nil
            } label: {
                Label("console.clearConsole", systemImage: "xmark.circle")
            }
            .buttonStyle(.plain)
            .font(.caption)

            Button {
                deleteOldLogs()
            } label: {
                Label("console.deleteOldLogs", systemImage: "trash")
            }
            .buttonStyle(.plain)
            .font(.caption)

            Button {
                NSWorkspace.shared.open(Wine.logsFolder)
            } label: {
                Label("console.openLogsFolder", systemImage: "folder")
            }
            .buttonStyle(.plain)
            .font(.caption)

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    // MARK: - Shared Badge Views

    private var runningBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(.green)
                .frame(width: 6, height: 6)
                .modifier(PulseAnimationModifier())
            Text("console.running")
                .font(.caption)
                .foregroundStyle(.green)
        }
    }

    private func exitCodeBadge(_ exitCode: Int32?) -> some View {
        Group {
            if let code = exitCode {
                Text("console.exitCode \(code)")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(code == 0 ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                    )
                    .foregroundStyle(code == 0 ? .green : .red)
            }
        }
    }

    private func durationLabel(_ duration: TimeInterval) -> some View {
        Text(formattedDuration(duration))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func exitedFooter(exitCode: Int32) -> some View {
        Text("console.exited \(exitCode)")
            .font(.caption2)
            .foregroundStyle(exitCode == 0 ? .green : .red)
    }

    // MARK: - Duration Formatting

    private func formattedDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }

    // MARK: - Data Operations

    private func loadHistory() {
        history = RunLogStore.load(for: program.name, in: bottle.url)
    }

    private func deleteEntry(_ entry: RunLogEntry) {
        if let removed = history.deleteEntry(id: entry.id) {
            let logURL = Wine.logsFolder.appending(path: removed.logFileName)
            try? FileManager.default.removeItem(at: logURL)
            RunLogStore.save(history, for: program.name, in: bottle.url)
        }
        if selectedRunId == entry.id {
            selectedRunId = nil
        }
    }

    private func deleteOldLogs() {
        let removed = history.deleteOldEntries(keepLast: 1)
        for entry in removed {
            let logURL = Wine.logsFolder.appending(path: entry.logFileName)
            try? FileManager.default.removeItem(at: logURL)
        }
        RunLogStore.save(history, for: program.name, in: bottle.url)
    }

    // MARK: - Refresh Timer

    private func startRefreshTimer() {
        stopRefreshTimer()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                loadHistory()
            }
        }
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}

// MARK: - Pulse Animation Modifier

/// A simple pulse animation modifier for the "Running" indicator dot.
private struct PulseAnimationModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.4 : 1.0)
            .animation(
                .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}
