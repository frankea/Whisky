//
//  ProgressRailView.swift
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

/// Vertical progress rail showing 5 stable wizard phases with state-based styling.
///
/// Displays: Symptom, Checks, Fix, Verify, Export as fixed phase items
/// with connector lines between them. The active phase is highlighted,
/// completed phases show green checkmarks, and upcoming phases are dimmed.
struct ProgressRailView: View {
    let session: TroubleshootingSession

    private let railPhases: [RailPhase] = [
        RailPhase(
            phase: .symptom,
            title: "Symptom",
            sfSymbol: "questionmark.circle"
        ),
        RailPhase(
            phase: .checks,
            title: "Checks",
            sfSymbol: "magnifyingglass.circle"
        ),
        RailPhase(
            phase: .fix,
            title: "Fix",
            sfSymbol: "wrench.and.screwdriver"
        ),
        RailPhase(
            phase: .verify,
            title: "Verify",
            sfSymbol: "checkmark.circle"
        ),
        RailPhase(
            phase: .export,
            title: "Export",
            sfSymbol: "square.and.arrow.up.circle"
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(railPhases.enumerated()), id: \.element.phase) { index, railPhase in
                phaseRow(railPhase)
                if index < railPhases.count - 1 {
                    connectorLine(after: railPhase)
                }
            }
            Spacer()
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
    }
}

// MARK: - Phase Row

extension ProgressRailView {
    private func phaseRow(_ railPhase: RailPhase) -> some View {
        let state = phaseState(for: railPhase.phase)

        return HStack(spacing: 10) {
            phaseIcon(railPhase: railPhase, state: state)
                .frame(width: 24, height: 24)
            Text(railPhase.title)
                .font(.subheadline)
                .fontWeight(state == .active ? .semibold : .regular)
                .foregroundStyle(textColor(for: state))
                .strikethrough(state == .superseded, color: .secondary.opacity(0.5))
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func phaseIcon(railPhase: RailPhase, state: PhaseState) -> some View {
        switch state {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.body)
        case .active:
            Image(systemName: railPhase.sfSymbol + ".fill")
                .foregroundStyle(.tint)
                .font(.body)
        case .upcoming:
            Image(systemName: railPhase.sfSymbol)
                .foregroundStyle(.secondary)
                .font(.body)
        case .superseded:
            Image(systemName: railPhase.sfSymbol)
                .foregroundStyle(.secondary.opacity(0.4))
                .font(.body)
        }
    }

    private func textColor(for state: PhaseState) -> Color {
        switch state {
        case .completed: .primary
        case .active: .accentColor
        case .upcoming: .secondary
        case .superseded: .secondary.opacity(0.4)
        }
    }
}

// MARK: - Connector Line

extension ProgressRailView {
    private func connectorLine(after railPhase: RailPhase) -> some View {
        let state = phaseState(for: railPhase.phase)
        return Rectangle()
            .fill(state == .completed ? Color.green.opacity(0.6) : Color.secondary.opacity(0.2))
            .frame(width: 2, height: 20)
            .padding(.leading, 11)
    }
}

// MARK: - Phase State

extension ProgressRailView {
    private enum PhaseState {
        case completed
        case active
        case upcoming
        case superseded
    }

    private func phaseState(for phase: TroubleshootingSession.SessionPhase) -> PhaseState {
        let currentPhase = session.phase
        let phaseOrder = Self.phaseOrder(for: phase)
        let currentOrder = Self.phaseOrder(for: currentPhase)

        // Handle escalation: all non-escalation phases before current are completed
        if currentPhase == .escalation {
            return phaseOrder <= Self.phaseOrder(for: .export) ? .completed : .upcoming
        }

        if phaseOrder < currentOrder {
            // Check if superseded by branch changes
            let hasSupersededSteps = session.stepHistory.contains { step in
                step.phase == phase && step.isSuperseded
            }
            return hasSupersededSteps ? .superseded : .completed
        } else if phaseOrder == currentOrder {
            return .active
        } else {
            return .upcoming
        }
    }

    private static func phaseOrder(for phase: TroubleshootingSession.SessionPhase) -> Int {
        switch phase {
        case .symptom: 0
        case .checks: 1
        case .fix: 2
        case .verify: 3
        case .export: 4
        case .escalation: 5
        }
    }
}

// MARK: - Rail Phase Model

extension ProgressRailView {
    struct RailPhase {
        let phase: TroubleshootingSession.SessionPhase
        let title: String
        let sfSymbol: String
    }
}
