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

    /// The fixed temp name earlier versions used, which a crash could leave behind.
    private var temp: URL {
        original.appendingPathExtension("whisky-tmp")
    }

    /// Whether any install temp, fixed or unique, is left beside the destination.
    private func noTempsLeft() throws -> Bool {
        let dir = original.deletingLastPathComponent().path(percentEncoded: false)
        return try !FileManager.default.contentsOfDirectory(atPath: dir).contains { $0.contains(".whisky-tmp") }
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    @Test("Replaces the file and leaves no temp behind", arguments: [true, false])
    func replacesWithoutTemp(makeOriginalCopy: Bool) throws {
        try FileManager.default.replaceFile(at: original, with: replacement, makeOriginalCopy: makeOriginalCopy)

        #expect(try Data(contentsOf: original) == Data("dxvk d3d11".utf8))
        #expect(try noTempsLeft())
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
        #expect(try noTempsLeft())
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
        #expect(try noTempsLeft())
    }

    @Test("A temp left by an interrupted replace is cleared")
    func staleTempIsCleared() throws {
        try Data("half written".utf8).write(to: temp)

        try FileManager.default.replaceFile(at: original, with: replacement, makeOriginalCopy: false)

        #expect(try Data(contentsOf: original) == Data("dxvk d3d11".utf8))
        #expect(try noTempsLeft())
    }

    @Test("A symlinked destination is replaced by a file and its target keeps its bytes", arguments: [true, false])
    func symlinkedDestinationIsReplaced(makeOriginalCopy: Bool) throws {
        // What DXVK's own `setup_dxvk.sh --symlink` leaves in a bottle.
        let target = tempDir.appending(path: "linked-d3d11.dll")
        try FileManager.default.moveItem(at: original, to: target)
        try FileManager.default.createSymbolicLink(at: original, withDestinationURL: target)

        try FileManager.default.replaceFile(at: original, with: replacement, makeOriginalCopy: makeOriginalCopy)

        let type = try FileManager.default.attributesOfItem(atPath: original.path(percentEncoded: false))[.type]
        #expect(type as? FileAttributeType == .typeRegular)
        #expect(try Data(contentsOf: original) == Data("dxvk d3d11".utf8))
        #expect(try Data(contentsOf: target) == Data("wine d3d11".utf8))
        #expect(try noTempsLeft())
    }

    @Test("A read-only destination is replaced", arguments: [true, false])
    func readOnlyDestinationIsReplaced(makeOriginalCopy: Bool) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o444], ofItemAtPath: original.path(percentEncoded: false)
        )

        try FileManager.default.replaceFile(at: original, with: replacement, makeOriginalCopy: makeOriginalCopy)

        #expect(try Data(contentsOf: original) == Data("dxvk d3d11".utf8))
        #expect(try noTempsLeft())
    }

    @Test("A swap that fails after the temp is written removes the temp and keeps the destination")
    func failedSwapRemovesTemp() throws {
        // rename(2) will not put a file over a non-empty directory, so the
        // copy into the temp succeeds and the swap is what fails.
        try FileManager.default.removeItem(at: original)
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: false)
        let inside = original.appending(path: "keep.txt")
        try Data("keep me".utf8).write(to: inside)

        #expect(throws: (any Error).self) {
            try FileManager.default.replaceFile(at: original, with: replacement, makeOriginalCopy: false)
        }
        #expect(try Data(contentsOf: inside) == Data("keep me".utf8))
        #expect(try noTempsLeft())
    }

    @Test("replaceDLLs leaves an excluded DLL alone, whatever its case, and replaces the rest")
    func replaceDLLsExcluding() throws {
        let source = tempDir.appending(path: "payload")
        let destination = tempDir.appending(path: "system32")
        for folder in [source, destination] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        for dll in ["d3d11.dll", "d3d10core.dll"] {
            try Data("dxvk \(dll)".utf8).write(to: source.appending(path: dll))
            try Data("wine \(dll)".utf8).write(to: destination.appending(path: dll))
        }

        try FileManager.default.replaceDLLs(in: destination, withContentsIn: source, excluding: ["D3D11.DLL"])

        #expect(try Data(contentsOf: destination.appending(path: "d3d11.dll")) == Data("wine d3d11.dll".utf8))
        #expect(
            try Data(contentsOf: destination.appending(path: "d3d10core.dll")) == Data("dxvk d3d10core.dll".utf8)
        )
    }
}
