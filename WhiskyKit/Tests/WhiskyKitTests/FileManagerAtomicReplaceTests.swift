//
//  FileManagerAtomicReplaceTests.swift
//  WhiskyKitTests
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
import Testing
@testable import WhiskyKit

/// `replaceFile` puts DXVK's DLLs over a bottle's system DLLs, so a replace
/// that fails part way must leave the original in place, never an empty slot.
@Suite("FileManager atomic replace")
struct FileManagerAtomicReplaceTests {
    private let tempDir: URL
    private let original: URL
    private let replacement: URL

    init() throws {
        tempDir = FileManager.default.temporaryDirectory.appending(path: "atomic_replace_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        original = tempDir.appending(path: "d3d11.dll")
        replacement = tempDir.appending(path: "dxvk-d3d11.dll")
        try Data("wine d3d11".utf8).write(to: original)
        try Data("dxvk d3d11".utf8).write(to: replacement)
    }

    private var temp: URL {
        original.appendingPathExtension("whisky-tmp")
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    @Test("Replaces the file and leaves no temp behind", arguments: [true, false])
    func replacesWithoutTemp(makeOriginalCopy: Bool) throws {
        try FileManager.default.replaceFile(at: original, with: replacement, makeOriginalCopy: makeOriginalCopy)

        #expect(try Data(contentsOf: original) == Data("dxvk d3d11".utf8))
        #expect(!exists(temp))
        let backup = original.appendingPathExtension("orig")
        #expect(exists(backup) == makeOriginalCopy)
        if makeOriginalCopy {
            #expect(try Data(contentsOf: backup) == Data("wine d3d11".utf8))
        }
    }

    @Test("A missing destination is left missing")
    func missingDestinationIsNotCreated() throws {
        let absent = tempDir.appending(path: "absent.dll")

        try FileManager.default.replaceFile(at: absent, with: replacement)

        #expect(!exists(absent))
        #expect(!exists(absent.appendingPathExtension("whisky-tmp")))
    }

    @Test("A replacement that cannot be copied leaves the original in place", arguments: [true, false])
    func failedCopyKeepsOriginal(makeOriginalCopy: Bool) throws {
        let unreadable = tempDir.appending(path: "missing.dll")

        #expect(throws: (any Error).self) {
            try FileManager.default.replaceFile(
                at: original, with: unreadable, makeOriginalCopy: makeOriginalCopy
            )
        }
        #expect(try Data(contentsOf: original) == Data("wine d3d11".utf8))
        #expect(!exists(temp))
    }

    @Test("A temp left by an interrupted replace is cleared")
    func staleTempIsCleared() throws {
        try Data("half written".utf8).write(to: temp)

        try FileManager.default.replaceFile(at: original, with: replacement, makeOriginalCopy: false)

        #expect(try Data(contentsOf: original) == Data("dxvk d3d11".utf8))
        #expect(!exists(temp))
    }
}
