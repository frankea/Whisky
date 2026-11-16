//
//  ProcessOutputSessionTests.swift
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

/// A process whose children inherit its stdout and stderr, as everything a
/// `wine start` launcher starts does, without Wine: the stream must finish when
/// the process exits, not when the last child does, and what the children write
/// later must still reach the log.
final class ProcessOutputSessionTests: XCTestCase {
    /// Well under the 30 seconds the child holding the output lives.
    private let promptly: TimeInterval = 10

    private var holderPIDs: [pid_t] = []

    override func tearDown() {
        for pid in holderPIDs {
            kill(pid, SIGKILL)
        }
        holderPIDs = []
        super.tearDown()
    }

    func testStreamFinishesWhenTheProcessExitsWhileAChildHoldsItsOutput() async throws {
        let (log, logURL) = try makeLog()
        let completion = ProcessOutputCompletion()
        let start = Date()

        let outputs = try await collect(
            script: #"echo started; (sleep 1; echo "late from child $((40+2))"; exec sleep 30) & echo "holder:$!""#,
            log: log, completion: completion
        )

        XCTAssertLessThan(Date().timeIntervalSince(start), promptly, "the stream waited for the child")
        XCTAssertEqual(outputs.first, .started)
        XCTAssertEqual(outputs.last, .terminated(0))
        XCTAssertTrue(stdout(of: outputs).contains("started\n"), "got \(outputs)")
        XCTAssertFalse(completion.isComplete, "the child still holds the output open")

        // The child's output after the exit still lands in the log.
        let late = await waitFor { (try? String(contentsOf: logURL, encoding: .utf8))?.contains("late from child 42") }
        XCTAssertTrue(late, "late output never reached the log")

        // The log is complete once the child is gone.
        killHolders()
        let closed = await waitFor { completion.isComplete }
        XCTAssertTrue(closed, "the output never closed after the child exited")
        let text = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertTrue(text.contains("started\n"))
        XCTAssertTrue(text.contains("late from child 42\n"))
    }

    /// A short helper run, such as `wine reg query`, whose Wine session starts
    /// services that inherit its output: all it wrote arrives before the stream ends.
    func testAllOutputWrittenBeforeTheExitArrivesBeforeTheStreamEnds() async throws {
        let start = Date()
        let outputs = try await collect(
            script: #"""
            i=0; while [ $i -lt 5000 ]; do echo "line $i"; i=$((i+1)); done
            echo "to stderr" >&2
            (exec sleep 30) & echo "holder:$!"
            """#,
            log: nil, completion: nil
        )

        XCTAssertLessThan(Date().timeIntervalSince(start), promptly, "the stream waited for the child")
        let lines = stdout(of: outputs).split(separator: "\n").filter { $0.hasPrefix("line ") }
        XCTAssertEqual(lines.count, 5_000)
        XCTAssertEqual(lines.last, "line 4999")
        XCTAssertTrue(stderr(of: outputs).contains("to stderr\n"))
        XCTAssertEqual(outputs.last, .terminated(0))
    }

    func testLateOutputIsDeliveredAndFinishesWhenTheOutputCloses() async throws {
        let (lateStream, lateContinuation) = AsyncStream.makeStream(of: ProcessOutput.self)
        let collector = Task {
            var collected: [ProcessOutput] = []
            for await output in lateStream {
                collected.append(output)
            }
            return collected
        }

        let (log, logURL) = try makeLog()
        let outputs = try await collect(
            script: #"(sleep 1; echo "late $((40+2))"; echo "late error $((40+2))" >&2; exec sleep 30) &"#
                + #" echo "holder:$!""#,
            log: log, completion: nil, lateOutput: lateContinuation
        )
        XCTAssertEqual(outputs.last, .terminated(0))
        XCTAssertFalse(stdout(of: outputs).contains("late"), "late output belongs to the late stream")

        // Once the child has written both lines, end it, which closes the output.
        let written = await waitFor { (try? String(contentsOf: logURL, encoding: .utf8))?.contains("late error 42") }
        XCTAssertTrue(written)
        killHolders()

        let late = await collector.value
        XCTAssertTrue(late.contains(.message("late 42\n")), "got \(late)")
        XCTAssertTrue(late.contains(.error("late error 42\n")), "got \(late)")
    }

    func testCompletionIsSignalledWhenNothingHoldsTheOutput() async throws {
        let (log, logURL) = try makeLog()
        let completion = ProcessOutputCompletion()

        let outputs = try await collect(script: "echo done", log: log, completion: completion)

        XCTAssertEqual(outputs.last, .terminated(0))
        let closed = await waitFor { completion.isComplete }
        XCTAssertTrue(closed)
        XCTAssertTrue(try String(contentsOf: logURL, encoding: .utf8).contains("done\n"))
    }

    func testCompletionWaitReturnsOnceCompleted() async {
        let completion = ProcessOutputCompletion()
        let waiter = Task { await completion.wait() }
        completion.complete()
        await waiter.value
        await completion.wait()
        XCTAssertTrue(completion.isComplete)
    }

    // MARK: - Helpers

    private func collect(
        script: String, log: FileHandle?, completion: ProcessOutputCompletion?,
        lateOutput: AsyncStream<ProcessOutput>.Continuation? = nil
    ) async throws -> [ProcessOutput] {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", script]

        var outputs: [ProcessOutput] = []
        let stream = try process.runStream(
            name: "sessionTest", fileHandle: log, completion: completion, lateOutput: lateOutput
        )
        for await output in stream {
            outputs.append(output)
        }
        recordHolders(from: stdout(of: outputs))
        return outputs
    }

    private func recordHolders(from text: String) {
        for line in text.split(separator: "\n") where line.hasPrefix("holder:") {
            if let pid = pid_t(line.dropFirst("holder:".count)) {
                holderPIDs.append(pid)
            }
        }
    }

    private func killHolders() {
        for pid in holderPIDs {
            kill(pid, SIGKILL)
        }
        holderPIDs = []
    }

    private func stdout(of outputs: [ProcessOutput]) -> String {
        outputs.compactMap { if case let .message(text) = $0 { text } else { nil } }.joined()
    }

    private func stderr(of outputs: [ProcessOutput]) -> String {
        outputs.compactMap { if case let .error(text) = $0 { text } else { nil } }.joined()
    }

    /// Polls `condition` until it holds or ``promptly`` passes.
    private func waitFor(_ condition: () -> Bool?) async -> Bool {
        let deadline = Date().addingTimeInterval(promptly)
        while Date() < deadline {
            if condition() == true {
                return true
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition() == true
    }

    private func makeLog() throws -> (FileHandle, URL) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "session-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return try Wine.makeLogFile(in: folder, date: .now)
    }
}
