//
//  CheckContext.swift
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

/// Context passed to every ``TroubleshootingCheck`` implementation.
///
/// Provides access to the bottle and program identity, preflight data snapshot,
/// and current session state. Since ``Bottle`` and ``Program`` are `@MainActor`
/// classes, this struct stores their URLs and names as `Sendable` values.
/// Use the ``create(bottle:program:preflight:session:)`` factory method
/// to safely capture values from the main actor.
public struct CheckContext: Sendable {
    /// URL of the bottle being troubleshot.
    public let bottleURL: URL

    /// Display name of the bottle.
    public let bottleName: String

    /// URL of the program being troubleshot, if any.
    public let programURL: URL?

    /// Display name of the program, if any.
    public let programName: String?

    /// Preflight data snapshot collected at session start.
    public let preflight: PreflightData

    /// Current session state for accessing check results and fix history.
    public let session: TroubleshootingSession

    public init(
        bottleURL: URL,
        bottleName: String,
        programURL: URL? = nil,
        programName: String? = nil,
        preflight: PreflightData,
        session: TroubleshootingSession
    ) {
        self.bottleURL = bottleURL
        self.bottleName = bottleName
        self.programURL = programURL
        self.programName = programName
        self.preflight = preflight
        self.session = session
    }

    /// Creates a ``CheckContext`` by safely capturing values from `@MainActor` types.
    ///
    /// - Parameters:
    ///   - bottle: The bottle being troubleshot.
    ///   - program: The program being troubleshot, if any.
    ///   - preflight: Preflight data snapshot.
    ///   - session: Current troubleshooting session.
    /// - Returns: A new context with captured values.
    @MainActor
    public static func create(
        bottle: Bottle,
        program: Program?,
        preflight: PreflightData,
        session: TroubleshootingSession
    ) -> CheckContext {
        CheckContext(
            bottleURL: bottle.url,
            bottleName: bottle.settings.name,
            programURL: program?.url,
            programName: program?.name,
            preflight: preflight,
            session: session
        )
    }
}
