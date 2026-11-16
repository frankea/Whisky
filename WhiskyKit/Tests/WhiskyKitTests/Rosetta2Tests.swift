//
//  Rosetta2Tests.swift
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
@testable import WhiskyKit
import XCTest

final class Rosetta2Tests: XCTestCase {
    // MARK: - isRosettaInstalled Property Tests

    func testIsRosettaInstalledReturnsBool() {
        // Verify the property returns a boolean value (true or false depending on system state)
        let result = Rosetta2.isRosettaInstalled
        XCTAssertNotNil(result)
        // Result will be true on Intel Macs or Apple Silicon with Rosetta installed,
        // false on Apple Silicon without Rosetta
        XCTAssertTrue(result == true || result == false)
    }

    func testIsRosettaInstalledIsConsistent() {
        // The property should return the same value on repeated calls
        let result1 = Rosetta2.isRosettaInstalled
        let result2 = Rosetta2.isRosettaInstalled
        let result3 = Rosetta2.isRosettaInstalled

        XCTAssertEqual(result1, result2)
        XCTAssertEqual(result2, result3)
    }

    func testIsRosettaInstalledChecksCorrectPath() {
        // The Rosetta runtime should be at the standard Apple location
        let rosettaPath = "/Library/Apple/usr/libexec/oah/libRosettaRuntime"
        let fileExists = FileManager.default.fileExists(atPath: rosettaPath)

        // isRosettaInstalled should match whether the file exists
        XCTAssertEqual(Rosetta2.isRosettaInstalled, fileExists)
    }

    func testRuntimeLookupIsLiveNotCached() throws {
        // A macOS update can remove Rosetta and the user can reinstall it while
        // the app runs, so each read has to reflect the file as it is now.
        let runtime = try makeTempDir().appending(path: "libRosettaRuntime")
        Rosetta2.runtimePath = runtime.path(percentEncoded: false)
        defer { Rosetta2.runtimePath = Rosetta2.rosetta2RuntimeBin }
        XCTAssertFalse(Rosetta2.isRosettaInstalled)

        try Data("x".utf8).write(to: runtime)
        XCTAssertTrue(Rosetta2.isRosettaInstalled)

        try FileManager.default.removeItem(at: runtime)
        XCTAssertFalse(Rosetta2.isRosettaInstalled)
    }

    // MARK: - installRosetta API Contract Tests

    /// Verifies that the installRosetta method has the expected API contract.
    ///
    /// Note: We cannot actually test installRosetta() because:
    /// 1. It would attempt to install system software
    /// 2. It requires admin privileges
    /// 3. It depends on Wine.makeFileHandle() and process execution
    ///
    /// This test verifies the API signature is maintained.
    func testInstallRosettaAPIContract() {
        // Verify the method exists and has the correct signature:
        // async throws -> Bool
        let methodReference: () async throws -> Bool = Rosetta2.installRosetta
        XCTAssertNotNil(methodReference)
    }
}
