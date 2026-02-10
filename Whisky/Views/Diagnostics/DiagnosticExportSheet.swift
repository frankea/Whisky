//
//  DiagnosticExportSheet.swift
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
import UniformTypeIdentifiers
import WhiskyKit

/// Sheet view for exporting diagnostic reports with privacy controls.
///
/// Presents toggles for sensitive details, remediation history, and full log
/// inclusion. Supports ZIP export via NSSavePanel and Markdown clipboard copy.
struct DiagnosticExportSheet: View {
    let diagnosis: CrashDiagnosis
    let bottle: Bottle
    let program: Program
    let logFileURL: URL?

    @Environment(\.dismiss) var dismiss

    @State private var includeSensitive = false
    @State private var includeRemediationHistory = true
    @State private var includeFullLog = true
    @State private var isExporting = false
    @State private var showCopySuccess = false

    private var exportOptions: ExportOptions {
        ExportOptions(
            includeSensitiveDetails: includeSensitive,
            includeRemediationHistory: includeRemediationHistory,
            includeFullLog: includeFullLog
        )
    }

    private var suggestedFilename: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd-HHmmss"
        let dateString = dateFormatter.string(from: Date())
        let bottleName = sanitizeName(bottle.settings.name)
        let programName = sanitizeName(program.name)
        return "Whisky-Diagnostics-\(bottleName)-\(programName)-\(dateString).zip"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export Diagnostic Report")
                .font(.headline)
            filenamePreview
            Divider()
            privacyOptions
            Divider()
            actionButtons
        }
        .padding(20)
        .frame(minWidth: 480)
    }
}

// MARK: - Subviews

extension DiagnosticExportSheet {
    private var filenamePreview: some View {
        HStack {
            Image(systemName: "doc.zipper")
                .foregroundStyle(.secondary)
            Text(suggestedFilename)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var privacyOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $includeSensitive) {
                VStack(alignment: .leading) {
                    Text("Include sensitive details")
                    Text("Recommended only when sharing privately")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle(isOn: $includeRemediationHistory) {
                Text("Include remediation history")
            }

            Toggle(isOn: $includeFullLog) {
                Text("Include full log file")
            }
        }
    }

    private var actionButtons: some View {
        HStack {
            Button("Cancel", role: .cancel) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            if showCopySuccess {
                Label("Copied!", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                    .transition(.opacity)
            }

            Button("Copy Report to Clipboard") {
                copyMarkdownReport()
            }
            .disabled(isExporting)

            Button("Save ZIP\u{2026}") {
                saveZIPExport()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(isExporting)

            if isExporting {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }
}

// MARK: - Actions

extension DiagnosticExportSheet {
    private func saveZIPExport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = suggestedFilename
        panel.canCreateDirectories = true

        panel.begin { result in
            guard result == .OK, let destination = panel.url else { return }
            isExporting = true
            Task {
                let zipURL = await DiagnosticExporter.exportZIP(
                    diagnosis: diagnosis,
                    bottle: bottle,
                    program: program,
                    logFileURL: logFileURL,
                    timeline: loadRemediationTimeline(),
                    options: exportOptions
                )

                try? moveFile(from: zipURL, to: destination)
                isExporting = false
                dismiss()
            }
        }
    }

    private func copyMarkdownReport() {
        isExporting = true
        Task {
            let markdown = await DiagnosticExporter.generateMarkdownReport(
                diagnosis: diagnosis,
                bottle: bottle,
                program: program,
                options: exportOptions
            )

            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(markdown, forType: .string)

            isExporting = false
            withAnimation {
                showCopySuccess = true
            }
            try? await Task.sleep(for: .seconds(2))
            withAnimation {
                showCopySuccess = false
            }
        }
    }
}

// MARK: - Helpers

extension DiagnosticExportSheet {
    private func moveFile(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: source, to: destination)
    }

    private func loadDiagnosisHistory() -> DiagnosisHistory? {
        let historyURL = bottle.url
            .appending(path: "Program Settings")
            .appending(path: program.name)
            .appendingPathExtension("diagnosis-history.plist")
        let history = DiagnosisHistory.load(from: historyURL)
        return history.isEmpty ? nil : history
    }

    private func loadRemediationTimeline() -> RemediationTimeline? {
        let timelineURL = bottle.url
            .appending(path: "Program Settings")
            .appending(path: program.name)
            .appendingPathExtension("remediation-timeline.plist")
        let timeline = RemediationTimeline.load(from: timelineURL)
        return timeline.isEmpty ? nil : timeline
    }

    private func sanitizeName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics
        return name.unicodeScalars
            .map { allowed.contains($0) ? String($0) : "-" }
            .joined()
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
