//
//  DiagnosticsPickerSheet.swift
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

// MARK: - Crash Diagnosis Banner State

struct CrashDiagnosisBannerState {
    let diagnosis: CrashDiagnosis
    let programName: String
    let logFileURL: URL
}

// MARK: - Diagnostics Picker Sheet

/// Sheet that lets the user select a bottle and program, then opens DiagnosticsView.
struct DiagnosticsPickerSheet: View {
    @EnvironmentObject var bottleVM: BottleVM
    @Environment(\.dismiss) var dismiss

    @State private var selectedBottle: Bottle?
    @State private var selectedProgram: Program?
    @State private var isAnalyzing = false
    @State private var showDiagnosticsResult = false
    @State private var resultDiagnosis: CrashDiagnosis?
    @State private var resultLogText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Run Diagnostics")
                .font(.headline)

            Picker("Bottle", selection: $selectedBottle) {
                Text("Select a bottle").tag(nil as Bottle?)
                ForEach(bottleVM.bottles) { bottle in
                    Text(bottle.settings.name).tag(bottle as Bottle?)
                }
            }

            if let bottle = selectedBottle {
                Picker("Program", selection: $selectedProgram) {
                    Text("Select a program").tag(nil as Program?)
                    ForEach(bottle.programs) { program in
                        Text(program.name).tag(program as Program?)
                    }
                }
            }

            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Analyze") {
                    runAnalysis()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedProgram == nil || isAnalyzing)

                if isAnalyzing {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 400)
        .onChange(of: selectedBottle) { _, _ in
            selectedProgram = nil
        }
        .sheet(isPresented: $showDiagnosticsResult) {
            if let diagnosis = resultDiagnosis, let program = selectedProgram {
                DiagnosticsView(
                    diagnosis: diagnosis,
                    logText: resultLogText,
                    programName: program.name,
                    bottleName: selectedBottle?.settings.name ?? "",
                    timestamp: Date()
                )
                .frame(minWidth: 600, minHeight: 400)
            }
        }
    }

    private func runAnalysis() {
        guard let program = selectedProgram,
              let logURL = program.settings.lastLogFileURL
        else { return }

        isAnalyzing = true
        Task {
            guard let diagnosis = await Wine.classifyLastRun(logFileURL: logURL, exitCode: 1) else {
                isAnalyzing = false
                return
            }
            resultDiagnosis = diagnosis
            resultLogText = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
            isAnalyzing = false
            showDiagnosticsResult = true
        }
    }
}
