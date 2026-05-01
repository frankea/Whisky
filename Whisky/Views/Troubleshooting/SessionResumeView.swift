//
//  SessionResumeView.swift
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

/// Overlay shown when a paused session is found with Resume/Start over/Discard options.
///
/// Per locked session persistence decisions. Displays a card with session summary,
/// relative time since last update, and "Since you left" staleness changes.
/// Provides three explicit actions: Resume, Start Over, and Discard.
struct SessionResumeView: View {
    let session: TroubleshootingSession
    let stalenessChanges: [StalenessChange]
    var onResume: (TroubleshootingSession) -> Void
    var onStartOver: () -> Void
    var onDiscard: () -> Void

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            resumeCard
        }
    }
}

// MARK: - Resume Card

extension SessionResumeView {
    private var resumeCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            cardHeader
            sessionSummary
            if !stalenessChanges.isEmpty {
                sinceYouLeftSection
            }
            actionButtons
        }
        .padding(20)
        .frame(maxWidth: 420)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
    }
}

// MARK: - Header

extension SessionResumeView {
    private var cardHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.counterclockwise.circle.fill")
                .foregroundStyle(.blue)
                .font(.title2)
            Text("Resume Troubleshooting?")
                .font(.title3)
                .fontWeight(.semibold)
        }
    }
}

// MARK: - Session Summary

extension SessionResumeView {
    private var sessionSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let category = session.symptomCategory {
                Text("You have a paused session for \(category.displayTitle)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("Last updated: \(session.lastUpdatedAt, style: .relative) ago")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Since You Left

extension SessionResumeView {
    private var sinceYouLeftSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Since you left:")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            ForEach(Array(stalenessChanges.enumerated()), id: \.offset) { _, change in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "arrow.right.circle")
                        .foregroundStyle(.orange)
                        .font(.caption2)
                    Text(change.displayMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.06))
        )
    }
}

// MARK: - Action Buttons

extension SessionResumeView {
    private var actionButtons: some View {
        VStack(spacing: 8) {
            Button {
                onResume(session)
            } label: {
                Text("Resume")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            HStack(spacing: 12) {
                Button("Start Over") {
                    onStartOver()
                }
                .buttonStyle(.bordered)

                Button("Discard", role: .destructive) {
                    onDiscard()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
            }
        }
    }
}
