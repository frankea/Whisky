//
//  WineLogFollowerTests.swift
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

/// Following a log, as the Console view and `whisky run --tail-log` do, across the
/// truncations that keep it under its cap.
final class WineLogFollowerTests: XCTestCase {
    private let limits = WineLogLimits(maxBytes: 8 * 1_024, headBytes: 1_024, tailBytes: 2 * 1_024)
    private let header = "Whisky Version: 9.9.9\nBottle Name: Test Bottle\n\n"
    private var nextLine = 0

    func testFollowerFromTheBeginningReadsTheWholeLogThenOnlyWhatIsNew() throws {
        let (handle, url) = try makeLog()
        handle.writeWineLog(line: header, limits: limits)
        var follower = WineLogFollower(logFileURL: url, start: .beginning)

        XCTAssertEqual(try follower.read().data, Data(header.utf8))
        XCTAssertEqual(try follower.read().data, Data())
        handle.writeWineLog(line: "one more\n", limits: limits)
        let chunk = try follower.read()
        XCTAssertEqual(chunk.data, Data("one more\n".utf8))
        XCTAssertFalse(chunk.resumedAtMarker)
    }

    func testFollowerFromTheEndSkipsWhatIsAlreadyThere() throws {
        let (handle, url) = try makeLog()
        handle.writeWineLog(line: header, limits: limits)
        var follower = WineLogFollower(logFileURL: url, start: .end)

        XCTAssertEqual(try follower.read().data, Data())
        handle.writeWineLog(line: "after the start\n", limits: limits)
        XCTAssertEqual(try follower.read().data, Data("after the start\n".utf8))
    }

    func testLogThatShrankResumesAtTheMarker() throws {
        let (handle, url) = try makeLog()
        handle.writeWineLog(line: header, limits: limits)
        try writeLines(to: handle, url: url, untilSize: UInt64(limits.maxBytes) - 64)
        var follower = WineLogFollower(logFileURL: url, start: .beginning)
        _ = try follower.read()

        handle.writeWineLog(line: String(repeating: "x", count: 100) + "\n", limits: limits)
        XCTAssertLessThan(try fileSize(url), follower.offset, "the log shrank")
        try assertResumesAtMarker(&follower, url: url, count: 1)
    }

    /// The log was cut back and grew past the follower's offset before it read again,
    /// so its size alone shows no truncation.
    func testLogThatGrewBackPastTheOffsetResumesAtTheMarker() throws {
        let (handle, url) = try makeLog()
        handle.writeWineLog(line: header, limits: limits)
        try writeLines(to: handle, url: url, untilSize: 6_000)
        var follower = WineLogFollower(logFileURL: url, start: .beginning)
        _ = try follower.read()

        try writeLines(to: handle, url: url, untilTruncations: 1, andSize: follower.offset)
        try assertResumesAtMarker(&follower, url: url, count: 1)

        // And again for a later truncation, whose marker sits where the first one did.
        try writeLines(to: handle, url: url, untilTruncations: 2, andSize: follower.offset)
        try assertResumesAtMarker(&follower, url: url, count: 2)
        XCTAssertEqual(try follower.read().data, Data(), "nothing is returned twice without a truncation")
    }

    func testFollowerStillInTheHeadReadsOnIntoTheMarker() throws {
        let (handle, url) = try makeLog()
        handle.writeWineLog(line: header, limits: limits)
        var follower = WineLogFollower(logFileURL: url, start: .beginning)
        let start = try follower.read().data

        try writeLines(to: handle, url: url, untilTruncations: 1, andSize: 6_000)
        let chunk = try follower.read()
        XCTAssertFalse(chunk.resumedAtMarker, "the head was kept as it was")
        XCTAssertEqual(start + chunk.data, try Data(contentsOf: url), "nothing is repeated or skipped")
    }

    func testLogRewrittenDuringAReadIsReadAgainFromTheMarker() throws {
        let (handle, url) = try makeLog()
        handle.writeWineLog(line: header, limits: limits)
        try writeLines(to: handle, url: url, untilSize: 6_000)
        var follower = WineLogFollower(logFileURL: url, start: .beginning)
        _ = try follower.read()
        handle.writeWineLog(line: "read from the old log\n", limits: limits)

        var rewrites = 0
        let chunk = try follower.read {
            guard rewrites == 0 else { return }
            rewrites += 1
            try? writeLines(to: handle, url: url, untilTruncations: 1, andSize: 7_000)
        }
        XCTAssertTrue(chunk.resumedAtMarker, "the read from the old offset was dropped")
        let marker = try XCTUnwrap(Wine.truncationMarker(inLogAt: url))
        XCTAssertEqual(chunk.data, try Data(contentsOf: url).dropFirst(Int(marker.offset)))
    }

    func testMarkerCountIsReadOnlyFromAWholeLine() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "log-marker-\(UUID().uuidString).log")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let marker = header + Wine.logTruncationMarker + Wine.logTruncationCountPrefix

        try Data((marker + "12").utf8).write(to: url)
        let partial = try XCTUnwrap(Wine.truncationMarker(inLogAt: url))
        XCTAssertEqual(partial.offset, UInt64(header.utf8.count))
        XCTAssertNil(partial.count, "a count still being written is not read as a smaller one")

        try Data((marker + "12\nnewest output\n").utf8).write(to: url)
        XCTAssertEqual(Wine.truncationMarker(inLogAt: url)?.count, 12)
    }

    // MARK: - Helpers

    /// Reads once and checks that the read went on from the marker to the end of the log.
    private func assertResumesAtMarker(
        _ follower: inout WineLogFollower,
        url: URL,
        count: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let chunk = try follower.read()
        let data = try Data(contentsOf: url)
        let marker = try XCTUnwrap(Wine.truncationMarker(inLogAt: url), file: file, line: line)
        XCTAssertEqual(marker.count, count, file: file, line: line)
        XCTAssertTrue(chunk.resumedAtMarker, "the truncation was noticed", file: file, line: line)
        XCTAssertEqual(
            chunk.data,
            data.dropFirst(Int(marker.offset)),
            "everything from the marker",
            file: file,
            line: line
        )
        XCTAssertEqual(follower.offset, UInt64(data.count), file: file, line: line)
    }

    /// Writes numbered lines until the log is at least `size` bytes long.
    private func writeLines(to handle: FileHandle, url: URL, untilSize size: UInt64) throws {
        try writeLines(to: handle, url: url, untilTruncations: 0, andSize: size)
    }

    /// Writes numbered lines until the log has been truncated `truncations` times in all
    /// and is at least `size` bytes long.
    private func writeLines(
        to handle: FileHandle,
        url: URL,
        untilTruncations truncations: Int,
        andSize size: UInt64
    ) throws {
        for _ in 0 ..< 10_000 {
            let count = Wine.truncationMarker(inLogAt: url)?.count ?? 0
            XCTAssertLessThanOrEqual(count, truncations, "the log was truncated more often than meant")
            if count == truncations, try fileSize(url) >= size { return }
            handle.writeWineLog(line: "fixme:spam line \(nextLine)\n", limits: limits)
            nextLine += 1
        }
        XCTFail("the log never reached \(truncations) truncations and \(size) bytes")
    }

    private func fileSize(_ url: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        return try XCTUnwrap(attributes[.size] as? UInt64)
    }

    private func makeLog() throws -> (FileHandle, URL) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "log-follow-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let (handle, url) = try Wine.makeLogFile(in: folder, date: .now)
        addTeardownBlock { try? handle.closeWineLog() }
        return (handle, url)
    }
}
