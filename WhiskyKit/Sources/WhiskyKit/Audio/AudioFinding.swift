//
//  AudioFinding.swift
//  WhiskyKit
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

import Foundation

/// A single diagnostic finding from audio troubleshooting.
///
/// Matches the Phase 5 ``DiagnosisMatch`` pattern, scoped to audio-specific
/// issues. Each finding carries a confidence tier (reusing ``ConfidenceTier``
/// from Phase 5 diagnostics) and optional remediation guidance.
public struct AudioFinding: Sendable, Identifiable, Equatable {
    /// Stable identifier for this finding.
    public let id: String

    /// Human-readable description of the detected issue.
    public let description: String

    /// Confidence tier for this finding, reusing the Phase 5 model.
    public let confidence: ConfidenceTier

    /// Technical evidence supporting the finding (e.g. log excerpt, property value).
    public let evidence: String

    /// Brief remediation hint, if available.
    public let suggestedAction: String?

    public init(
        id: String,
        description: String,
        confidence: ConfidenceTier,
        evidence: String,
        suggestedAction: String? = nil
    ) {
        self.id = id
        self.description = description
        self.confidence = confidence
        self.evidence = evidence
        self.suggestedAction = suggestedAction
    }
}
