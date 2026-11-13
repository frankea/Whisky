//
//  FixApplicator+Reversal.swift
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

// MARK: - Enhanced Diagnostics

public extension FixApplicator {
    /// The WINEDEBUG preset `run-enhanced-diagnostics` turns on when its
    /// flow node names none.
    static let enhancedDiagnosticsPreset: WineDebugPreset = .verbose

    /// Whether running enhanced diagnostics would change a program's
    /// logging: not when the program already logs with the enhanced preset.
    ///
    /// - Parameter currentPreset: The program's WINEDEBUG preset, `nil` for
    ///   the default.
    /// - Returns: `true` when the fix would turn on more logging.
    static func enhancedDiagnosticsAddsLogging(to currentPreset: WineDebugPreset?) -> Bool {
        currentPreset != enhancedDiagnosticsPreset
    }
}

// MARK: - Undo Availability

public extension FixApplicator {
    /// Whether ``undo(attempt:bottle:program:)`` can restore an applied fix,
    /// decided from the attempt alone.
    ///
    /// Reads no settings, files or registry, so a view can ask on every
    /// render; ``preview(fixId:params:bottle:program:)`` reads the current
    /// value (all of `system.reg` for a registry fix) and is for the fix
    /// card.
    ///
    /// - Parameters:
    ///   - attempt: The applied attempt.
    ///   - hasProgram: Whether a program is at hand, which program-scoped
    ///     fixes need to be undone.
    /// - Returns: `true` when the fix is reversible and the attempt kept
    ///   what undoing it needs.
    static func canUndo(_ attempt: FixAttempt, hasProgram: Bool) -> Bool {
        switch attempt.fixId {
        case "switch-backend":
            guard attempt.beforeValue.flatMap(GraphicsBackend.init(rawValue:)) != nil else { return false }
            return attempt.params?[backendScopeKey] != "program" || hasProgram
        case "enable-dxvk-async", "set-audio-driver", "set-buffer-size", "enable-esync",
             "enable-controller-compat":
            return attempt.beforeValue != nil
        case "run-enhanced-diagnostics":
            return hasProgram
        case "set-registry-value":
            return attempt.params?["key"] != nil && attempt.params?["valueName"] != nil
        case "apply-game-config":
            return true
        default:
            return false
        }
    }
}
