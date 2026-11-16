//
//  WineStrippedCopyTests.swift
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

@Suite("Wine stripped copy install")
struct WineStrippedCopyTests {
    private let tempDir: URL
    private let source: URL
    private let destination: URL

    init() throws {
        tempDir = try makeGPTKTempDir()
        source = tempDir.appending(path: "source").appending(path: "dxgi.dll")
        destination = tempDir.appending(path: "system32").appending(path: "dxgi.dll")
        for dir in [source, destination] {
            try FileManager.default.createDirectory(
                at: dir.deletingLastPathComponent(), withIntermediateDirectories: true
            )
        }
        var wine = fakePE(builtin: true)
        wine.append(Data("wine dxgi".utf8))
        try wine.write(to: source)
    }

    /// The fixed temp name earlier versions used, which a crash could leave behind.
    private var temp: URL {
        destination.appendingPathExtension("whisky-tmp")
    }

    /// Whether any install temp, fixed or unique, is left beside the destination.
    private func noTempsLeft() throws -> Bool {
        let dir = destination.deletingLastPathComponent().path(percentEncoded: false)
        return try !FileManager.default.contentsOfDirectory(atPath: dir).contains { $0.contains(".whisky-tmp") }
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    private func identity(_ url: URL) throws -> (inode: Int, mtime: Date) {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        let inode = try #require(attrs[.systemFileNumber] as? Int)
        let mtime = try #require(attrs[.modificationDate] as? Date)
        return (inode, mtime)
    }

    // MARK: - installStrippedCopy

    @Test("Installs a native copy of the builtin, marker stripped")
    func installsStrippedNativeCopy() throws {
        try Wine.installStrippedCopy(at: destination, from: source)

        #expect(try Wine.isNativePE(destination))
        #expect(Wine.isStrippedCopy(destination, of: source))
        #expect(try Data(contentsOf: destination).suffix(9) == Data("wine dxgi".utf8))
        #expect(try noTempsLeft())
    }

    @Test("Replaces a different file already at the destination")
    func replacesExistingFile() throws {
        try fakePE(builtin: false).write(to: destination)

        try Wine.installStrippedCopy(at: destination, from: source)

        #expect(Wine.isStrippedCopy(destination, of: source))
        #expect(try noTempsLeft())
    }

    @Test("A second install leaves the stripped copy untouched")
    func secondInstallIsANoOp() throws {
        try Wine.installStrippedCopy(at: destination, from: source)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_000_000)],
            ofItemAtPath: destination.path(percentEncoded: false)
        )
        let before = try identity(destination)

        try Wine.installStrippedCopy(at: destination, from: source)

        let after = try identity(destination)
        #expect(after.inode == before.inode)
        #expect(after.mtime == before.mtime)
    }

    @Test("An unmarked source throws and leaves the destination as it was")
    func unmarkedSourceLeavesDestination() throws {
        try fakePE(builtin: false).write(to: source)
        let keep = Data("keep me".utf8)
        try keep.write(to: destination)

        #expect(throws: WineStrippedCopyError.sourceNotBuiltinMarked("dxgi.dll")) {
            try Wine.installStrippedCopy(at: destination, from: source)
        }
        #expect(try Data(contentsOf: destination) == keep)
        #expect(try noTempsLeft())
    }

    @Test("A missing source throws and never leaves the destination missing")
    func missingSourceLeavesDestination() throws {
        try FileManager.default.removeItem(at: source)
        let before = fakePE(builtin: true)
        try before.write(to: destination)

        #expect(throws: WineStrippedCopyError.self) {
            try Wine.installStrippedCopy(at: destination, from: source)
        }
        #expect(try Data(contentsOf: destination) == before)
        #expect(try noTempsLeft())
    }

    @Test("A swap that fails after the temp is written removes the temp and keeps the destination")
    func failedSwapRemovesTemp() throws {
        // rename(2) will not put a file over a non-empty directory, so the
        // copy and the strip succeed and only the swap fails.
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        let inside = destination.appending(path: "keep.txt")
        try Data("keep me".utf8).write(to: inside)

        #expect(throws: (any Error).self) {
            try Wine.installStrippedCopy(at: destination, from: source)
        }
        #expect(try Data(contentsOf: inside) == Data("keep me".utf8))
        #expect(try noTempsLeft())
    }

    @Test("A symlinked destination is replaced by the stripped copy and its target keeps its bytes")
    func symlinkedDestinationIsReplaced() throws {
        let target = tempDir.appending(path: "linked-dxgi.dll")
        let linked = Data("linked dxgi".utf8)
        try linked.write(to: target)
        try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: target)

        try Wine.installStrippedCopy(at: destination, from: source)

        let type = try FileManager.default.attributesOfItem(atPath: destination.path(percentEncoded: false))[.type]
        #expect(type as? FileAttributeType == .typeRegular)
        #expect(Wine.isStrippedCopy(destination, of: source))
        #expect(try Data(contentsOf: target) == linked)
        #expect(try noTempsLeft())
    }

    @Test("A read-only destination is replaced")
    func readOnlyDestinationIsReplaced() throws {
        try fakePE(builtin: false).write(to: destination)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o444], ofItemAtPath: destination.path(percentEncoded: false)
        )

        try Wine.installStrippedCopy(at: destination, from: source)

        #expect(Wine.isStrippedCopy(destination, of: source))
        #expect(try noTempsLeft())
    }

    @Test("A temp left by an interrupted install is replaced, then cleaned up")
    func staleTempIsCleanedUp() throws {
        try Data("half written".utf8).write(to: temp)

        try Wine.installStrippedCopy(at: destination, from: source)

        #expect(Wine.isStrippedCopy(destination, of: source))
        #expect(try noTempsLeft())
    }

    @Test("A symlinked source is copied from its target, which keeps its marker")
    func symlinkedSourceIsNotWrittenThrough() throws {
        let link = tempDir.appending(path: "source").appending(path: "linked-dxgi.dll")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        let before = try Data(contentsOf: source)

        try Wine.installStrippedCopy(at: destination, from: link)

        #expect(try Data(contentsOf: source) == before)
        #expect(Wine.carriesBuiltinMarker(source))
        #expect(Wine.isStrippedCopy(destination, of: source))
        let type = try FileManager.default.attributesOfItem(atPath: destination.path(percentEncoded: false))[.type]
        #expect(type as? FileAttributeType == .typeRegular)
        #expect(try noTempsLeft())
    }

    @Test("Each install gets a temp name of its own")
    func tempNamesAreUnique() {
        let first = FileManager.default.uniqueTempURL(beside: destination)
        let second = FileManager.default.uniqueTempURL(beside: destination)

        #expect(first != second)
        #expect(first.deletingLastPathComponent() == destination.deletingLastPathComponent())
        #expect(first.lastPathComponent.hasPrefix("dxgi.dll.whisky-tmp-"))
    }

    @Test("A failed copy leaves the destination and no temp behind")
    func failedCopyLeavesDestination() throws {
        let keep = Data("keep me".utf8)
        try keep.write(to: destination)
        let dir = destination.deletingLastPathComponent().path(percentEncoded: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir) }

        #expect(throws: (any Error).self) {
            try Wine.installStrippedCopy(at: destination, from: source)
        }
        #expect(try Data(contentsOf: destination) == keep)
        #expect(try noTempsLeft())
    }

    // MARK: - deployCleanDXGI

    private var prefixRoot: URL {
        tempDir.appending(path: "bottle")
    }

    private var prefixDXGI: URL {
        prefixRoot.appending(path: "drive_c/windows/system32/dxgi.dll")
    }

    private func makePrefix(holding contents: Data) throws {
        try FileManager.default.createDirectory(
            at: prefixDXGI.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try contents.write(to: prefixDXGI)
    }

    @Test("Deploying from a resolved source installs its stripped copy")
    func deployFromResolvedSource() throws {
        try makePrefix(holding: fakePE(builtin: true))

        Wine.deployCleanDXGI(prefixRoot: prefixRoot, source: .libWine(source))

        #expect(Wine.isStrippedCopy(prefixDXGI, of: source))
    }

    @Test("An unavailable source leaves the prefix's dxgi as it is")
    func unavailableSourceLeavesPrefix() throws {
        let existing = fakePE(builtin: true)
        try makePrefix(holding: existing)

        Wine.deployCleanDXGI(prefixRoot: prefixRoot, source: .unavailable(.missingFile))

        #expect(try Data(contentsOf: prefixDXGI) == existing)
    }

    @Test("Originals stamped for an older engine are never deployed")
    func staleOriginalsAreRefused() throws {
        let runtime = tempDir.appending(path: "Libraries")
        try makeRuntime(at: runtime)
        try writeRuntimeVersion(at: runtime, 11, 19, 0)
        let store = try makeImportedStore(in: tempDir)
        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)
        try writeRuntimeVersion(at: runtime, 11, 20, 0)
        let existing = fakePE(builtin: true)
        try makePrefix(holding: existing)

        Wine.reconcileDXGIForDXVK(
            prefixRoot: prefixRoot, gptkPayloadIsDeployed: true, libraryFolder: runtime, store: store
        )

        #expect(try Data(contentsOf: prefixDXGI) == existing)
    }

    @Test("Originals stamped for the installed engine are deployed")
    func currentOriginalsAreDeployed() throws {
        let runtime = tempDir.appending(path: "Libraries")
        try makeRuntime(at: runtime)
        try writeRuntimeVersion(at: runtime, 11, 19, 0)
        let store = try makeImportedStore(in: tempDir)
        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)
        try makePrefix(holding: fakePE(builtin: true))

        Wine.reconcileDXGIForDXVK(
            prefixRoot: prefixRoot, gptkPayloadIsDeployed: true, libraryFolder: runtime, store: store
        )

        let original = store.appending(path: "originals").appending(path: "dxgi.dll")
        #expect(Wine.isStrippedCopy(prefixDXGI, of: original))
    }
}
