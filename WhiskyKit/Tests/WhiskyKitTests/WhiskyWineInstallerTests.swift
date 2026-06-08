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
}
