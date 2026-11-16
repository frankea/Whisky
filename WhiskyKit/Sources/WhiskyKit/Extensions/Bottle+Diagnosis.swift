//
//  Bottle+Diagnosis.swift
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

public extension Bottle {
    /// The program in this bottle whose last run was most recently diagnosed as a crash.
    ///
    /// A program counts once a crash classification has stamped its
    /// ``ProgramSettings/lastDiagnosisDate``. Programs that only ever exited
    /// cleanly have no stamp, so a bottle of them has no diagnosed program.
    ///
    /// - Returns: The program with the newest diagnosis date, or `nil` when no
    ///   program in ``programs`` has one.
    @MainActor
    var mostRecentlyDiagnosedProgram: Program? {
        var newest: (program: Program, date: Date)?
        for program in programs {
            guard let date = program.settings.lastDiagnosisDate else { continue }
            if let current = newest, current.date >= date { continue }
            newest = (program, date)
        }
        return newest?.program
    }
}
