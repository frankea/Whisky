//
//  WineLogCapTests.swift
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

/// A log that reaches its cap keeps its launch header and its newest output (#360).
final class WineLogCapTests: XCTestCase {
    private let limits = WineLogLimits(maxBytes: 8 * 1_024, headBytes: 1_024, tailBytes: 2 * 1_024)
    private let header = """
    Whisky Version: 9.9.9
    Bottle Name: Test Bottle
    Arguments: start /unix C:\\game.exe

    Environment (keys only):
    WINEPREFIX, WINEDEBUG


    """

    func testTruncatedLogKeepsHeaderAndEndsWithNewestOutput() throws {
        let (handle, url) = try makeLog()
        handle.writeWineLog(line: header, limits: limits)
        for index in 0 ..< 3_000 {
            handle.writeWineLog(line: "fixme:spam line \(index)\n", limits: limits)
        }
        handle.writeWineLog(line: "wine: Unhandled exception 0xc0000005 at the very end\n", limits: limits)
        try handle.closeWineLog()

        let data = try Data(contentsOf: url)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertLessThanOrEqual(data.count, Int(limits.maxBytes))
        XCTAssertTrue(text.hasPrefix(header), "the launch header must survive truncation")
        XCTAssertTrue(text.hasSuffix("wine: Unhandled exception 0xc0000005 at the very end\n"))
        XCTAssertTrue(text.contains("fixme:spam line 2999\n"), "the newest output must be kept")
        XCTAssertFalse(text.contains("fixme:spam line 1500\n"), "the middle of the session is what gets dropped")
        XCTAssertEqual(text.components(separatedBy: Wine.logTruncationMarker).count - 1, 1)
    }

    func testTruncationCutsTheHeadAndTailAtLineBoundaries() throws {
        let (handle, url) = try makeLog()
        handle.writeWineLog(line: header, limits: limits)
        for index in 0 ..< 1_000 {
            handle.writeWineLog(line: "early or late output \(index)\n", limits: limits)
        }
        try handle.closeWineLog()

        let text = try XCTUnwrap(String(data: Data(contentsOf: url), encoding: .utf8))
        let parts = text.components(separatedBy: Wine.logTruncationMarker)
        XCTAssertEqual(parts.count, 2)
        let head = try XCTUnwrap(parts.first)
        let afterMarker = try XCTUnwrap(parts.last)
        XCTAssertTrue(afterMarker.hasPrefix(Wine.logTruncationCountPrefix), "the marker is followed by its count")
        let tail = afterMarker.drop { $0 != "\n" }.dropFirst()
        XCTAssertTrue(head.hasPrefix(header))
        XCTAssertTrue(head.hasSuffix("\n"), "the head ends with a whole line")
        XCTAssertLessThanOrEqual(head.utf8.count, limits.headBytes)
        XCTAssertTrue(tail.hasPrefix("early or late output "), "the kept tail starts with a whole line")
        XCTAssertTrue(tail.hasSuffix("early or late output 999\n"))
    }

    func testWriteLargerThanTheCapKeepsHeaderAndItsEnd() throws {
        let (handle, url) = try makeLog()
        handle.writeWineLog(line: header, limits: limits)
        let flood = String(repeating: "x", count: 20_000) + "\nlast words\n"
        handle.writeWineLog(line: flood, limits: limits)
        try handle.closeWineLog()

        let data = try Data(contentsOf: url)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertLessThanOrEqual(data.count, Int(limits.maxBytes))
        XCTAssertTrue(text.hasPrefix(header))
        XCTAssertTrue(text.hasSuffix("last words\n"))
        XCTAssertTrue(text.contains(Wine.logTruncationMarker))
    }

    func testLogUnderTheCapIsLeftAlone() throws {
        let (handle, url) = try makeLog()
        handle.writeWineLog(line: header, limits: limits)
        handle.writeWineLog(line: "a short run\n", limits: limits)
        try handle.closeWineLog()

        let text = try XCTUnwrap(String(data: Data(contentsOf: url), encoding: .utf8))
        XCTAssertEqual(text, header + "a short run\n")
    }

    func testStandardLimitsKeepMoreThanClassificationReads() {
        let standard = WineLogLimits.standard
        XCTAssertEqual(standard.maxBytes, Wine.maxLogFileBytes)
        // Classification reads 64 KiB of head and 256 KiB of tail.
        XCTAssertGreaterThanOrEqual(standard.headBytes, 64 * 1_024)
        XCTAssertGreaterThanOrEqual(standard.tailBytes, 256 * 1_024)
        XCTAssertLessThan(
            Int64(
                standard.headBytes + standard.tailBytes + Wine.logTruncationMarker.utf8.count
                    + Wine.logTruncationCountLine(Int.max).utf8.count
            ),
            standard.maxBytes
        )
    }

    func testReaderThatSawTheLogShrinkResumesAtTheMarker() throws {
        let (handle, url) = try makeLog()
        handle.writeWineLog(line: header, limits: limits)
        var written = header.utf8.count
        var index = 0
        while true {
            let line = "fixme:spam line \(index)\n"
            guard written + line.utf8.count <= Int(limits.maxBytes) else { break }
            handle.writeWineLog(line: line, limits: limits)
            written += line.utf8.count
            index += 1
        }
        // Everything up to here has been read by someone following the log.
        let readerOffset = try XCTUnwrap(try FileManager.default.attributesOfItem(
            atPath: url.path(percentEncoded: false)
        )[.size] as? UInt64)
        XCTAssertNil(Wine.truncationMarker(inLogAt: url), "a log under its cap has no marker")

        handle.writeWineLog(line: "the write that overflowed the log\n", limits: limits)
        try handle.closeWineLog()

        let data = try Data(contentsOf: url)
        XCTAssertLessThan(UInt64(data.count), readerOffset, "the log shrank")
        let marker = try XCTUnwrap(Wine.truncationMarker(inLogAt: url))
        XCTAssertEqual(marker.count, 1)
        let markerOffset = marker.offset
        let resumed = try XCTUnwrap(String(data: data.dropFirst(Int(markerOffset)), encoding: .utf8))
        XCTAssertTrue(resumed.hasPrefix(Wine.logTruncationMarker))
        XCTAssertTrue(resumed.hasSuffix("the write that overflowed the log\n"))
    }

    func testSealedHeadLengthStopsAfterTheLastFullLine() {
        XCTAssertEqual(WineLogCapRegistry.sealedHeadLength(of: Data("one\ntwo\nthr".utf8)), 8)
        XCTAssertEqual(WineLogCapRegistry.sealedHeadLength(of: Data("no newline".utf8)), 10)
        XCTAssertEqual(WineLogCapRegistry.sealedHeadLength(of: Data()), 0)
    }

    func testLineAlignedSuffix() {
        let data = Data("alpha\nbeta\ngamma\n".utf8)
        XCTAssertEqual(WineLogCapRegistry.lineAlignedSuffix(of: data, maxCount: 100), data)
        XCTAssertEqual(WineLogCapRegistry.lineAlignedSuffix(of: data, maxCount: 9), Data("gamma\n".utf8))
        XCTAssertEqual(WineLogCapRegistry.lineAlignedSuffix(of: data, maxCount: 4), Data("mma\n".utf8))
        XCTAssertEqual(WineLogCapRegistry.lineAlignedSuffix(of: data, maxCount: 0), Data())
    }

    // MARK: - Helpers

    private func makeLog() throws -> (FileHandle, URL) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "log-cap-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return try Wine.makeLogFile(in: folder, date: .now)
    }
}
