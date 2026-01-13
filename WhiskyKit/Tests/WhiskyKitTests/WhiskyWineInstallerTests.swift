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

import Foundation
import SemanticVersion
@testable import WhiskyKit
import XCTest

final class WhiskyWineInstallerTests: XCTestCase {
    func testLocateExtractedLibrariesFolderFindsVersionFileParent() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("whisky-installer-test-\(UUID().uuidString)")
        let libraries = root.appendingPathComponent("SomeRoot").appendingPathComponent("Libraries")
        try fileManager.createDirectory(at: libraries, withIntermediateDirectories: true)

        // Create a valid WhiskyWineVersion.plist in Libraries/
        let version = WhiskyWineVersion(version: SemanticVersion(2, 5, 0))
        let data = try PropertyListEncoder().encode(version)
        let versionPlist = libraries.appendingPathComponent("WhiskyWineVersion").appendingPathExtension("plist")
        try data.write(to: versionPlist)

        defer { try? fileManager.removeItem(at: root) }

        let found = WhiskyWineInstaller.locateExtractedLibrariesFolder(in: root)
        XCTAssertEqual(found?.standardizedFileURL.path, libraries.standardizedFileURL.path)
    }

    func testDecodeWhiskyWineVersionDecodesValidPlist() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("whisky-installer-test-\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let version = WhiskyWineVersion(version: SemanticVersion(2, 5, 0))
        let data = try PropertyListEncoder().encode(version)
        let plist = root.appendingPathComponent("WhiskyWineVersion").appendingPathExtension("plist")
        try data.write(to: plist)

        let decoded = try WhiskyWineInstaller.decodeWhiskyWineVersion(from: plist)
        XCTAssertEqual(decoded, SemanticVersion(2, 5, 0))
    }
}
