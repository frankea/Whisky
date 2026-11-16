//
//  ProcessRegistry+ProcessInfo.swift
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

extension ProcessRegistry {
    /// Information about a tracked Wine process.
    public struct ProcessInfo: Hashable, Sendable {
        /// Process ID (may be 0 if not yet launched)
        public let pid: Int32
        /// When the process was launched
        public let launchTime: Date
        /// URL of the bottle containing this process
        public let bottleURL: URL
        /// Name of the program/executable
        public let programName: String
        /// Identity of the underlying `Process` object, used to disambiguate
        /// pre-launch entries (where ``pid`` is still 0). Excluded from hashing
        /// and equality so that updating ``pid`` does not change identity.
        let processIdentity: ObjectIdentifier?

        public init(
            pid: Int32,
            launchTime: Date,
            bottleURL: URL,
            programName: String,
            processIdentity: ObjectIdentifier? = nil
        ) {
            self.pid = pid
            self.launchTime = launchTime
            self.bottleURL = bottleURL
            self.programName = programName
            self.processIdentity = processIdentity
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(pid)
            hasher.combine(launchTime)
            hasher.combine(bottleURL)
            hasher.combine(programName)
        }

        public static func == (lhs: ProcessInfo, rhs: ProcessInfo) -> Bool {
            lhs.pid == rhs.pid &&
                lhs.launchTime == rhs.launchTime &&
                lhs.bottleURL == rhs.bottleURL &&
                lhs.programName == rhs.programName
        }
    }
}
