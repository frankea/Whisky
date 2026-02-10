//
//  AudioTroubleshootingStep.swift
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

/// The symptom categories a user can select when starting audio troubleshooting.
///
/// Each symptom maps to an ordered list of fix actions in the
/// ``AudioTroubleshootingEngine``. The wizard guides the user through
/// the most likely fixes for the selected symptom.
public enum AudioSymptom: String, CaseIterable, Identifiable, Sendable {
    /// Games or applications produce no audio output.
    case noSound
    /// Audio plays but with crackling, popping, or distortion.
    case crackling
    /// Sound stutters, skips, or falls out of sync with video.
    case stutter
    /// Sound plays through the wrong speakers or headphones.
    case wrongDevice
    /// Audio works in game menus but not during gameplay.
    case menusOnly

    public var id: String {
        rawValue
    }

    /// Human-readable display name for this symptom.
    public var displayName: String {
        switch self {
        case .noSound: "No sound at all"
        case .crackling: "Crackling or popping"
        case .stutter: "Audio stutter or desync"
        case .wrongDevice: "Wrong output device"
        case .menusOnly: "Sound in menus only"
        }
    }

    /// SF Symbol name for the symptom icon.
    public var sfSymbol: String {
        switch self {
        case .noSound: "speaker.slash"
        case .crackling: "waveform.badge.exclamationmark"
        case .stutter: "waveform.path"
        case .wrongDevice: "hifispeaker.slash"
        case .menusOnly: "list.bullet.rectangle"
        }
    }

    /// Detailed description of this symptom for the selection UI.
    public var symptomDescription: String {
        switch self {
        case .noSound:
            "Games or applications produce no audio output"
        case .crackling:
            "Audio plays but with crackling, popping, or distortion"
        case .stutter:
            "Sound stutters, skips, or falls out of sync with video"
        case .wrongDevice:
            "Sound plays through the wrong speakers or headphones"
        case .menusOnly:
            "Audio works in game menus but not during gameplay"
        }
    }
}

/// A record of a single fix attempt during troubleshooting.
///
/// Tracks which fix action was applied, when, and the before/after
/// values to avoid repeating the same fix and to support undo.
public struct TroubleshootingFixAttempt: Codable, Sendable, Identifiable {
    /// Unique identifier for this attempt.
    public let id: UUID

    /// The fix action identifier that was applied.
    public let actionId: String

    /// When the fix was applied.
    public let timestamp: Date

    /// The setting value before the fix was applied, if applicable.
    public let beforeValue: String?

    /// The setting value after the fix was applied, if applicable.
    public let afterValue: String?

    public init(
        id: UUID = UUID(),
        actionId: String,
        timestamp: Date = Date(),
        beforeValue: String? = nil,
        afterValue: String? = nil
    ) {
        self.id = id
        self.actionId = actionId
        self.timestamp = timestamp
        self.beforeValue = beforeValue
        self.afterValue = afterValue
    }
}
