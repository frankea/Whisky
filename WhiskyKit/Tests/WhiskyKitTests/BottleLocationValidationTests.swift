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

        // The carried path must be the original target the user chose (it is
        // shown to them), not the nearest existing ancestor that was probed.
        guard case let .notWritable(path) = BottleLocationValidation.validate(at: target, minimumFreeBytes: 0) else {
            return XCTFail("Expected .notWritable for a read-only directory")
        }
        XCTAssertEqual(path, target.path(percentEncoded: false))
    }

    func testNotWritableWhenNearestAncestorIsRegularFile() throws {
        // If the walk-up lands on a regular file (a malformed location), the
        // probe write fails and the result is .notWritable rather than a crash.
        let file = tempDir.appendingPathComponent("not-a-directory")
        try Data("x".utf8).write(to: file)
        let target = file.appendingPathComponent("bottle")

        guard case .notWritable = BottleLocationValidation.validate(at: target, minimumFreeBytes: 0) else {
            return XCTFail("Expected .notWritable when the nearest ancestor is a regular file")
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

    // MARK: - Against a real volume

    /// Opt-in, because it needs a volume the machine running the suite may not
    /// have. Point `WHISKY_TEST_VOLUME` at a mounted external or network volume
    /// to check the classification against the real thing rather than a temp
    /// directory on the boot disk:
    ///
    ///     WHISKY_TEST_VOLUME=/Volumes/MyDrive swift test
    ///
    /// A disk image works: `hdiutil create -size 50m -fs APFS -volname T t.dmg`
    /// then `hdiutil attach t.dmg` mounts as External/Removable.
    func testRealExternalVolumeIsConsentGated() throws {
        guard let path = ProcessInfo.processInfo.environment["WHISKY_TEST_VOLUME"] else {
            throw XCTSkip("set WHISKY_TEST_VOLUME to a mounted external volume")
        }
        let volume = URL(fileURLWithPath: path)
        XCTAssertTrue(
            BottleLocationValidation.isConsentGatedVolume(volume),
            "\(path) should be consent gated; is it actually external or a network mount?"
        )
    }

    /// The distinction the UI hangs on: on a consent-gated volume a permission
    /// refusal is `.accessDenied` (privacy can fix it), and anything else is
    /// `.notWritable` (privacy cannot).
    func testRealExternalVolumeRefusalIsAccessDenied() throws {
        guard let path = ProcessInfo.processInfo.environment["WHISKY_TEST_VOLUME"] else {
            throw XCTSkip("set WHISKY_TEST_VOLUME to a mounted external volume")
        }
        let volume = URL(fileURLWithPath: path)
        let locked = volume.appendingPathComponent("whisky-denied-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            try? FileManager.default.removeItem(at: locked)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: locked.path)

        XCTAssertEqual(BottleLocationValidation.probeWrite(in: locked, fileManager: .default), .denied)
        guard case .accessDenied = BottleLocationValidation.validate(at: locked, minimumFreeBytes: 0) else {
            return XCTFail("a permission refusal on a consent gated volume must be .accessDenied")
        }
    }

    func testRealExternalVolumeWritesCleanly() throws {
        guard let path = ProcessInfo.processInfo.environment["WHISKY_TEST_VOLUME"] else {
            throw XCTSkip("set WHISKY_TEST_VOLUME to a mounted external volume")
        }
        let dir = URL(fileURLWithPath: path).appendingPathComponent("whisky-ok-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertEqual(BottleLocationValidation.validate(at: dir, minimumFreeBytes: 0), .valid)
    }

    // MARK: - Permission-shaped refusals

    /// The privacy pointer must only appear for a refusal privacy can explain.
    /// An unwritable folder on the internal disk is the same errno with a
    /// different fix, so it stays `.notWritable`.
    func testUnwritableInternalDirectoryIsNotReportedAsAccessDenied() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: tempDir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDir.path) }

        guard case .notWritable = BottleLocationValidation.validate(at: tempDir, minimumFreeBytes: 0) else {
            return XCTFail("an internal volume can never be a consent problem")
        }
    }

    func testProbeReportsDeniedForAPermissionRefusal() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: tempDir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDir.path) }

        XCTAssertEqual(BottleLocationValidation.probeWrite(in: tempDir, fileManager: .default), .denied)
    }

    func testProbeSucceedsOnAWritableDirectory() {
        XCTAssertEqual(BottleLocationValidation.probeWrite(in: tempDir, fileManager: .default), .succeeded)
    }

    func testProbeLeavesNothingBehind() throws {
        XCTAssertEqual(BottleLocationValidation.probeWrite(in: tempDir, fileManager: .default), .succeeded)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: tempDir.path), [])
    }

    func testProbeReportsFailedWhenTheTargetIsNotADirectory() throws {
        let file = tempDir.appendingPathComponent("a-file")
        try Data("x".utf8).write(to: file)
        // ENOTDIR, not a permission problem, so it must not read as a refusal.
        XCTAssertEqual(BottleLocationValidation.probeWrite(in: file, fileManager: .default), .failed)
    }

    func testInternalVolumeIsNotConsentGated() {
        XCTAssertFalse(BottleLocationValidation.isConsentGatedVolume(tempDir))
    }

    func testNearestExistingDirectoryWalksUpToFirstExistingParent() {
        let deep = tempDir.appendingPathComponent("a/b/c")
        let nearest = BottleLocationValidation.nearestExistingDirectory(for: deep, fileManager: .default)
        XCTAssertEqual(nearest.path, tempDir.resolvingSymlinksInPath().path)
    }
}
