//
//  FileExtensionTests.swift
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

// MARK: - FileHandle.extract Tests

final class FileHandleExtractTests: XCTestCase {
    var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory.appending(path: "test_\(UUID().uuidString).bin")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }

    func testExtractUInt8() throws {
        let data = Data([0x42])
        try data.write(to: tempURL)

        let handle = try FileHandle(forReadingFrom: tempURL)
        defer { try? handle.close() }

        let value = handle.extract(UInt8.self, offset: 0)
        XCTAssertEqual(value, 0x42)
    }

    func testExtractUInt16() throws {
        let data = Data([0x34, 0x12])
        try data.write(to: tempURL)

        let handle = try FileHandle(forReadingFrom: tempURL)
        defer { try? handle.close() }

        let value = handle.extract(UInt16.self, offset: 0)
        XCTAssertEqual(value, 0x1234)
    }

    func testExtractUInt32() throws {
        let data = Data([0x78, 0x56, 0x34, 0x12])
        try data.write(to: tempURL)

        let handle = try FileHandle(forReadingFrom: tempURL)
        defer { try? handle.close() }

        let value = handle.extract(UInt32.self, offset: 0)
        XCTAssertEqual(value, 0x1234_5678)
    }

    func testExtractUInt64() throws {
        let data = Data([0xEF, 0xCD, 0xAB, 0x90, 0x78, 0x56, 0x34, 0x12])
        try data.write(to: tempURL)

        let handle = try FileHandle(forReadingFrom: tempURL)
        defer { try? handle.close() }

        let value = handle.extract(UInt64.self, offset: 0)
        XCTAssertEqual(value, 0x1234_5678_90AB_CDEF)
    }

    func testExtractWithOffset() throws {
        let data = Data([0x00, 0x00, 0x42, 0x00])
        try data.write(to: tempURL)

        let handle = try FileHandle(forReadingFrom: tempURL)
        defer { try? handle.close() }

        let value = handle.extract(UInt8.self, offset: 2)
        XCTAssertEqual(value, 0x42)
    }

    func testExtractMultipleValues() throws {
        let data = Data([
            0x01, 0x00,
            0x02, 0x00,
            0x03, 0x00, 0x00, 0x00
        ])
        try data.write(to: tempURL)

        let handle = try FileHandle(forReadingFrom: tempURL)
        defer { try? handle.close() }

        let value1 = handle.extract(UInt16.self, offset: 0)
        let value2 = handle.extract(UInt16.self, offset: 2)
        let value3 = handle.extract(UInt32.self, offset: 4)

        XCTAssertEqual(value1, 0x0001)
        XCTAssertEqual(value2, 0x0002)
        XCTAssertEqual(value3, 0x0000_0003)
    }

    func testExtractAtExactEndReturnsNil() throws {
        let data = Data([0x01, 0x02, 0x03, 0x04])
        try data.write(to: tempURL)

        let handle = try FileHandle(forReadingFrom: tempURL)
        defer { try? handle.close() }

        let value = handle.extract(UInt8.self, offset: 4)
        XCTAssertNil(value)
    }

    func testExtractFromEmptyFile() throws {
        let data = Data()
        try data.write(to: tempURL)

        let handle = try FileHandle(forReadingFrom: tempURL)
        defer { try? handle.close() }

        let value = handle.extract(UInt8.self, offset: 0)
        XCTAssertNil(value)
    }

    func testExtractAtOffsetBeyondFileSize() throws {
        let data = Data([0x01, 0x02, 0x03, 0x04])
        try data.write(to: tempURL)

        let handle = try FileHandle(forReadingFrom: tempURL)
        defer { try? handle.close() }

        let value = handle.extract(UInt32.self, offset: 100)
        XCTAssertNil(value)
    }
}

// MARK: - FileHandle.write(line:) Tests

final class FileHandleWriteLineTests: XCTestCase {
    var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory.appending(path: "test_\(UUID().uuidString).txt")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }

    func testWriteLine() throws {
        FileManager.default.createFile(atPath: tempURL.path(percentEncoded: false), contents: nil)

        let handle = try FileHandle(forWritingTo: tempURL)
        handle.write(line: "Hello, World!")
        try handle.close()

        let content = try String(contentsOf: tempURL, encoding: .utf8)
        XCTAssertEqual(content, "Hello, World!")
    }

    func testWriteMultipleLines() throws {
        FileManager.default.createFile(atPath: tempURL.path(percentEncoded: false), contents: nil)

        let handle = try FileHandle(forWritingTo: tempURL)
        handle.write(line: "Line 1\n")
        handle.write(line: "Line 2\n")
        handle.write(line: "Line 3")
        try handle.close()

        let content = try String(contentsOf: tempURL, encoding: .utf8)
        XCTAssertEqual(content, "Line 1\nLine 2\nLine 3")
    }

    func testWriteEmptyLine() throws {
        FileManager.default.createFile(atPath: tempURL.path(percentEncoded: false), contents: nil)

        let handle = try FileHandle(forWritingTo: tempURL)
        handle.write(line: "")
        try handle.close()

        let content = try String(contentsOf: tempURL, encoding: .utf8)
        XCTAssertEqual(content, "")
    }

    func testWriteUnicodeContent() throws {
        FileManager.default.createFile(atPath: tempURL.path(percentEncoded: false), contents: nil)

        let handle = try FileHandle(forWritingTo: tempURL)
        handle.write(line: "日本語テスト 🎮")
        try handle.close()

        let content = try String(contentsOf: tempURL, encoding: .utf8)
        XCTAssertEqual(content, "日本語テスト 🎮")
    }
}

