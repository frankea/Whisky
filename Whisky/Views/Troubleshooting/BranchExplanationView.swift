//
//  BranchExplanationView.swift
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

/// Inline explanation bar shown when the flow branches and changes future steps.
///
/// Per locked "Why path changed" decision. Displays a subtle info bar with
/// the branch reason. Dismissable by the user, which sets
/// ``TroubleshootingFlowEngine/pathChanged`` to `false`.
struct BranchExplanationView: View {
    let reason: String?
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.blue)
                .font(.caption)

            Text(displayText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(.tertiary)
                    .font(.caption2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.secondarySystemFill))
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private var displayText: String {
        if let reason {
            "Path updated: \(reason)"
        } else {
            "The troubleshooting path has been updated based on the check results."
        }
    }
}
