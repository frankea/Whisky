//
//  ProcessExtensionTests.swift
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

// MARK: - ProcessOutput Enum Extended Tests

final class ProcessOutputExtendedTests: XCTestCase {
    // MARK: - Equality Tests

    func testStartedEquality() {
        XCTAssertEqual(ProcessOutput.started, ProcessOutput.started)
    }

    func testMessageEquality() {
        XCTAssertEqual(ProcessOutput.message("hello"), ProcessOutput.message("hello"))
        XCTAssertNotEqual(ProcessOutput.message("hello"), ProcessOutput.message("world"))
    }

    func testErrorEquality() {
        XCTAssertEqual(ProcessOutput.error("error1"), ProcessOutput.error("error1"))
        XCTAssertNotEqual(ProcessOutput.error("error1"), ProcessOutput.error("error2"))
    }

    func testTerminatedEquality() {
        XCTAssertEqual(ProcessOutput.terminated(0), ProcessOutput.terminated(0))
        XCTAssertEqual(ProcessOutput.terminated(1), ProcessOutput.terminated(1))
        XCTAssertNotEqual(ProcessOutput.terminated(0), ProcessOutput.terminated(1))
    }

    func testDifferentCasesNotEqual() {
        XCTAssertNotEqual(ProcessOutput.started, ProcessOutput.terminated(0))
        XCTAssertNotEqual(ProcessOutput.message("test"), ProcessOutput.error("test"))
        XCTAssertNotEqual(ProcessOutput.message("test"), ProcessOutput.started)
    }

    // MARK: - Hashable Tests

    func testHashableConsistency() {
        let output1 = ProcessOutput.message("test")
        let output2 = ProcessOutput.message("test")

        XCTAssertEqual(output1.hashValue, output2.hashValue)
    }

    func testHashableInSet() {
        var outputSet: Set<ProcessOutput> = []

        outputSet.insert(.started)
        outputSet.insert(.message("hello"))
        outputSet.insert(.error("error"))
        outputSet.insert(.terminated(0))

        XCTAssertEqual(outputSet.count, 4)
        XCTAssertTrue(outputSet.contains(.started))
        XCTAssertTrue(outputSet.contains(.message("hello")))
        XCTAssertTrue(outputSet.contains(.error("error")))
        XCTAssertTrue(outputSet.contains(.terminated(0)))
    }

    func testHashableInSetDeduplication() {
        var outputSet: Set<ProcessOutput> = []

        outputSet.insert(.message("test"))
        outputSet.insert(.message("test"))
        outputSet.insert(.message("test"))

        XCTAssertEqual(outputSet.count, 1)
    }

    func testHashableAsDictionaryKey() {
        var dict: [ProcessOutput: String] = [:]

        dict[.started] = "started"
        dict[.message("msg")] = "message"
        dict[.error("err")] = "error"
        dict[.terminated(0)] = "success"
        dict[.terminated(1)] = "failure"

        XCTAssertEqual(dict[.started], "started")
        XCTAssertEqual(dict[.message("msg")], "message")
        XCTAssertEqual(dict[.error("err")], "error")
        XCTAssertEqual(dict[.terminated(0)], "success")
        XCTAssertEqual(dict[.terminated(1)], "failure")
    }

    // MARK: - Sendable Conformance

    func testSendableConformance() {
        // This test verifies at compile-time that ProcessOutput is Sendable
        // by using it in a context that requires Sendable
        let output: ProcessOutput = .message("test")
        Task {
            // If ProcessOutput weren't Sendable, this would be a compile error
            _ = output
        }
    }

    // MARK: - Edge Cases

    func testMessageWithEmptyString() {
        let output = ProcessOutput.message("")
        XCTAssertEqual(output, ProcessOutput.message(""))
    }

    func testErrorWithEmptyString() {
        let output = ProcessOutput.error("")
        XCTAssertEqual(output, ProcessOutput.error(""))
    }

    func testTerminatedWithNegativeCode() {
        let output = ProcessOutput.terminated(-1)
        XCTAssertEqual(output, ProcessOutput.terminated(-1))
        XCTAssertNotEqual(output, ProcessOutput.terminated(1))
    }

    func testTerminatedWithMaxInt32() {
        let output = ProcessOutput.terminated(Int32.max)
        XCTAssertEqual(output, ProcessOutput.terminated(Int32.max))
    }

    func testTerminatedWithMinInt32() {
        let output = ProcessOutput.terminated(Int32.min)
        XCTAssertEqual(output, ProcessOutput.terminated(Int32.min))
    }

    func testMessageWithUnicodeContent() {
        let unicodeMessage = "日本語テスト 🎮 émoji"
        XCTAssertEqual(ProcessOutput.message(unicodeMessage), ProcessOutput.message(unicodeMessage))
    }

    func testErrorWithMultilineContent() {
        let multiline = "Error line 1\nError line 2\nError line 3"
        XCTAssertEqual(ProcessOutput.error(multiline), ProcessOutput.error(multiline))
    }
}

// MARK: - FileHandle.nextLine Tests

final class FileHandleNextLineTests: XCTestCase {
    var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory.appending(path: "nextline_\(UUID().uuidString).txt")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }

    func testNextLineWithContent() throws {
        try Data("Hello, World!".utf8).write(to: tempURL)

        let handle = try FileHandle(forReadingFrom: tempURL)
        defer { try? handle.close() }

        let line = handle.nextLine()
        XCTAssertEqual(line, "Hello, World!")
    }

    func testNextLineWithEmptyFile() throws {
        try Data().write(to: tempURL)

        let handle = try FileHandle(forReadingFrom: tempURL)
        defer { try? handle.close() }

        let line = handle.nextLine()
        XCTAssertNil(line)
    }

    func testNextLineWithMultipleLines() throws {
        try Data("Line 1\nLine 2\nLine 3".utf8).write(to: tempURL)

        let handle = try FileHandle(forReadingFrom: tempURL)
        defer { try? handle.close() }

        // First call gets all available data
        let line = handle.nextLine()
        XCTAssertNotNil(line)
        XCTAssertTrue(line?.contains("Line 1") ?? false)
    }

    func testNextLineWithUnicodeContent() throws {
        try Data("日本語テスト 🍷".utf8).write(to: tempURL)

        let handle = try FileHandle(forReadingFrom: tempURL)
        defer { try? handle.close() }

        let line = handle.nextLine()
        XCTAssertEqual(line, "日本語テスト 🍷")
    }
}
