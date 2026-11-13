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
