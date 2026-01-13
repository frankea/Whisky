//
//  LogRetentionTests.swift
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

final class LogRetentionTests: XCTestCase {
    func testEnforceLogRetentionDeletesOldestLogsByModificationDate() throws {
        let dir = try makeTempDirectory()

        // Create 3 log files with sizes 100, 200, 300 bytes
        let log1 = dir.appendingPathComponent("oldest").appendingPathExtension("log")
        let log2 = dir.appendingPathComponent("middle").appendingPathExtension("log")
        let log3 = dir.appendingPathComponent("newest").appendingPathExtension("log")

        try Data(repeating: 0x01, count: 100).write(to: log1)
        try Data(repeating: 0x02, count: 200).write(to: log2)
        try Data(repeating: 0x03, count: 300).write(to: log3)

        // Force deterministic ordering by modification date
        let now = Date()
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-300)],
            ofItemAtPath: log1.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-200)],
            ofItemAtPath: log2.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-100)],
            ofItemAtPath: log3.path
        )

        // Total is 600 bytes; with a cap of 400, should delete log1 (total becomes 500),
        // then log2 (total becomes 300), and keep log3.
        Wine.enforceLogRetention(in: dir, maxTotalBytes: 400)

        XCTAssertFalse(FileManager.default.fileExists(atPath: log1.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: log2.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: log3.path))
    }

    func testWriteWineLogCapsFileAndWritesTruncationMarkerOnce() throws {
        let dir = try makeTempDirectory()
        let fileURL = dir.appendingPathComponent("capped").appendingPathExtension("log")
        try "".write(to: fileURL, atomically: true, encoding: .utf8)

        let handle = try FileHandle(forWritingTo: fileURL)

        // Write enough data to exceed the cap.
        let chunk = String(repeating: "A", count: 64 * 1_024)
        for _ in 0 ..< 400 { // ~25 MiB of attempted output
            handle.writeWineLog(line: chunk)
        }

        try handle.closeWineLog()

        let data = try Data(contentsOf: fileURL)
        XCTAssertLessThanOrEqual(data.count, Int(Wine.maxLogFileBytes))

        let marker = Wine.logTruncationMarker.data(using: .utf8) ?? Data()
        let occurrences = countOccurrences(of: marker, in: data)
        XCTAssertEqual(occurrences, 1)
    }

    func testWriteWineLogDoesNotWriteTruncationMarkerWhenUnderCap() throws {
        let dir = try makeTempDirectory()
        let fileURL = dir.appendingPathComponent("normal").appendingPathExtension("log")
        try "".write(to: fileURL, atomically: true, encoding: .utf8)

        let handle = try FileHandle(forWritingTo: fileURL)

        handle.writeWineLog(line: "hello world\n")
        try handle.closeWineLog()

        let data = try Data(contentsOf: fileURL)
        let text = String(bytes: data, encoding: .utf8)
        XCTAssertTrue(text?.contains("hello world") == true)

        let marker = Wine.logTruncationMarker.data(using: .utf8) ?? Data()
        let occurrences = countOccurrences(of: marker, in: data)
        XCTAssertEqual(occurrences, 0)
    }

    func testWriteWineLogIsThreadSafeAndMarkerAppearsOnce() throws {
        let dir = try makeTempDirectory()
        let fileURL = dir.appendingPathComponent("concurrent").appendingPathExtension("log")
        try "".write(to: fileURL, atomically: true, encoding: .utf8)

        let handle = try FileHandle(forWritingTo: fileURL)

        let chunk = String(repeating: "B", count: 32 * 1_024)
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "log-test", attributes: .concurrent)

        for _ in 0 ..< 8 {
            group.enter()
            queue.async {
                for _ in 0 ..< 200 { // ~6.25 MiB per worker attempted
                    handle.writeWineLog(line: chunk)
                }
                group.leave()
            }
        }

        group.wait()
        try handle.closeWineLog()

        let data = try Data(contentsOf: fileURL)
        XCTAssertLessThanOrEqual(data.count, Int(Wine.maxLogFileBytes))

        let marker = Wine.logTruncationMarker.data(using: .utf8) ?? Data()
        let occurrences = countOccurrences(of: marker, in: data)
        XCTAssertEqual(occurrences, 1)
    }

    // MARK: - Helpers

    private func makeTempDirectory() throws -> URL {
        let base = FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: dir)
        }
        return dir
    }

    private func countOccurrences(of needle: Data, in haystack: Data) -> Int {
        guard !needle.isEmpty, haystack.count >= needle.count else { return 0 }
        var count = 0
        var searchStart = haystack.startIndex
        while searchStart < haystack.endIndex {
            if let range = haystack.range(of: needle, options: [], in: searchStart ..< haystack.endIndex) {
                count += 1
                searchStart = range.upperBound
            } else {
                break
            }
        }
        return count
    }
}
