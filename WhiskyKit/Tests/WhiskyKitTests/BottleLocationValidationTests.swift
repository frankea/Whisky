//
//  BottleLocationValidationTests.swift
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

@testable import WhiskyKit
import XCTest

final class BottleLocationValidationTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            // Restore writability before removal in case a test made it read-only.
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDir.path)
            try? FileManager.default.removeItem(at: tempDir)
        }
        tempDir = nil
    }

    func testValidForWritableDirectoryWithSpace() {
        XCTAssertEqual(BottleLocationValidation.validate(at: tempDir, minimumFreeBytes: 0), .valid)
    }

    func testValidForNonexistentSubdirectoryOfWritableParent() {
        // Mirrors first-run: the chosen parent (e.g. .../Bottles) doesn't exist
        // yet, so the validator must probe the nearest existing ancestor.
        let subdir = tempDir.appendingPathComponent("Bottles")
        XCTAssertEqual(BottleLocationValidation.validate(at: subdir, minimumFreeBytes: 0), .valid)
    }

    func testNotWritableForReadOnlyDirectory() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: tempDir.path)
        let target = tempDir.appendingPathComponent("bottle")

        guard case .notWritable = BottleLocationValidation.validate(at: target, minimumFreeBytes: 0) else {
            return XCTFail("Expected .notWritable for a read-only directory")
        }
    }

    func testInsufficientSpaceWhenFloorExceedsCapacity() {
        let result = BottleLocationValidation.validate(at: tempDir, minimumFreeBytes: .max)

        guard case let .insufficientSpace(available, required) = result else {
            return XCTFail("Expected .insufficientSpace, got \(result)")
        }
        XCTAssertEqual(required, .max)
        XCTAssertGreaterThanOrEqual(available, 0)
    }

    func testNearestExistingDirectoryWalksUpToFirstExistingParent() {
        let deep = tempDir.appendingPathComponent("a/b/c")
        let nearest = BottleLocationValidation.nearestExistingDirectory(for: deep, fileManager: .default)
        XCTAssertEqual(nearest.path, tempDir.resolvingSymlinksInPath().path)
    }
}
