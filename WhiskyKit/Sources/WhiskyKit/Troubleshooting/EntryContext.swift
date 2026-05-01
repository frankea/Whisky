//
//  EntryContext.swift
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

/// Describes where the user entered the troubleshooting wizard from.
///
/// Different entry points provide different levels of pre-existing context.
/// The engine uses this to determine the initial wizard phase and any
/// prefilled evidence.
public enum EntryContext: Sendable {
    /// Primary entry from the Program view with full program context.
    case program(programURL: URL, bottleURL: URL)

    /// Entry from a crash banner with prefilled crash evidence.
    case launchFailure(programURL: URL, bottleURL: URL, evidence: [String: String])

    /// Entry from the bottle Config diagnostics section.
    case bottleDiagnostics(bottleURL: URL)

    /// Entry from the Help menu with optional program context.
    case helpMenu(bottleURL: URL, programURL: URL?)

    /// The bottle URL associated with this entry context.
    public var bottleURL: URL {
        switch self {
        case let .program(_, bottleURL): bottleURL
        case let .launchFailure(_, bottleURL, _): bottleURL
        case let .bottleDiagnostics(bottleURL): bottleURL
        case let .helpMenu(bottleURL, _): bottleURL
        }
    }

    /// The program URL associated with this entry context, if any.
    public var programURL: URL? {
        switch self {
        case let .program(programURL, _): programURL
        case let .launchFailure(programURL, _, _): programURL
        case .bottleDiagnostics: nil
        case let .helpMenu(_, programURL): programURL
        }
    }

    /// The initial wizard phase based on entry context.
    ///
    /// Launch failures and bottle diagnostics start at the checks phase
    /// (skipping symptom selection) since the context is already known.
    /// Other entry points start at symptom selection.
    public var initialPhase: TroubleshootingSession.SessionPhase {
        switch self {
        case .launchFailure: .checks
        case .bottleDiagnostics: .checks
        case .program: .symptom
        case .helpMenu: .symptom
        }
    }
}
