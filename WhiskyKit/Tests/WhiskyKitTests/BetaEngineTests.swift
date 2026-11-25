//
//  BetaEngineTests.swift
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

import SemanticVersion
@testable import WhiskyKit
import XCTest

final class BetaEngineTests: XCTestCase {
    private let digestA = String(repeating: "a", count: 64)
    private let digestB = String(repeating: "b", count: 64)

    /// One release in the shape `GET /repos/{owner}/{repo}/releases` returns.
    private func release(
        tag: String,
        prerelease: Bool = true,
        draft: Bool = false,
        asset: String = "Libraries.tar.gz",
        digest: String? = nil
    ) -> [String: Any] {
        var assetJSON: [String: Any] = [
            "name": asset,
            "browser_download_url": "https://github.com/frankea/Whisky/releases/download/\(tag)/\(asset)"
        ]
        if let digest {
            assetJSON["digest"] = digest
        }
        return [
            "tag_name": tag,
            "prerelease": prerelease,
            "draft": draft,
            "html_url": "https://github.com/frankea/Whisky/releases/tag/\(tag)",
            "assets": [assetJSON]
        ]
    }

    private func listing(_ releases: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: releases)
    }

    // MARK: - Picking the beta

    func testPicksNewestBetaAboveStable() throws {
        let data = try listing([
            release(tag: "app-v3.10.3", prerelease: false),
            release(tag: "v4.8.5-beta.1", digest: "sha256:\(digestA)"),
            release(tag: "v4.8.4-beta.1", digest: "sha256:\(digestB)"),
            release(tag: "v4.8.3", prerelease: false, digest: "sha256:\(digestB)")
        ])
        let beta = BetaEngine.latestBeta(inReleasesJSON: data, newerThan: SemanticVersion(4, 8, 3))
        XCTAssertEqual(beta?.tag, "v4.8.5-beta.1")
        XCTAssertEqual(beta?.version, SemanticVersion(4, 8, 5, "beta.1"))
        XCTAssertEqual(beta?.sha256, digestA)
        XCTAssertEqual(
            beta?.downloadURL.absoluteString,
            "https://github.com/frankea/Whisky/releases/download/v4.8.5-beta.1/Libraries.tar.gz"
        )
        XCTAssertEqual(beta?.notesURL.absoluteString, "https://github.com/frankea/Whisky/releases/tag/v4.8.5-beta.1")
    }

    func testOrderComesFromVersionsNotListingOrder() throws {
        let data = try listing([
            release(tag: "v4.8.4-beta.1", digest: "sha256:\(digestA)"),
            release(tag: "v4.8.5-beta.2", digest: "sha256:\(digestA)"),
            release(tag: "v4.8.5-beta.10", digest: "sha256:\(digestA)")
        ])
        let beta = BetaEngine.latestBeta(inReleasesJSON: data, newerThan: SemanticVersion(4, 8, 3))
        XCTAssertEqual(beta?.tag, "v4.8.5-beta.10")
    }

    func testBetaOfThePromotedVersionIsNotOffered() throws {
        // 4.8.5-beta.1 sorts below 4.8.5, so once 4.8.5 is stable nobody is
        // offered the beta it came from.
        let data = try listing([release(tag: "v4.8.5-beta.1", digest: "sha256:\(digestA)")])
        XCTAssertNil(BetaEngine.latestBeta(inReleasesJSON: data, newerThan: SemanticVersion(4, 8, 5)))
        XCTAssertNil(BetaEngine.latestBeta(inReleasesJSON: data, newerThan: SemanticVersion(4, 9, 0)))
    }

    func testSkipsReleasesThatAreNotInstallableBetas() throws {
        let data = try listing([
            release(tag: "v4.9.0-beta.1", draft: true, digest: "sha256:\(digestA)"),
            release(tag: "v4.9.0", prerelease: false, digest: "sha256:\(digestA)"),
            release(tag: "app-v3.11.0-beta.1", digest: "sha256:\(digestA)"),
            release(tag: "v4.9.1-beta.1", asset: "Whisky.dmg", digest: "sha256:\(digestA)"),
            release(tag: "v4.9.2-beta.1"),
            release(tag: "v4.9.3-beta.1", digest: "md5:\(digestA)"),
            release(tag: "v4.9.4-beta.1", digest: "sha256:abc"),
            release(tag: "v4.9.5", digest: "sha256:\(digestA)")
        ])
        XCTAssertNil(BetaEngine.latestBeta(inReleasesJSON: data, newerThan: SemanticVersion(4, 8, 3)))
    }

    func testMalformedListingYieldsNil() {
        XCTAssertNil(BetaEngine.latestBeta(inReleasesJSON: Data("{}".utf8), newerThan: SemanticVersion(4, 8, 3)))
        XCTAssertNil(BetaEngine.latestBeta(inReleasesJSON: Data(), newerThan: SemanticVersion(4, 8, 3)))
    }

    func testDigestIsLowercased() {
        XCTAssertEqual(BetaEngine.sha256(fromDigest: "sha256:\(digestA.uppercased())"), digestA)
    }

    func testVersionFromTag() {
        XCTAssertEqual(BetaEngine.version(fromTag: "v4.8.5-beta.1"), SemanticVersion(4, 8, 5, "beta.1"))
        XCTAssertEqual(BetaEngine.version(fromTag: "v4.8.3"), SemanticVersion(4, 8, 3))
        XCTAssertNil(BetaEngine.version(fromTag: "app-v3.10.3"))
        XCTAssertNil(BetaEngine.version(fromTag: "4.8.3"))
    }

    // MARK: - Installed record

    private func tempFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "BetaEngineTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func betaRelease() throws -> EngineRelease {
        try EngineRelease(
            tag: "v4.8.5-beta.1",
            version: XCTUnwrap(SemanticVersion("4.8.5-beta.1")),
            downloadURL: XCTUnwrap(URL(string: "https://example.com/Libraries.tar.gz")),
            sha256: digestA,
            notesURL: XCTUnwrap(URL(string: "https://example.com/notes"))
        )
    }

    func testRecordRoundTrips() throws {
        let folder = try tempFolder()
        XCTAssertNil(BetaEngine.installedBeta(inLibraryFolder: folder))

        try BetaEngine.recordInstalled(betaRelease(), inLibraryFolder: folder)
        let record = BetaEngine.installedBeta(inLibraryFolder: folder)
        XCTAssertEqual(record?.tag, "v4.8.5-beta.1")
        XCTAssertEqual(record?.notesURL.absoluteString, "https://example.com/notes")
        XCTAssertEqual(record?.version, SemanticVersion(4, 8, 5, "beta.1"))
    }

    func testInstallingAnotherEngineDropsTheRecord() throws {
        // The record lives inside Libraries, which every install replaces, so
        // a switch back to stable (or any update) leaves no stale beta behind.
        let root = try tempFolder()
        let libraries = root.appending(path: "Libraries")
        try writeRuntime(into: libraries, version: "4.8.5")
        try BetaEngine.recordInstalled(betaRelease(), inLibraryFolder: libraries)
        XCTAssertNotNil(BetaEngine.installedBeta(inLibraryFolder: libraries))

        let source = root.appending(path: "source")
        try writeRuntime(into: source.appending(path: "Libraries"), version: "4.8.3")
        let tarball = root.appending(path: "Libraries.tar.gz")
        try Tar.tar(folder: source.appending(path: "Libraries"), toURL: tarball)
        try WhiskyWineInstaller.install(tarball: tarball, into: root)

        XCTAssertTrue(WhiskyWineInstaller.isRuntimePresent(inLibraryFolder: libraries))
        XCTAssertNil(BetaEngine.installedBeta(inLibraryFolder: libraries))
    }

    func testSupersededOnceStableCarriesTheBeta() {
        let record = InstalledBetaRecord(
            tag: "v4.8.5-beta.1",
            notesURL: URL(fileURLWithPath: "/")
        )
        XCTAssertFalse(record.isSuperseded(byStable: SemanticVersion(4, 8, 3)))
        XCTAssertTrue(record.isSuperseded(byStable: SemanticVersion(4, 8, 5)))
        XCTAssertTrue(record.isSuperseded(byStable: SemanticVersion(4, 9, 0)))
    }

    private func writeRuntime(into libraries: URL, version: String) throws {
        let bin = libraries.appending(path: "Wine").appending(path: "bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try Data().write(to: bin.appending(path: "wine64"))
        let info = try WhiskyWineVersion(version: XCTUnwrap(SemanticVersion(version)))
        try PropertyListEncoder().encode(info)
            .write(to: libraries.appending(path: "WhiskyWineVersion").appendingPathExtension("plist"))
    }
}