// MARK: - FileManager.replaceFile Tests

final class FileManagerReplaceFileTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appending(path: "test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testReplaceFileWithOriginalCopy() throws {
        let originalURL = tempDir.appending(path: "original.txt")
        let replacementURL = tempDir.appending(path: "replacement.txt")

        try Data("original content".utf8).write(to: originalURL)
        try Data("new content".utf8).write(to: replacementURL)

        try FileManager.default.replaceFile(at: originalURL, with: replacementURL, makeOriginalCopy: true)

        let newContent = try String(contentsOf: originalURL, encoding: .utf8)
        XCTAssertEqual(newContent, "new content")

        let copyURL = originalURL.appendingPathExtension("orig")
        XCTAssertTrue(FileManager.default.fileExists(atPath: copyURL.path(percentEncoded: false)))

        let copyContent = try String(contentsOf: copyURL, encoding: .utf8)
        XCTAssertEqual(copyContent, "original content")
    }

    func testReplaceFileWithoutOriginalCopy() throws {
        let originalURL = tempDir.appending(path: "original.txt")
        let replacementURL = tempDir.appending(path: "replacement.txt")

        try Data("original content".utf8).write(to: originalURL)
        try Data("new content".utf8).write(to: replacementURL)

        try FileManager.default.replaceFile(at: originalURL, with: replacementURL, makeOriginalCopy: false)

        let newContent = try String(contentsOf: originalURL, encoding: .utf8)
        XCTAssertEqual(newContent, "new content")

        let copyURL = originalURL.appendingPathExtension("orig")
        XCTAssertFalse(FileManager.default.fileExists(atPath: copyURL.path(percentEncoded: false)))
    }

    func testReplaceFileWhenOriginalDoesNotExist() throws {
        let originalURL = tempDir.appending(path: "nonexistent.txt")
        let replacementURL = tempDir.appending(path: "replacement.txt")

        try Data("new content".utf8).write(to: replacementURL)

        try FileManager.default.replaceFile(at: originalURL, with: replacementURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: originalURL.path(percentEncoded: false)))
    }

    func testReplaceFileRemovesExistingBackup() throws {
        let originalURL = tempDir.appending(path: "original.txt")
        let replacementURL = tempDir.appending(path: "replacement.txt")
        let backupURL = originalURL.appendingPathExtension("orig")

        try Data("original content".utf8).write(to: originalURL)
        try Data("old backup".utf8).write(to: backupURL)
        try Data("new content".utf8).write(to: replacementURL)

        try FileManager.default.replaceFile(at: originalURL, with: replacementURL, makeOriginalCopy: true)

        let backupContent = try String(contentsOf: backupURL, encoding: .utf8)
        XCTAssertEqual(backupContent, "original content")
    }
}

// MARK: - FileManager.replaceDLLs Tests

final class FileManagerReplaceDLLsTests: XCTestCase {
    var tempDir: URL!
    var destinationDir: URL!
    var sourceDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appending(path: "dll_test_\(UUID().uuidString)")
        destinationDir = tempDir.appending(path: "destination")
        sourceDir = tempDir.appending(path: "source")

        try? FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testReplaceDLLsReplacesMatchingFiles() throws {
        let destDLL = destinationDir.appending(path: "test.dll")
        let srcDLL = sourceDir.appending(path: "test.dll")

        try Data("original dll".utf8).write(to: destDLL)
        try Data("new dll".utf8).write(to: srcDLL)

        try FileManager.default.replaceDLLs(in: destinationDir, withContentsIn: sourceDir)

        let content = try String(contentsOf: destDLL, encoding: .utf8)
        XCTAssertEqual(content, "new dll")
    }

    func testReplaceDLLsIgnoresNonDLLFiles() throws {
        let destFile = destinationDir.appending(path: "test.exe")
        let srcFile = sourceDir.appending(path: "test.exe")

        try Data("original exe".utf8).write(to: destFile)
        try Data("new exe".utf8).write(to: srcFile)

        try FileManager.default.replaceDLLs(in: destinationDir, withContentsIn: sourceDir)

        let content = try String(contentsOf: destFile, encoding: .utf8)
        XCTAssertEqual(content, "original exe")
    }

    func testReplaceDLLsWithMakeOriginalCopy() throws {
        let destDLL = destinationDir.appending(path: "test.dll")
        let srcDLL = sourceDir.appending(path: "test.dll")

        try Data("original dll".utf8).write(to: destDLL)
        try Data("new dll".utf8).write(to: srcDLL)

        try FileManager.default.replaceDLLs(in: destinationDir, withContentsIn: sourceDir, makeOriginalCopy: true)

        let backupURL = destDLL.appendingPathExtension("orig")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path(percentEncoded: false)))
    }
}
