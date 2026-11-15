//
//  GPTKImporter+Serialization.swift
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

public extension GPTKImporter {
    /// Held by everything that writes the payload store or the runtime's
    /// payload files: import, verify (which takes a failing store back out),
    /// deploy, remove, and the bridge and interposer installs.
    ///
    /// The launch-time update runs on a background task while Settings can
    /// verify, deploy, import or remove at the same moment, and two of those
    /// copying into the same runtime folders at once leave a half-written
    /// payload. Recursive, because some entry points call others.
    internal static let mutationLock = NSRecursiveLock()

    /// Testable seam for ``removeStore()``.
    internal static func removeStore(at store: URL) throws {
        mutationLock.lock()
        defer { mutationLock.unlock() }
        guard FileManager.default.fileExists(atPath: store.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: store)
    }
}
