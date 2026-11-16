//
//  WhiskyWineInstallerTests.swift
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

// swiftlint:disable file_length
import CryptoKit
import SemanticVersion
@testable import WhiskyKit
import XCTest

// swiftlint:disable:next type_body_length
final class WhiskyWineInstallerTests: XCTestCase {
    func testCleanupTarballRemovesExistingFile() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tarURL = tempDir.appendingPathComponent("whiskywine").appendingPathExtension("tar.gz")
        try Data("test".utf8).write(to: tarURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tarURL.path))

        WhiskyWineInstaller.cleanupTarball(at: tarURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: tarURL.path))
    }

    func testRemoveBottleStorageDeletesDefaultBottlesAndRegistryOnly() throws {
        let tempDir = try makeTempDir()
        let bottles = tempDir.appending(path: "Bottles")
        let registry = tempDir.appending(path: "BottleVM.plist")
        let custom = tempDir.appending(path: "elsewhere")
        for dir in [bottles.appending(path: "one"), custom] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try Data("x".utf8).write(to: registry)

        WhiskyWineInstaller.removeBottleStorage(defaultBottlesDir: bottles, registryFile: registry)

        XCTAssertFalse(FileManager.default.fileExists(atPath: bottles.path(percentEncoded: false)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: registry.path(percentEncoded: false)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: custom.path(percentEncoded: false)))

        // Running again with nothing left must not fail.
        WhiskyWineInstaller.removeBottleStorage(defaultBottlesDir: bottles, registryFile: registry)
    }

    func testRemovedRegistryReloadsAsEmpty() throws {
        let tempDir = try makeTempDir()
        let registry = tempDir.appending(path: "BottleVM.plist")
        var data = BottleData(entriesFile: registry)
        data.paths = [tempDir.appending(path: "Bottles/one")]
        XCTAssertEqual(BottleData(entriesFile: registry).paths.count, 1)

        WhiskyWineInstaller.removeBottleStorage(
            defaultBottlesDir: tempDir.appending(path: "Bottles"), registryFile: registry
        )

        XCTAssertTrue(BottleData(entriesFile: registry).paths.isEmpty)
    }

    func testCleanupTarballIgnoresMissingFile() {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("tar.gz")

        WhiskyWineInstaller.cleanupTarball(at: missingURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: missingURL.path))
    }

    /// Verifies that cleanupTarball handles removal errors gracefully without crashing.
    /// The file should remain when deletion fails due to permission restrictions.
    func testCleanupTarballHandlesRemovalError() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: tempDir.path
            )
            try? FileManager.default.removeItem(at: tempDir)
        }

        let tarURL = tempDir.appendingPathComponent("whiskywine").appendingPathExtension("tar.gz")
        try Data("test".utf8).write(to: tarURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555],
            ofItemAtPath: tempDir.path
        )

        WhiskyWineInstaller.cleanupTarball(at: tarURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: tarURL.path))
    }

    func testWhiskyWineInfoAtReadsVersionAndDXVK() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let plistURL = tempDir.appendingPathComponent("WhiskyWineVersion").appendingPathExtension("plist")
        let plist: [String: Any] = [
            "version": ["major": 3, "minor": 0, "patch": 0],
            "dxvkVersion": "1.10.3"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL)

        let info = WhiskyWineInstaller.whiskyWineInfo(at: plistURL)

        XCTAssertEqual(info?.version, SemanticVersion(3, 0, 0))
        XCTAssertEqual(info?.dxvkVersion, "1.10.3")
    }

    func testWhiskyWineInfoAtMissingFileReturnsNil() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("WhiskyWineVersion.plist")

        XCTAssertNil(WhiskyWineInstaller.whiskyWineInfo(at: missing))
    }

    func testWhiskyWineInfoAtMalformedFileReturnsNil() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // A present-but-corrupt plist must be swallowed to nil, not crash.
        let garbageURL = tempDir.appendingPathComponent("WhiskyWineVersion").appendingPathExtension("plist")
        try Data("this is not a plist".utf8).write(to: garbageURL)

        XCTAssertNil(WhiskyWineInstaller.whiskyWineInfo(at: garbageURL))
    }

    func testWhiskyWineInfoAtPartialPlistReturnsNil() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Valid plist but missing a required version field — decode throws, swallowed to nil.
        let partialURL = tempDir.appendingPathComponent("WhiskyWineVersion").appendingPathExtension("plist")
        let plist: [String: Any] = ["version": ["major": 3, "minor": 0]]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: partialURL)

        XCTAssertNil(WhiskyWineInstaller.whiskyWineInfo(at: partialURL))
    }

    // MARK: - isRuntimePresent (plist + wine64)

    /// Builds a runtime tree under `folder` with an optional version plist and an
    /// optional `wine64` binary, mirroring the layout the installer extracts.
    private func makeRuntime(in folder: URL, plist: Bool, wine64: Bool) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if plist {
            let plistURL = folder.appending(path: "WhiskyWineVersion").appendingPathExtension("plist")
            let contents: [String: Any] = ["version": ["major": 3, "minor": 0, "patch": 0]]
            let data = try PropertyListSerialization.data(fromPropertyList: contents, format: .xml, options: 0)
            try data.write(to: plistURL)
        }
        if wine64 {
            let binDir = folder.appending(path: "Wine").appending(path: "bin")
            try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
            try Data("#!/bin/sh\n".utf8).write(to: binDir.appending(path: "wine64"))
        }
    }

    func testRuntimePresentWhenPlistAndBinaryExist() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try makeRuntime(in: tempDir, plist: true, wine64: true)

        XCTAssertTrue(WhiskyWineInstaller.isRuntimePresent(inLibraryFolder: tempDir))
    }

    func testRuntimeNotPresentWhenBinaryMissing() throws {
        // The #63 case: a half-extracted runtime keeps the plist but loses wine64.
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try makeRuntime(in: tempDir, plist: true, wine64: false)

        XCTAssertFalse(WhiskyWineInstaller.isRuntimePresent(inLibraryFolder: tempDir))
    }

    func testRuntimeNotPresentWhenPlistMissing() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try makeRuntime(in: tempDir, plist: false, wine64: true)

        XCTAssertFalse(WhiskyWineInstaller.isRuntimePresent(inLibraryFolder: tempDir))
    }

    // MARK: - isD3DMetalPresent (GPTK payload)

    func testD3DMetalPresentWhenFrameworkExists() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let external = tempDir.appending(path: "Wine").appending(path: "lib").appending(path: "external")
        try FileManager.default.createDirectory(
            at: external.appending(path: "D3DMetal.framework"),
            withIntermediateDirectories: true
        )

        XCTAssertTrue(WhiskyWineInstaller.isD3DMetalPresent(inLibraryFolder: tempDir))
    }

    func testD3DMetalNotPresentInRuntimeWithoutGPTKPayload() throws {
        // The layout the current Libraries bundle actually ships: Wine, DXVK
        // and DXMT, but no D3DMetal payload under Wine/lib/external.
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try makeRuntime(in: tempDir, plist: true, wine64: true)
        try FileManager.default.createDirectory(
            at: tempDir.appending(path: "DXVK").appending(path: "x64"),
            withIntermediateDirectories: true
        )

        XCTAssertFalse(WhiskyWineInstaller.isD3DMetalPresent(inLibraryFolder: tempDir))
    }

    // MARK: - backendAvailability (issue #146)

    func testD3DMetalUnavailableWithoutPayload() {
        let runtime = WhiskyWineVersion(version: SemanticVersion(3, 1, 1), dxmtVersion: "0.80")

        XCTAssertFalse(WhiskyWineInstaller.backendAvailability(
            .d3dMetal, runtimeInfo: runtime, d3dMetalInstalled: false, dxmtRuntimeNative: true
        ))
    }

    func testD3DMetalAvailableWithPayload() {
        let runtime = WhiskyWineVersion(version: SemanticVersion(3, 1, 1), dxmtVersion: "0.80")

        XCTAssertTrue(WhiskyWineInstaller.backendAvailability(
            .d3dMetal, runtimeInfo: runtime, d3dMetalInstalled: true, dxmtRuntimeNative: true
        ))
    }

    func testDXMTRequiresNativePayloadVariant() {
        let runtime = WhiskyWineVersion(version: SemanticVersion(3, 1, 1), dxmtVersion: "0.80")

        XCTAssertFalse(WhiskyWineInstaller.backendAvailability(
            .dxmt, runtimeInfo: runtime, d3dMetalInstalled: true, dxmtRuntimeNative: false
        ))
        XCTAssertTrue(WhiskyWineInstaller.backendAvailability(
            .dxmt, runtimeInfo: runtime, d3dMetalInstalled: false, dxmtRuntimeNative: true
        ))
    }

    func testUniversalBackendsUnaffectedByMissingPayloads() {
        for backend in [GraphicsBackend.recommended, .dxvk, .wined3d] {
            XCTAssertTrue(WhiskyWineInstaller.backendAvailability(
                backend, runtimeInfo: nil, d3dMetalInstalled: false, dxmtRuntimeNative: false
            ))
        }
    }

    func testRuntimeNotPresentWhenFolderEmpty() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertFalse(WhiskyWineInstaller.isRuntimePresent(inLibraryFolder: tempDir))
    }

    // MARK: - install(from:) error propagation

    func testInstallThrowsWhenTarballMissing() {
        // The guard runs before the destination is touched, so this is safe to
        // exercise against the real application folder.
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("tar.gz")

        XCTAssertThrowsError(try WhiskyWineInstaller.install(from: missing)) { error in
            XCTAssertEqual(error as? WhiskyWineInstallError, .tarballNotFound)
        }
    }

    func testInstallThrowsOnInvalidArchive() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // A non-tar payload makes the extraction fail; `into:` keeps it off the
        // real application folder.
        let badTarball = tempDir.appendingPathComponent("bad").appendingPathExtension("tar.gz")
        try Data("not a tarball".utf8).write(to: badTarball)
        let destination = tempDir.appendingPathComponent("dest")

        XCTAssertThrowsError(try WhiskyWineInstaller.install(tarball: badTarball, into: destination))
    }

    func testInstallExtractsValidArchiveIntoDestination() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tarball = try makeRuntimeTarball(in: tempDir)

        let destination = tempDir.appendingPathComponent("dest")
        try WhiskyWineInstaller.install(tarball: tarball, into: destination)

        let extracted = destination.appendingPathComponent("Libraries/marker.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: extracted.path))
        XCTAssertTrue(WhiskyWineInstaller.isRuntimePresent(
            inLibraryFolder: destination.appendingPathComponent("Libraries")
        ))
    }

    func testInstallReplacesExistingDestinationContents() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tarball = try makeRuntimeTarball(in: tempDir)

        // Pre-existing install with a stale file that the rebuild must remove,
        // rather than merging the new contents on top of it.
        let destination = tempDir.appendingPathComponent("dest")
        let stale = destination.appendingPathComponent("Libraries/stale.txt")
        try FileManager.default.createDirectory(
            at: stale.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("stale".utf8).write(to: stale)

        try WhiskyWineInstaller.install(tarball: tarball, into: destination)

        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path), "Stale contents should be removed")
        let extracted = destination.appendingPathComponent("Libraries/marker.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: extracted.path))
    }

    func testInstallPreservesDestinationSiblingsOutsideLibraries() throws {
        // The destination is the live Application Support folder: besides the
        // runtime it holds unrelated app state (the analytics SDK's storage with
        // its anonymous ID and queued events, and anything added later). A
        // runtime install must replace only Libraries/, never its siblings —
        // wiping the whole folder silently destroys that state on every
        // install/update.
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tarball = try makeRuntimeTarball(in: tempDir)

        // A destination that already has a stale runtime AND an unrelated
        // sibling directory with a file in it.
        let destination = tempDir.appendingPathComponent("dest")
        let stale = destination.appendingPathComponent("Libraries/stale.txt")
        try FileManager.default.createDirectory(
            at: stale.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("stale".utf8).write(to: stale)
        let sibling = destination.appendingPathComponent("analytics-store/queued-event.json")
        try FileManager.default.createDirectory(
            at: sibling.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{}".utf8).write(to: sibling)

        try WhiskyWineInstaller.install(tarball: tarball, into: destination)

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: sibling.path),
            "Install must not delete unrelated state next to Libraries/ in the destination"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path), "Stale runtime contents are replaced")
        let extracted = destination.appendingPathComponent("Libraries/marker.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: extracted.path))
    }

    // MARK: - install keeps the previous runtime on failure

    func testInstallKeepsExistingRuntimeWhenExtractionFails() throws {
        // A corrupt or truncated download (or a disk that fills up mid-untar)
        // must not cost the user the runtime they already had.
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let badTarball = tempDir.appendingPathComponent("bad").appendingPathExtension("tar.gz")
        try Data("not a tarball".utf8).write(to: badTarball)

        let destination = tempDir.appendingPathComponent("dest")
        let installed = try makeInstalledRuntime(in: destination)

        XCTAssertThrowsError(try WhiskyWineInstaller.install(tarball: badTarball, into: destination))

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: installed.path),
            "A failed extraction must leave the previously installed runtime in place"
        )
        XCTAssertEqual(try stagingLeftovers(in: destination), [])
    }

    func testInstallKeepsExistingRuntimeWhenArchiveHasNoLibraries() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // A well-formed archive that doesn't carry a Libraries/ folder.
        let sourceDir = tempDir.appendingPathComponent("Other")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try Data("marker".utf8).write(to: sourceDir.appendingPathComponent("marker.txt"))
        let tarball = try makeTarball(of: "Other", in: tempDir)

        let destination = tempDir.appendingPathComponent("dest")
        let installed = try makeInstalledRuntime(in: destination)

        XCTAssertThrowsError(try WhiskyWineInstaller.install(tarball: tarball, into: destination)) { error in
            XCTAssertEqual(error as? WhiskyWineInstallError, .runtimeIncomplete)
        }

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: installed.path),
            "An archive without a runtime must not replace the installed one"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Other").path))
        XCTAssertEqual(try stagingLeftovers(in: destination), [])
    }

    func testInstallKeepsExistingRuntimeWhenStagedRuntimeIsIncomplete() throws {
        // An archive with a Libraries/ folder that lacks the version plist or
        // wine64 is not a runtime, and must not replace the working one.
        for (plist, wine64) in [(true, false), (false, true), (false, false)] {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let sourceDir = tempDir.appendingPathComponent("Libraries")
            try makeRuntime(in: sourceDir, plist: plist, wine64: wine64)
            try Data("marker".utf8).write(to: sourceDir.appendingPathComponent("marker.txt"))
            let tarball = try makeTarball(of: "Libraries", in: tempDir)

            let destination = tempDir.appendingPathComponent("dest")
            let installed = try makeInstalledRuntime(in: destination)

            XCTAssertThrowsError(try WhiskyWineInstaller.install(tarball: tarball, into: destination)) { error in
                XCTAssertEqual(error as? WhiskyWineInstallError, .runtimeIncomplete, "plist \(plist), wine64 \(wine64)")
            }

            XCTAssertTrue(FileManager.default.fileExists(atPath: installed.path), "plist \(plist), wine64 \(wine64)")
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: destination.appendingPathComponent("Libraries/marker.txt").path
            ))
            XCTAssertEqual(try stagingLeftovers(in: destination), [])
        }
    }

    func testInstallLeavesNoStagingFoldersAfterSuccess() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tarball = try makeRuntimeTarball(in: tempDir)

        let destination = tempDir.appendingPathComponent("dest")
        _ = try makeInstalledRuntime(in: destination)

        try WhiskyWineInstaller.install(tarball: tarball, into: destination)

        XCTAssertTrue(FileManager.default.fileExists(
            atPath: destination.appendingPathComponent("Libraries/marker.txt").path
        ))
        XCTAssertEqual(try stagingLeftovers(in: destination), [])
    }

    func testInstallRemovesStaleStagingFoldersOnly() throws {
        // A force-quit mid-install leaves its staging folder (and Tar's own,
        // inside it) behind. The next install clears folders it named, and
        // nothing else that merely looks similar.
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tarball = try makeRuntimeTarball(in: tempDir)
        let destination = tempDir.appendingPathComponent("dest")
        _ = try makeInstalledRuntime(in: destination)

        let stale = destination.appendingPathComponent(".runtime-staging-\(UUID().uuidString)")
        let halfExtracted = stale.appendingPathComponent("extracted/.untar-staging-\(UUID().uuidString)/Libraries")
        try FileManager.default.createDirectory(at: halfExtracted, withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: halfExtracted.appendingPathComponent("partial.bin"))
        let lookalikes = [".runtime-staging-notes", ".runtime-staging-\(UUID().uuidString)-copy"]
        for name in lookalikes {
            try FileManager.default.createDirectory(
                at: destination.appendingPathComponent(name),
                withIntermediateDirectories: true
            )
        }

        try WhiskyWineInstaller.install(tarball: tarball, into: destination)

        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path), "A stale staging folder is removed")
        XCTAssertEqual(try stagingLeftovers(in: destination).sorted(), lookalikes.sorted())
    }

    func testInstallRestoresPreviousRuntimeWhenSwapFails() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tarball = try makeRuntimeTarball(in: tempDir)
        let destination = tempDir.appendingPathComponent("dest")
        let installed = try makeInstalledRuntime(in: destination)
        let runtime = destination.appendingPathComponent("Libraries")

        // Only the first move into place (the new runtime) fails.
        var movesIntoPlace = 0
        let moveItem: (URL, URL) throws -> Void = { source, target in
            if target.standardizedFileURL.path == runtime.standardizedFileURL.path {
                movesIntoPlace += 1
                if movesIntoPlace == 1 {
                    throw CocoaError(.fileWriteUnknown)
                }
            }
            try FileManager.default.moveItem(at: source, to: target)
        }

        XCTAssertThrowsError(
            try WhiskyWineInstaller.install(tarball: tarball, into: destination, moveItem: moveItem)
        ) { error in
            XCTAssertEqual((error as? CocoaError)?.code, .fileWriteUnknown)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.path), "The previous runtime is put back")
        XCTAssertEqual(try stagingLeftovers(in: destination), [])
    }

    func testInstallKeepsStagingWhenRestoreFails() throws {
        // If neither the new runtime nor the old one can be moved into place,
        // the staging folder holds the only copy of the previous runtime and
        // must survive the install.
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tarball = try makeRuntimeTarball(in: tempDir)
        let destination = tempDir.appendingPathComponent("dest")
        _ = try makeInstalledRuntime(in: destination)
        let runtime = destination.appendingPathComponent("Libraries")

        XCTAssertThrowsError(try WhiskyWineInstaller.install(
            tarball: tarball,
            into: destination,
            moveItem: failingMoves(into: runtime)
        )) { error in
            XCTAssertEqual(error as? WhiskyWineInstallError, .restoreFailed)
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: runtime.path))
        let kept = try stagingLeftovers(in: destination)
        XCTAssertEqual(kept.count, 1)
        let retired = destination.appendingPathComponent(kept.first ?? "")
            .appendingPathComponent("Libraries.previous/installed.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: retired.path), "Staging keeps the previous runtime")

        // The next install puts the kept runtime back before it extracts, so
        // even an install that then fails leaves the user with a runtime.
        let badTarball = tempDir.appendingPathComponent("bad").appendingPathExtension("tar.gz")
        try Data("not a tarball".utf8).write(to: badTarball)
        XCTAssertThrowsError(try WhiskyWineInstaller.install(tarball: badTarball, into: destination))

        XCTAssertTrue(FileManager.default.fileExists(atPath: runtime.appendingPathComponent("installed.txt").path))
        XCTAssertEqual(try stagingLeftovers(in: destination), [])
    }

    func testStaleCleanupKeepsFolderWhenPreviousRuntimeCannotBeRestored() throws {
        let destination = try makeTempDir()
        let runtime = destination.appendingPathComponent("Libraries")
        let stale = destination.appendingPathComponent(".runtime-staging-\(UUID().uuidString)")
        let retired = stale.appendingPathComponent("Libraries.previous")
        try FileManager.default.createDirectory(at: retired, withIntermediateDirectories: true)

        WhiskyWineInstaller.cleanUpStaleStaging(in: destination, moveItem: failingMoves(into: runtime))

        XCTAssertTrue(FileManager.default.fileExists(atPath: retired.path), "The only copy is never deleted")

        WhiskyWineInstaller.cleanUpStaleStaging(in: destination)

        XCTAssertTrue(FileManager.default.fileExists(atPath: runtime.path), "A later cleanup restores it")
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
    }

    func testNextInstallRestoresPreviousRuntimeWhenLibrariesWasRecreated() throws {
        // Another writer (a GPTK deploy, say) re-creates Libraries/ between the
        // two renames, so neither the new runtime nor the old one can be moved
        // into place. The next install must put the old runtime back over that
        // unusable folder before extracting, not delete it with the staging.
        let tempDir = try makeTempDir()
        let tarball = try makeRuntimeTarball(in: tempDir)
        let destination = tempDir.appendingPathComponent("dest")
        _ = try makeInstalledRuntime(in: destination)
        let runtime = destination.appendingPathComponent("Libraries")
        let recreated = runtime.appendingPathComponent("Wine/lib/external")

        var movesIntoPlace = 0
        let moveItem: (URL, URL) throws -> Void = { source, target in
            if target.standardizedFileURL.path == runtime.standardizedFileURL.path {
                movesIntoPlace += 1
                if movesIntoPlace == 1 {
                    try FileManager.default.createDirectory(at: recreated, withIntermediateDirectories: true)
                }
            }
            try FileManager.default.moveItem(at: source, to: target)
        }

        XCTAssertThrowsError(
            try WhiskyWineInstaller.install(tarball: tarball, into: destination, moveItem: moveItem)
        ) { error in
            XCTAssertEqual(error as? WhiskyWineInstallError, .restoreFailed)
        }
        XCTAssertEqual(try stagingLeftovers(in: destination).count, 1)

        let badTarball = tempDir.appendingPathComponent("bad").appendingPathExtension("tar.gz")
        try Data("not a tarball".utf8).write(to: badTarball)
        XCTAssertThrowsError(try WhiskyWineInstaller.install(tarball: badTarball, into: destination))

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: runtime.appendingPathComponent("installed.txt").path),
            "The previous runtime survives a later failed install"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: recreated.path))
        XCTAssertEqual(try stagingLeftovers(in: destination), [])
    }

    func testStaleCleanupDropsRetiredCopyWhenRuntimeIsUsable() throws {
        let destination = try makeTempDir()
        let runtime = destination.appendingPathComponent("Libraries")
        try makeRuntime(in: runtime, plist: true, wine64: true)
        let stale = destination.appendingPathComponent(".runtime-staging-\(UUID().uuidString)")
        let retired = stale.appendingPathComponent("Libraries.previous")
        try FileManager.default.createDirectory(at: retired, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: retired.appendingPathComponent("old.txt"))

        WhiskyWineInstaller.cleanUpStaleStaging(in: destination)

        XCTAssertTrue(WhiskyWineInstaller.isRuntimePresent(inLibraryFolder: runtime))
        XCTAssertFalse(FileManager.default.fileExists(atPath: runtime.appendingPathComponent("old.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
    }

    func testStaleCleanupKeepsFolderWhenUnusableRuntimeCannotBeMovedAside() throws {
        let destination = try makeTempDir()
        let runtime = destination.appendingPathComponent("Libraries")
        let recreated = runtime.appendingPathComponent("Wine/lib/external")
        try FileManager.default.createDirectory(at: recreated, withIntermediateDirectories: true)
        let stale = destination.appendingPathComponent(".runtime-staging-\(UUID().uuidString)")
        let retired = stale.appendingPathComponent("Libraries.previous")
        try FileManager.default.createDirectory(at: retired, withIntermediateDirectories: true)

        WhiskyWineInstaller.cleanUpStaleStaging(
            in: destination,
            moveItem: failingMoves(into: stale.appendingPathComponent("Libraries.unusable"))
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: retired.path), "The only copy is never deleted")
        XCTAssertTrue(FileManager.default.fileExists(atPath: recreated.path))

        WhiskyWineInstaller.cleanUpStaleStaging(in: destination)

        XCTAssertFalse(FileManager.default.fileExists(atPath: recreated.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: runtime.path), "A later cleanup restores it")
    }

    /// A mover that refuses every move into `target`, and performs the rest.
    private func failingMoves(into target: URL) -> (URL, URL) throws -> Void {
        { source, destination in
            if destination.standardizedFileURL.path == target.standardizedFileURL.path {
                throw CocoaError(.fileWriteNoPermission)
            }
            try FileManager.default.moveItem(at: source, to: destination)
        }
    }

    /// Gzip-tars a minimal usable runtime (version plist, `wine64`, and a
    /// `marker.txt`) as `Libraries/`, the way the runtime archive ships.
    private func makeRuntimeTarball(in directory: URL) throws -> URL {
        let sourceDir = directory.appendingPathComponent("Libraries")
        try makeRuntime(in: sourceDir, plist: true, wine64: true)
        try Data("marker".utf8).write(to: sourceDir.appendingPathComponent("marker.txt"))
        return try makeTarball(of: "Libraries", in: directory)
    }

    /// Gzip-tars `folder` (a child of `directory`) the way the runtime archive ships.
    private func makeTarball(of folder: String, in directory: URL) throws -> URL {
        let tarball = directory.appendingPathComponent("archive").appendingPathExtension("tar.gz")
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.currentDirectoryURL = directory
        tar.arguments = ["-czf", tarball.path, folder]
        try tar.run()
        tar.waitUntilExit()
        try XCTSkipUnless(tar.terminationStatus == 0, "Could not build the tar fixture")
        return tarball
    }

    /// Creates `destination/Libraries/installed.txt`, standing in for a working runtime.
    private func makeInstalledRuntime(in destination: URL) throws -> URL {
        let installed = destination.appendingPathComponent("Libraries/installed.txt")
        try FileManager.default.createDirectory(
            at: installed.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("installed".utf8).write(to: installed)
        return installed
    }

    /// Hidden staging folders the install or untar left behind in `destination`.
    private func stagingLeftovers(in destination: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: destination.path)
            .filter { $0.hasPrefix(".runtime-staging-") || $0.hasPrefix(".untar-staging-") }
    }
}

// MARK: - SHA-256 Integrity Tests

final class WhiskyWineInstallerSHA256Tests: XCTestCase {
    /// Writes `data` to a unique temp file and returns its URL, registering
    /// cleanup with the test case.
    private func writeTempFile(_ data: Data, file: StaticString = #filePath, line: UInt = #line) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("bin")
        do {
            try data.write(to: url)
        } catch {
            XCTFail("Failed to write temp file: \(error)", file: file, line: line)
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testSHA256OfKnownVector() {
        // NIST FIPS 180-4 test vector: SHA-256("abc").
        let url = writeTempFile(Data("abc".utf8))
        XCTAssertEqual(
            WhiskyWineInstaller.sha256(ofFileAt: url),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func testSHA256OfEmptyFile() {
        // Well-known digest of the empty input.
        let url = writeTempFile(Data())
        XCTAssertEqual(
            WhiskyWineInstaller.sha256(ofFileAt: url),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
    }

    func testSHA256MatchesOneShotForMultiChunkFile() {
        // Larger than the 1 MiB streaming chunk so the read loop runs several
        // iterations and crosses a chunk boundary. Cross-checked against
        // CryptoKit's one-shot hash of the same bytes (not a circular check of
        // the streaming code against itself).
        let byteCount = 3 * (1 << 20) + 7
        let bytes: [UInt8] = (0 ..< byteCount).map { UInt8($0 & 0xFF) }
        let data = Data(bytes)
        let expected = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

        let url = writeTempFile(data)
        XCTAssertEqual(WhiskyWineInstaller.sha256(ofFileAt: url), expected)
    }

    func testSHA256OfMissingFileReturnsNil() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("bin")
        XCTAssertNil(WhiskyWineInstaller.sha256(ofFileAt: missing))
    }

    private let abcDigest = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

    func testIntegrityResultMatch() {
        let url = writeTempFile(Data("abc".utf8))
        XCTAssertEqual(
            WhiskyWineInstaller.integrityResult(forFileAt: url, expectedSHA256: abcDigest),
            .match
        )
    }

    func testIntegrityResultIsCaseInsensitive() {
        // The advertised digest may be uppercase; comparison must not care.
        let url = writeTempFile(Data("abc".utf8))
        XCTAssertEqual(
            WhiskyWineInstaller.integrityResult(forFileAt: url, expectedSHA256: abcDigest.uppercased()),
            .match
        )
    }

    func testIntegrityResultMismatchCarriesActualDigest() {
        // A mismatch must report the real digest so diagnostics can distinguish
        // a corrupted download from a wrongly published hash.
        let url = writeTempFile(Data("abc".utf8))
        XCTAssertEqual(
            WhiskyWineInstaller.integrityResult(
                forFileAt: url,
                expectedSHA256: "0000000000000000000000000000000000000000000000000000000000000000"
            ),
            .mismatch(actual: abcDigest)
        )
    }

    func testIntegrityResultUnreadableForMissingFile() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("bin")
        XCTAssertEqual(
            WhiskyWineInstaller.integrityResult(forFileAt: missing, expectedSHA256: abcDigest),
            .unreadable
        )
    }
}
