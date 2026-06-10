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

import CryptoKit
import SemanticVersion
@testable import WhiskyKit
import XCTest

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

        // Build a tiny source tree and gzip-tar it the way the runtime archive ships.
        let sourceDir = tempDir.appendingPathComponent("Libraries")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try Data("marker".utf8).write(to: sourceDir.appendingPathComponent("marker.txt"))

        let tarball = tempDir.appendingPathComponent("archive").appendingPathExtension("tar.gz")
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.currentDirectoryURL = tempDir
        tar.arguments = ["-czf", tarball.path, "Libraries"]
        try tar.run()
        tar.waitUntilExit()
        try XCTSkipUnless(tar.terminationStatus == 0, "Could not build the tar fixture")

        let destination = tempDir.appendingPathComponent("dest")
        try WhiskyWineInstaller.install(tarball: tarball, into: destination)

        let extracted = destination.appendingPathComponent("Libraries/marker.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: extracted.path))
    }

    func testInstallReplacesExistingDestinationContents() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceDir = tempDir.appendingPathComponent("Libraries")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try Data("marker".utf8).write(to: sourceDir.appendingPathComponent("marker.txt"))

        let tarball = tempDir.appendingPathComponent("archive").appendingPathExtension("tar.gz")
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.currentDirectoryURL = tempDir
        tar.arguments = ["-czf", tarball.path, "Libraries"]
        try tar.run()
        tar.waitUntilExit()
        try XCTSkipUnless(tar.terminationStatus == 0, "Could not build the tar fixture")

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
