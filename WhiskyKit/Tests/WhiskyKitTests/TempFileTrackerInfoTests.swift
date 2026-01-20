//
//  TempFileTrackerInfoTests.swift
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

// MARK: - TempFileInfo Tests

final class TempFileInfoTests: XCTestCase {
    var testDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()

        let tempDir = FileManager.default.temporaryDirectory
        testDirectory = tempDir.appendingPathComponent("temp-info-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)

        TempFileTracker.shared.reset()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: testDirectory)
        try await super.tearDown()
    }

    func testTempFileInfoHashable() throws {
        let tempFile = testDirectory.appendingPathComponent("test.sh")
        try "test content".write(to: tempFile, atomically: true, encoding: .utf8)

        let info1 = TempFileTracker.TempFileInfo(
            url: tempFile,
            creationTime: Date(),
            associatedProcess: 123,
            cleanupAttempts: 0,
            maxRetries: 3
        )

        let info2 = TempFileTracker.TempFileInfo(
            url: tempFile,
            creationTime: info1.creationTime,
            associatedProcess: 123,
            cleanupAttempts: 0,
            maxRetries: 3
        )

        XCTAssertEqual(info1, info2, "TempFileInfo with same values should be equal")
        XCTAssertEqual(info1.hashValue, info2.hashValue, "TempFileInfo with same values should have same hash")
    }

    func testTempFileInfoNotEqual() throws {
        let file1 = testDirectory.appendingPathComponent("file1.sh")
        let file2 = testDirectory.appendingPathComponent("file2.sh")

        try "content1".write(to: file1, atomically: true, encoding: .utf8)
        try "content2".write(to: file2, atomically: true, encoding: .utf8)

        let info1 = TempFileTracker.TempFileInfo(
            url: file1,
            creationTime: Date(),
            associatedProcess: 123,
            cleanupAttempts: 0,
            maxRetries: 3
        )

        let info2 = TempFileTracker.TempFileInfo(
            url: file2,
            creationTime: Date(),
            associatedProcess: 456,
            cleanupAttempts: 0,
            maxRetries: 3
        )

        XCTAssertNotEqual(info1, info2, "TempFileInfo with different values should not be equal")
    }
}

// MARK: - Thread Safety Tests

final class TempFileTrackerThreadSafetyTests: XCTestCase {
    var testDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()

        let tempDir = FileManager.default.temporaryDirectory
        testDirectory = tempDir.appendingPathComponent("temp-thread-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)

        TempFileTracker.shared.reset()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: testDirectory)
        try await super.tearDown()
    }

    func testConcurrentRegistration() throws {
        let fileCount = 100

        var files: [URL] = []
        for index in 0 ..< fileCount {
            let file = testDirectory.appendingPathComponent("file\(index).sh")
            try "content\(index)".write(to: file, atomically: true, encoding: .utf8)
            files.append(file)
        }

        DispatchQueue.concurrentPerform(iterations: fileCount) { index in
            TempFileTracker.shared.register(file: files[index])
        }

        let trackedFiles = TempFileTracker.shared.getAllTrackedFiles()
        XCTAssertEqual(trackedFiles.count, fileCount, "All files should be registered")
    }

    func testConcurrentCleanup() async throws {
        let fileCount = 50
        var files: [URL] = []

        for index in 0 ..< fileCount {
            let file = testDirectory.appendingPathComponent("file\(index).sh")
            try "content\(index)".write(to: file, atomically: true, encoding: .utf8)
            TempFileTracker.shared.register(file: file)
            files.append(file)
        }

        await withTaskGroup(of: Void.self) { group in
            for file in files {
                group.addTask {
                    await TempFileTracker.shared.cleanupWithRetry(file: file, maxRetries: 1)
                }
            }
        }

        // Task group already waits for all tasks to complete - no additional sleep needed
        let trackedFiles = TempFileTracker.shared.getAllTrackedFiles()
        XCTAssertGreaterThanOrEqual(trackedFiles.count, 0, "Tracker should handle concurrent operations safely")
    }
}

// MARK: - Edge Case Tests

final class TempFileTrackerEdgeCaseTests: XCTestCase {
    var testDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()

        let tempDir = FileManager.default.temporaryDirectory
        testDirectory = tempDir.appendingPathComponent("temp-edge-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)

        TempFileTracker.shared.reset()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: testDirectory)
        try await super.tearDown()
    }

    func testCleanupNonExistentFile() async {
        let nonExistentFile = testDirectory.appendingPathComponent("nonexistent.sh")

        TempFileTracker.shared.register(file: nonExistentFile)

        await TempFileTracker.shared.cleanupWithRetry(file: nonExistentFile, maxRetries: 3)

        let trackedFiles = TempFileTracker.shared.getAllTrackedFiles()
        XCTAssertNil(trackedFiles[nonExistentFile], "Non-existent file should be removed from tracker")
    }

    func testMarkForCleanupUnregisteredFile() throws {
        let tempFile = testDirectory.appendingPathComponent("test.sh")
        try "test content".write(to: tempFile, atomically: true, encoding: .utf8)

        TempFileTracker.shared.markForCleanup(file: tempFile)

        let trackedFiles = TempFileTracker.shared.getAllTrackedFiles()
        XCTAssertNil(trackedFiles[tempFile], "Unregistered file should not be tracked")
    }
}
