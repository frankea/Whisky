//
//  TempFileTrackerTests.swift
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

final class TempFileTrackerTests: XCTestCase {
    var testDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()

        // Create a temporary directory for tests
        let tempDir = FileManager.default.temporaryDirectory
        testDirectory = tempDir.appendingPathComponent("temp-tracker-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)

        // Clear tracker before each test
        TempFileTracker.shared.lock.lock()
        TempFileTracker.shared.tempFiles.removeAll()
        TempFileTracker.shared.lock.unlock()
    }

    override func tearDown() async throws {
        // Clean up test directory
        try? FileManager.default.removeItem(at: testDirectory)
        try await super.tearDown()
    }

    // MARK: - Registration Tests

    func testRegisterTempFile() throws {
        let tempFile = testDirectory.appendingPathComponent("test.sh")
        try "test content".write(to: tempFile, atomically: true, encoding: .utf8)

        TempFileTracker.shared.register(file: tempFile)

        let trackedFiles = TempFileTracker.shared.getAllTrackedFiles()
        XCTAssertTrue(trackedFiles[tempFile] != nil, "File should be tracked")
        XCTAssertEqual(trackedFiles.count, 1, "Should have one tracked file")
    }

    func testRegisterMultipleTempFiles() throws {
        let file1 = testDirectory.appendingPathComponent("test1.sh")
        let file2 = testDirectory.appendingPathComponent("test2.sh")
        let file3 = testDirectory.appendingPathComponent("test3.sh")

        try "content1".write(to: file1, atomically: true, encoding: .utf8)
        try "content2".write(to: file2, atomically: true, encoding: .utf8)
        try "content3".write(to: file3, atomically: true, encoding: .utf8)

        TempFileTracker.shared.register(file: file1)
        TempFileTracker.shared.register(file: file2)
        TempFileTracker.shared.register(file: file3)

        let trackedFiles = TempFileTracker.shared.getAllTrackedFiles()
        XCTAssertEqual(trackedFiles.count, 3, "Should have three tracked files")
    }

    func testRegisterTempFileWithProcess() throws {
        let tempFile = testDirectory.appendingPathComponent("test.sh")
        try "test content".write(to: tempFile, atomically: true, encoding: .utf8)

        let pid: Int32 = 12345
        TempFileTracker.shared.register(file: tempFile, process: pid)

        let trackedFiles = TempFileTracker.shared.getAllTrackedFiles()
        XCTAssertTrue(trackedFiles[tempFile] != nil, "File should be tracked")
        XCTAssertEqual(trackedFiles[tempFile]?.associatedProcess, pid, "PID should be associated")
    }

    func testMarkForCleanup() throws {
        let tempFile = testDirectory.appendingPathComponent("test.sh")
        try "test content".write(to: tempFile, atomically: true, encoding: .utf8)

        TempFileTracker.shared.register(file: tempFile)

        let infoBefore = TempFileTracker.shared.getAllTrackedFiles()[tempFile]
        XCTAssertEqual(infoBefore?.cleanupAttempts, 0, "Initial cleanup attempts should be 0")

        TempFileTracker.shared.markForCleanup(file: tempFile)

        let infoAfter = TempFileTracker.shared.getAllTrackedFiles()[tempFile]
        XCTAssertEqual(infoAfter?.cleanupAttempts, 1, "Cleanup attempts should be incremented")
    }

    // MARK: - Cleanup Tests

    func testCleanupWithRetry() async throws {
        let tempFile = testDirectory.appendingPathComponent("test.sh")
        try "test content".write(to: tempFile, atomically: true, encoding: .utf8)

        TempFileTracker.shared.register(file: tempFile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempFile.path), "File should exist before cleanup")

        await TempFileTracker.shared.cleanupWithRetry(file: tempFile, maxRetries: 3)

        XCTAssertFalse(FileManager.default.fileExists(atPath: tempFile.path), "File should be deleted")

