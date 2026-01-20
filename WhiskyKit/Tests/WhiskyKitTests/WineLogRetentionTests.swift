//
//  WineLogRetentionTests.swift
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

final class WineLogRetentionTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appending(path: "logretention_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    /// Helper to create a log file with specific content
    func createLogFile(name: String, content: String, modificationDate: Date? = nil) throws -> URL {
        let url = tempDir.appending(path: name)
        try content.write(to: url, atomically: true, encoding: .utf8)

        if let date = modificationDate {
            try FileManager.default.setAttributes(
                [.modificationDate: date],
                ofItemAtPath: url.path(percentEncoded: false)
            )
        }

        return url
    }

    func testEnforceLogRetentionDoesNothingWhenUnderLimit() throws {
        // Create files totaling 100 bytes, with limit of 1000 bytes
        _ = try createLogFile(name: "test1.log", content: String(repeating: "a", count: 50))
        _ = try createLogFile(name: "test2.log", content: String(repeating: "b", count: 50))

        Wine.enforceLogRetention(in: tempDir, maxTotalBytes: 1_000)

        // Both files should still exist
        let files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 2)
    }

    func testEnforceLogRetentionDeletesOldestFirst() throws {
        let now = Date()
        let oldest = try createLogFile(
            name: "oldest.log",
            content: String(repeating: "a", count: 100),
            modificationDate: now.addingTimeInterval(-3_600) // 1 hour ago
        )
        let middle = try createLogFile(
            name: "middle.log",
            content: String(repeating: "b", count: 100),
            modificationDate: now.addingTimeInterval(-1_800) // 30 min ago
        )
        let newest = try createLogFile(
            name: "newest.log",
            content: String(repeating: "c", count: 100),
            modificationDate: now
        )

        // Total is 300 bytes, limit to 250 bytes - should only delete oldest (100 bytes),
        // leaving middle + newest = 200 bytes which is under limit
        Wine.enforceLogRetention(in: tempDir, maxTotalBytes: 250)

        XCTAssertFalse(FileManager.default.fileExists(atPath: oldest.path(percentEncoded: false)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: middle.path(percentEncoded: false)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newest.path(percentEncoded: false)))
    }

    func testEnforceLogRetentionOnlyDeletesLogFiles() throws {
        // Create a .log file and a .txt file
        let logFile = try createLogFile(name: "test.log", content: String(repeating: "a", count: 100))
        let txtFile = tempDir.appending(path: "test.txt")
        try String(repeating: "b", count: 100).write(to: txtFile, atomically: true, encoding: .utf8)

        // Limit to 50 bytes - should only consider .log files
        Wine.enforceLogRetention(in: tempDir, maxTotalBytes: 50)

        // Log file should be deleted (over limit), txt should remain
        XCTAssertFalse(FileManager.default.fileExists(atPath: logFile.path(percentEncoded: false)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: txtFile.path(percentEncoded: false)))
    }

    func testEnforceLogRetentionHandlesEmptyDirectory() throws {
        // Should not crash on empty directory
        Wine.enforceLogRetention(in: tempDir, maxTotalBytes: 100)

        let files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 0)
    }

    func testEnforceLogRetentionHandlesNonexistentDirectory() {
        let nonexistent = tempDir.appending(path: "nonexistent")
        // Should not crash on nonexistent directory
        Wine.enforceLogRetention(in: nonexistent, maxTotalBytes: 100)
    }

    func testEnforceLogRetentionDeletesMultipleFilesIfNeeded() throws {
        let now = Date()
        let file1 = try createLogFile(
            name: "file1.log",
            content: String(repeating: "a", count: 100),
            modificationDate: now.addingTimeInterval(-300)
        )
        let file2 = try createLogFile(
            name: "file2.log",
            content: String(repeating: "b", count: 100),
            modificationDate: now.addingTimeInterval(-200)
        )
        let file3 = try createLogFile(
            name: "file3.log",
            content: String(repeating: "c", count: 100),
            modificationDate: now.addingTimeInterval(-100)
        )
        let file4 = try createLogFile(
            name: "file4.log",
            content: String(repeating: "d", count: 100),
            modificationDate: now
        )

        // Total is 400 bytes, limit to 150 - should delete 3 oldest files
        Wine.enforceLogRetention(in: tempDir, maxTotalBytes: 150)

        XCTAssertFalse(FileManager.default.fileExists(atPath: file1.path(percentEncoded: false)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file2.path(percentEncoded: false)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file3.path(percentEncoded: false)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file4.path(percentEncoded: false)))
    }

    func testEnforceLogRetentionWithZeroLimit() throws {
        _ = try createLogFile(name: "test.log", content: "content")

        // Zero limit should delete all log files
        Wine.enforceLogRetention(in: tempDir, maxTotalBytes: 0)

        let files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 0)
    }

    func testEnforceLogRetentionIgnoresSubdirectories() throws {
        // Create a subdirectory named .log
        let subdir = tempDir.appending(path: "subdir.log")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)

        // Create a file inside the subdirectory
        let fileInSubdir = subdir.appending(path: "nested.log")
        try "nested content".write(to: fileInSubdir, atomically: true, encoding: .utf8)

        // Create a regular log file
        let logFile = try createLogFile(name: "regular.log", content: String(repeating: "a", count: 100))

        // Limit to 50 bytes
        Wine.enforceLogRetention(in: tempDir, maxTotalBytes: 50)

        // Subdirectory should still exist (directories are skipped via isRegularFileKey check)
        XCTAssertTrue(FileManager.default.fileExists(atPath: subdir.path(percentEncoded: false)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileInSubdir.path(percentEncoded: false)))
        // Regular log file should be deleted
        XCTAssertFalse(FileManager.default.fileExists(atPath: logFile.path(percentEncoded: false)))
    }
}
