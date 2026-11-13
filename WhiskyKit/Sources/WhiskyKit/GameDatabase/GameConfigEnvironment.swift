//
//  GameConfigEnvironment.swift
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

/// Environment variables an applied game configuration sets for that game's
/// executables in a bottle.
///
/// ``GameConfigApplicator`` writes a variant's environment variables into the
/// settings of the game's programs when it can find them in the bottle. When
/// the game isn't there yet (applied before it was installed), the variables
/// are kept here instead, in ``BottleSettings/gameConfigEnvironments``, and
/// every launch of one of ``executables`` gets them through the
/// ``EnvironmentLayer/gameProfile`` layer. They live in the bottle settings,
/// so reverting the configuration's snapshot removes them with the rest.
public struct GameConfigEnvironment: Codable, Sendable, Equatable, Identifiable {
    /// The ``GameDBEntry`` these variables came from.
    public var entryId: String
    /// The game's display title, for the bottle configuration view.
    public var title: String
    /// The executable file names the variables apply to, matched without
    /// regard to case. Empty means every program launched in the bottle.
    public var executables: [String]
    /// The variables to set.
    public var variables: [String: String]

    public var id: String {
        entryId
    }

    public init(entryId: String, title: String, executables: [String], variables: [String: String]) {
        self.entryId = entryId
        self.title = title
        self.executables = executables
        self.variables = variables
    }

    /// Whether these variables apply to a launch of `executableName`.
    ///
    /// - Parameter executableName: The file name of the executable being launched.
    /// - Returns: `true` when ``executables`` is empty or names it, ignoring case.
    public func applies(toExecutable executableName: String) -> Bool {
        executables.isEmpty
            || executables.contains { $0.caseInsensitiveCompare(executableName) == .orderedSame }
    }
}

extension BottleSettings {
    /// The variables applied game configurations set for a launch of `executableName`.
    ///
    /// When two configurations set the same variable, the one applied later wins.
    ///
    /// - Parameter executableName: The file name of the executable being launched.
    /// - Returns: The merged variables; empty when no configuration applies.
    public func gameConfigEnvironment(forExecutable executableName: String) -> [String: String] {
        var environment: [String: String] = [:]
        for record in gameConfigEnvironments where record.applies(toExecutable: executableName) {
            environment.merge(record.variables) { _, new in new }
        }
        return environment
    }
}