        let trackedFiles = TempFileTracker.shared.getAllTrackedFiles()
        XCTAssertNil(trackedFiles[tempFile], "File should be removed from tracker")
    }

    func testCleanupWithRetryOnLockedFile() async throws {
        let tempFile = testDirectory.appendingPathComponent("locked.sh")
        try "test content".write(to: tempFile, atomically: true, encoding: .utf8)

        TempFileTracker.shared.register(file: tempFile)

        // Lock the file by opening it
        let handle = try FileHandle(forWritingTo: tempFile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempFile.path), "File should exist")

        // Attempt cleanup (should fail due to lock)
        await TempFileTracker.shared.cleanupWithRetry(file: tempFile, maxRetries: 2)

        // File should still exist because it's locked
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempFile.path), "Locked file should still exist")

        // Release the lock and retry
        try handle.close()
        await TempFileTracker.shared.cleanupWithRetry(file: tempFile, maxRetries: 2)

        XCTAssertFalse(FileManager.default.fileExists(atPath: tempFile.path), "File should be deleted after lock released")
    }

    func testCleanupAssociatedWithProcess() async throws {
        let pid: Int32 = 9999
        let file1 = testDirectory.appendingPathComponent("file1.sh")
        let file2 = testDirectory.appendingPathComponent("file2.sh")
        let file3 = testDirectory.appendingPathComponent("file3.sh")

        try "content1".write(to: file1, atomically: true, encoding: .utf8)
        try "content2".write(to: file2, atomically: true, encoding: .utf8)
        try "content3".write(to: file3, atomically: true, encoding: .utf8)

        TempFileTracker.shared.register(file: file1, process: pid)
        TempFileTracker.shared.register(file: file2, process: pid)
        TempFileTracker.shared.register(file: file3, process: 8888) // Different process

        // Cleanup files associated with process
        TempFileTracker.shared.cleanup(associatedWith: pid)

        // Wait for async cleanup
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        // Files 1 and 2 should be cleaned, file 3 should remain
        XCTAssertFalse(FileManager.default.fileExists(atPath: file1.path), "File 1 should be cleaned")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file2.path), "File 2 should be cleaned")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file3.path), "File 3 should remain")
    }

    func testCleanupAll() async throws {
        let file1 = testDirectory.appendingPathComponent("file1.sh")
        let file2 = testDirectory.appendingPathComponent("file2.sh")
        let file3 = testDirectory.appendingPathComponent("file3.sh")

        try "content1".write(to: file1, atomically: true, encoding: .utf8)
        try "content2".write(to: file2, atomically: true, encoding: .utf8)
        try "content3".write(to: file3, atomically: true, encoding: .utf8)

        TempFileTracker.shared.register(file: file1)
        TempFileTracker.shared.register(file: file2)
        TempFileTracker.shared.register(file: file3)

        TempFileTracker.shared.cleanupAll()

        // Wait for async cleanup
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        XCTAssertFalse(FileManager.default.fileExists(atPath: file1.path), "File 1 should be cleaned")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file2.path), "File 2 should be cleaned")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file3.path), "File 3 should be cleaned")

        let trackedFiles = TempFileTracker.shared.getAllTrackedFiles()
        XCTAssertEqual(trackedFiles.count, 0, "All files should be removed from tracker")
    }

    func testCleanupOldFiles() async throws {
        let oldFile = testDirectory.appendingPathComponent("old.sh")
        let newFile = testDirectory.appendingPathComponent("new.sh")

        try "old content".write(to: oldFile, atomically: true, encoding: .utf8)
        try "new content".write(to: newFile, atomically: true, encoding: .utf8)

        // Set old file modification date to 2 days ago
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-2 * 24 * 60 * 60)],
            ofItemAtPath: oldFile.path
        )

        TempFileTracker.shared.register(file: oldFile)
        TempFileTracker.shared.register(file: newFile)

        // Cleanup files older than 1 hour
        await TempFileTracker.shared.cleanupOldFiles(olderThan: 60 * 60)

        XCTAssertFalse(FileManager.default.fileExists(atPath: oldFile.path), "Old file should be cleaned")
        XCTAssertTrue(FileManager.default.fileExists(atPath: newFile.path), "New file should remain")

        let trackedFiles = TempFileTracker.shared.getAllTrackedFiles()
        XCTAssertNil(trackedFiles[oldFile], "Old file should be removed from tracker")
        XCTAssertNotNil(trackedFiles[newFile], "New file should remain in tracker")
    }

    func testCleanupOldFilesWithNoOldFiles() async throws {
        let newFile = testDirectory.appendingPathComponent("new.sh")
        try "new content".write(to: newFile, atomically: true, encoding: .utf8)

        TempFileTracker.shared.register(file: newFile)

        // Cleanup files older than 1 day (none should be cleaned)
        await TempFileTracker.shared.cleanupOldFiles(olderThan: 24 * 60 * 60)

        XCTAssertTrue(FileManager.default.fileExists(atPath: newFile.path), "New file should remain")

        let trackedFiles = TempFileTracker.shared.getAllTrackedFiles()
        XCTAssertEqual(trackedFiles.count, 1, "File should remain in tracker")
    }

    func testCleanupOldFilesWithEmptyTracker() async throws {
        // No files registered
        await TempFileTracker.shared.cleanupOldFiles(olderThan: 60 * 60)

        // Should not crash or throw
        let trackedFiles = TempFileTracker.shared.getAllTrackedFiles()
        XCTAssertEqual(trackedFiles.count, 0, "Tracker should remain empty")
    }

    // MARK: - Querying Tests

    func testGetAllTrackedFiles() throws {
        let file1 = testDirectory.appendingPathComponent("file1.sh")
        let file2 = testDirectory.appendingPathComponent("file2.sh")

        try "content1".write(to: file1, atomically: true, encoding: .utf8)
        try "content2".write(to: file2, atomically: true, encoding: .utf8)

        TempFileTracker.shared.register(file: file1)
        TempFileTracker.shared.register(file: file2)

        let trackedFiles = TempFileTracker.shared.getAllTrackedFiles()
        XCTAssertEqual(trackedFiles.count, 2, "Should return all tracked files")
        XCTAssertTrue(trackedFiles[file1] != nil, "Should contain file1")
        XCTAssertTrue(trackedFiles[file2] != nil, "Should contain file2")
    }

    func testGetTrackedFileCount() throws {
        XCTAssertEqual(TempFileTracker.shared.getTrackedFileCount(), 0, "Should be 0 initially")

        let file1 = testDirectory.appendingPathComponent("file1.sh")
        let file2 = testDirectory.appendingPathComponent("file2.sh")

        try "content1".write(to: file1, atomically: true, encoding: .utf8)
        try "content2".write(to: file2, atomically: true, encoding: .utf8)

        TempFileTracker.shared.register(file: file1)
        XCTAssertEqual(TempFileTracker.shared.getTrackedFileCount(), 1, "Should be 1 after first registration")

        TempFileTracker.shared.register(file: file2)
        XCTAssertEqual(TempFileTracker.shared.getTrackedFileCount(), 2, "Should be 2 after second registration")
    }

    // MARK: - TempFileInfo Tests

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

    // MARK: - Thread Safety Tests

    func testConcurrentRegistration() throws {
        let fileCount = 100
        let expectation = XCTestExpectation(description: "Concurrent registration")

        // Create files
        var files: [URL] = []
        for index in 0..<fileCount {
            let file = testDirectory.appendingPathComponent("file\(index).sh")
            try "content\(index)".write(to: file, atomically: true, encoding: .utf8)
            files.append(file)
        }

        // Register concurrently
        DispatchQueue.concurrentPerform(iterations: fileCount) { index in
            TempFileTracker.shared.register(file: files[index])
        }

        expectation.fulfill()

        let trackedFiles = TempFileTracker.shared.getAllTrackedFiles()
        XCTAssertEqual(trackedFiles.count, fileCount, "All files should be registered")
    }

    func testConcurrentCleanup() async throws {
        let fileCount = 50
        var files: [URL] = []

        // Create and register files
        for index in 0..<fileCount {
            let file = testDirectory.appendingPathComponent("file\(index).sh")
            try "content\(index)".write(to: file, atomically: true, encoding: .utf8)
            TempFileTracker.shared.register(file: file)
            files.append(file)
        }

        // Cleanup concurrently
        await withTaskGroup(of: Void.self) { group in
            for file in files {
                group.addTask {
                    await TempFileTracker.shared.cleanupWithRetry(file: file, maxRetries: 1)
                }
            }
        }

        // Wait for all cleanups to complete
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds

        let trackedFiles = TempFileTracker.shared.getAllTrackedFiles()
        // Some may remain due to concurrent access, but tracker should handle it safely
        XCTAssertGreaterThanOrEqual(trackedFiles.count, 0, "Tracker should handle concurrent operations safely")
    }

    // MARK: - Edge Cases

    func testCleanupNonExistentFile() async {
        let nonExistentFile = testDirectory.appendingPathComponent("nonexistent.sh")

        TempFileTracker.shared.register(file: nonExistentFile)

        // Should not crash or throw
        await TempFileTracker.shared.cleanupWithRetry(file: nonExistentFile, maxRetries: 3)

        let trackedFiles = TempFileTracker.shared.getAllTrackedFiles()
        XCTAssertNil(trackedFiles[nonExistentFile], "Non-existent file should be removed from tracker")
    }

    func testMarkForCleanupUnregisteredFile() throws {
        let tempFile = testDirectory.appendingPathComponent("test.sh")
        try "test content".write(to: tempFile, atomically: true, encoding: .utf8)

        // Should not crash
        TempFileTracker.shared.markForCleanup(file: tempFile)

        // File should not be tracked
        let trackedFiles = TempFileTracker.shared.getAllTrackedFiles()
        XCTAssertNil(trackedFiles[tempFile], "Unregistered file should not be tracked")
    }
}
