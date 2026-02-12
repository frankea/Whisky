//
//  TroubleshootingTargetPicker.swift
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

/// Bottle and program picker sheet for the Help menu troubleshooting entry point.
///
/// Follows the ``DiagnosticsPickerSheet`` pattern. Lets the user select a bottle
/// and optionally a program, then triggers the callback to open the wizard.
struct TroubleshootingTargetPicker: View {
    let bottles: [Bottle]
    let onSelect: (Bottle, Program?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedBottle: Bottle?
    @State private var selectedProgram: Program?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "troubleshooting.wizard.title"))
                .font(.headline)

            Text("Select a bottle and optionally a program to troubleshoot.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("Bottle", selection: $selectedBottle) {
                Text("Select a bottle").tag(nil as Bottle?)
                ForEach(bottles) { bottle in
                    Text(bottle.settings.name).tag(bottle as Bottle?)
                }
            }

            if let bottle = selectedBottle {
                Picker("Program", selection: $selectedProgram) {
                    Text("No specific program (bottle-level)").tag(nil as Program?)
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

                Button(String(localized: "troubleshooting.entry.startGuided")) {
                    guard let bottle = selectedBottle else { return }
                    onSelect(bottle, selectedProgram)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedBottle == nil)
            }
        }
        .padding(20)
        .frame(minWidth: 400)
        .onChange(of: selectedBottle) { _, _ in
            selectedProgram = nil
        }
    }
}
