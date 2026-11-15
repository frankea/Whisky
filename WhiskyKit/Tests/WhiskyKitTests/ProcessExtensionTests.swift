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

// MARK: - FileHandle.readChunk Tests

final class FileHandleReadChunkTests: XCTestCase {
    var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory.appending(path: "readchunk_\(UUID().uuidString).txt")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }

    func testReturnsDataForContent() throws {
        try Data("Hello, World!".utf8).write(to: tempURL)

        let handle = try FileHandle(forReadingFrom: tempURL)
        defer { try? handle.close() }

        XCTAssertEqual(handle.readChunk(), .data(Data("Hello, World!".utf8)))
    }

    /// An empty read is EOF, reported distinctly so the readability handler
    /// can remove itself instead of spinning on it (whisky-app/whisky#917).
    func testReturnsEndOfFileForEmptyRead() throws {
        try Data().write(to: tempURL)

        let handle = try FileHandle(forReadingFrom: tempURL)
        defer { try? handle.close() }

        XCTAssertEqual(handle.readChunk(), .endOfFile)
    }

    /// A pipe that is open but empty must not block a non-blocking reader, nor read as EOF.
    func testReturnsWouldBlockForAnEmptyOpenPipe() {
        let pipe = Pipe()
        let descriptor = pipe.fileHandleForReading.fileDescriptor
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)

        XCTAssertEqual(pipe.fileHandleForReading.readChunk(), .wouldBlock)

        pipe.fileHandleForWriting.write(Data("late".utf8))
        XCTAssertEqual(pipe.fileHandleForReading.readChunk(), .data(Data("late".utf8)))

        try? pipe.fileHandleForWriting.close()
        XCTAssertEqual(pipe.fileHandleForReading.readChunk(), .endOfFile)
    }

    func testReadsAtMostMaxCount() throws {
        try Data("Line 1\nLine 2\nLine 3".utf8).write(to: tempURL)

        let handle = try FileHandle(forReadingFrom: tempURL)
        defer { try? handle.close() }

        XCTAssertEqual(handle.readChunk(maxCount: 7), .data(Data("Line 1\n".utf8)))
    }
}

// MARK: - UTF8ChunkDecoder Tests

final class UTF8ChunkDecoderTests: XCTestCase {
    func testDecodesWholeText() {
        var decoder = UTF8ChunkDecoder()
        XCTAssertEqual(decoder.decode(Data("日本語テスト 🍷".utf8)), "日本語テスト 🍷")
        XCTAssertEqual(decoder.flush(), "")
    }

    /// A character split across two reads arrives whole with the second read.
    func testHoldsBackACharacterSplitAcrossReads() {
        let bytes = Array("a🍷b".utf8)
        var decoder = UTF8ChunkDecoder()

        XCTAssertEqual(decoder.decode(Data(bytes[0 ..< 3])), "a")
        XCTAssertEqual(decoder.decode(Data(bytes[3...])), "🍷b")
        XCTAssertEqual(decoder.flush(), "")
    }

    /// Bytes that aren't UTF-8 become replacement characters rather than
    /// taking the rest of their chunk with them.
    func testKeepsTheRestOfAChunkWithInvalidBytes() {
        var decoder = UTF8ChunkDecoder()
        XCTAssertEqual(decoder.decode(Data([0x6F, 0x6B, 0xFF, 0x21, 0x0A])), "ok\u{FFFD}!\n")
    }

    func testFlushDecodesAnUnfinishedCharacter() {
        var decoder = UTF8ChunkDecoder()
        XCTAssertEqual(decoder.decode(Data([0x61, 0xE6, 0x97])), "a")
        XCTAssertEqual(decoder.flush(), "\u{FFFD}")
    }
}

// MARK: - Process.runStream Integration Tests

final class ProcessRunStreamTests: XCTestCase {
    /// Collects every `ProcessOutput` a short-lived `/bin/sh -c <script>` emits.
    private func collectOutput(script: String) async throws -> [ProcessOutput] {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", script]

        var outputs: [ProcessOutput] = []
        let stream = try process.runStream(name: "runStreamTest", fileHandle: nil)
        for await output in stream {
            outputs.append(output)
        }
        return outputs
    }

    func testHappyPathYieldsOutputAndTermination() async throws {
        let outputs = try await collectOutput(script: "printf 'hello\\n'")

        XCTAssertEqual(outputs.first, .started)
        XCTAssertEqual(outputs.last, .terminated(0))
        XCTAssertTrue(
            outputs.contains { if case let .message(line) = $0 { line.contains("hello") } else { false } },
            "expected a stdout message containing 'hello', got \(outputs)"
        )
    }

    /// The regression case: the child closes stdout/stderr while still running,
    /// so the pipe reaches EOF before termination. Output must still arrive and
    /// the stream must finish cleanly (and promptly — no hang from the spin path).
    func testEOFBeforeExitStillDeliversOutputAndTerminates() async throws {
        let outputs = try await collectOutput(
            script: "printf 'early\\n'; exec 1>&-; exec 2>&-; sleep 0.3"
        )

        XCTAssertEqual(outputs.last, .terminated(0))
        XCTAssertTrue(
            outputs.contains { if case let .message(line) = $0 { line.contains("early") } else { false } },
            "output written before the pipe closed must not be lost, got \(outputs)"
        )
    }

    func testSilentProcessTerminatesWithoutSpuriousOutput() async throws {
        let outputs = try await collectOutput(script: "sleep 0.2")

        XCTAssertEqual(outputs.first, .started)
        XCTAssertEqual(outputs.last, .terminated(0))
        XCTAssertFalse(
            outputs.contains { if case .message = $0 { true } else if case .error = $0 { true } else { false } },
            "a silent process should produce no message/error output, got \(outputs)"
        )
    }
}
