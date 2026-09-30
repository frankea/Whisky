//
//  WineRegistryImport.swift
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

extension Wine {
    /// A `reg import` that ran but did not succeed.
    struct RegistryImportError: LocalizedError {
        /// What the import exited with, or -1 when it never reported an exit.
        let exitCode: Int32

        var errorDescription: String? {
            "reg import exited with code \(exitCode)"
        }
    }

    /// Imports a `.reg` document into the bottle's registry in one Wine process.
    ///
    /// The file is written as UTF-16LE behind a BOM: Wine reads a `.reg` as
    /// Unicode only when it starts with one, and otherwise parses it as ANSI,
    /// matches no header and imports nothing.
    ///
    /// - Throws: ``RegistryImportError`` when the import exits with anything
    ///   but 0. `reg` does for a file it cannot open or whose header it does
    ///   not recognize, and Wine does when it cannot start in the prefix.
    @MainActor
    static func importRegistry(document: String, bottle: Bottle) async throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "whisky-registry-\(UUID().uuidString).reg")
        try ("\u{FEFF}" + document).write(to: url, atomically: true, encoding: .utf16LittleEndian)
        defer { try? FileManager.default.removeItem(at: url) }

        // `reg import`, not `regedit`: regedit has no silent switch, so it puts
        // up the import confirmation and never exits.
        let arguments = ["reg", "import", url.path(percentEncoded: false)]
        var exitCode: Int32 = -1
        for await output in try runWineProcess(args: arguments, bottle: bottle) {
            if case let .terminated(code) = output {
                exitCode = code
            }
        }
        guard exitCode == 0 else {
            throw RegistryImportError(exitCode: exitCode)
        }
    }
}
