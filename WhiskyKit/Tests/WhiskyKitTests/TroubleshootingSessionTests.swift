//
//  TroubleshootingSessionTests.swift
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

final class TroubleshootingSessionTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        tempDir = nil
    }

    private func makeNode(id: String, phase: FlowPhase = .checks) -> FlowStepNode {
        FlowStepNode(id: id, type: .check, phase: phase, title: "Node \(id)")
    }

    // MARK: - Session mutations

    func testPushStepAppendsHistoryAndTracksCurrentNode() {
        var session = TroubleshootingSession()

        session.pushStep(makeNode(id: "a"))
        session.pushStep(makeNode(id: "b", phase: .fix))

        XCTAssertEqual(session.stepHistory.map(\.nodeId), ["a", "b"])
        XCTAssertEqual(session.currentNodeId, "b")
        XCTAssertEqual(session.stepHistory.last?.phase, .fix)
    }

    func testRecordCheckResultAttachesToMatchingStep() {
        var session = TroubleshootingSession()
        session.pushStep(makeNode(id: "a"))
        session.pushStep(makeNode(id: "b"))

        let result = CheckResult(outcome: .fail, summary: "nope")
        session.recordCheckResult(nodeId: "a", result: result)

        XCTAssertEqual(session.checkResults["a"]?.outcome, .fail)
        XCTAssertEqual(session.stepHistory[0].checkResult?.outcome, .fail)
        XCTAssertNil(session.stepHistory[1].checkResult)
    }

    func testFailedFixCountCountsOnlyFailures() {
        var session = TroubleshootingSession()
        for (index, result) in [FixResult.failed, .applied, .failed, .verified].enumerated() {
            session.recordFixAttempt(FixAttempt(
                fixId: "fix.\(index)", timestamp: Date(), beforeValue: nil, afterValue: nil, result: result
            ))
        }

        XCTAssertEqual(session.failedFixCount, 2)
    }

    func testRecordBranchKeepsDecisionOrder() {
        var session = TroubleshootingSession()

        session.recordBranch(from: "a", targetNodeId: "b", reason: "pass")
        session.recordBranch(from: "b", targetNodeId: "c")

        XCTAssertEqual(session.branchDecisions.map(\.fromNodeId), ["a", "b"])
        XCTAssertEqual(session.branchDecisions.first?.reason, "pass")
    }

    func testSessionCodableRoundTrip() throws {
        var session = TroubleshootingSession(bottleURL: tempDir)
        session.pushStep(makeNode(id: "a"))
        session.recordCheckResult(nodeId: "a", result: CheckResult(outcome: .pass, summary: "ok"))
        session.symptomCategory = .graphics
        session.outcome = .resolved

        let data = try PropertyListEncoder().encode(session)
        let decoded = try PropertyListDecoder().decode(TroubleshootingSession.self, from: data)

        XCTAssertEqual(decoded.id, session.id)
        XCTAssertEqual(decoded.stepHistory.map(\.nodeId), ["a"])
        XCTAssertEqual(decoded.checkResults["a"]?.outcome, .pass)
        XCTAssertEqual(decoded.symptomCategory, .graphics)
        XCTAssertEqual(decoded.outcome, .resolved)
    }

    // MARK: - Session store

    func testSaveWritesActiveSessionIntoBottleDir() throws {
        let store = TroubleshootingSessionStore()
        let session = TroubleshootingSession(bottleURL: tempDir)

        store.save(session)

        let file = tempDir.appendingPathComponent(TroubleshootingSessionStore.activeSessionFileName)
        let data = try Data(contentsOf: file)
        let decoded = try PropertyListDecoder().decode(TroubleshootingSession.self, from: data)
        XCTAssertEqual(decoded.id, session.id)
    }

    func testSaveWithoutBottleURLIsSafeNoOp() {
        let store = TroubleshootingSessionStore()

        store.save(TroubleshootingSession())
        // Nothing to assert on disk; the point is no crash and no stray file
        // in the current directory.
    }

    func testCompleteSessionWritesHistoryAndRemovesActiveFile() {
        let store = TroubleshootingSessionStore()
        var session = TroubleshootingSession(bottleURL: tempDir)
        session.symptomCategory = .audio
        session.outcome = .resolved
        session.recordCheckResult(nodeId: "a", result: CheckResult(outcome: .fail, summary: "finding"))
        store.save(session)

        store.completeSession(session)

        let history = TroubleshootingHistory.load(from: tempDir)
        XCTAssertEqual(history.entries.count, 1)
        XCTAssertEqual(history.entries.first?.symptomCategory, .audio)
        XCTAssertEqual(history.entries.first?.outcome, .resolved)
        XCTAssertEqual(history.entries.first?.primaryFindings, ["finding"])

        let activeFile = tempDir.appendingPathComponent(TroubleshootingSessionStore.activeSessionFileName)
        XCTAssertFalse(FileManager.default.fileExists(atPath: activeFile.path(percentEncoded: false)))
    }

    func testCompleteSessionAppendsToExistingHistory() {
        let store = TroubleshootingSessionStore()
        var first = TroubleshootingSession(bottleURL: tempDir)
        first.outcome = .resolved
        var second = TroubleshootingSession(bottleURL: tempDir)
        second.outcome = .unresolved

        store.completeSession(first)
        store.completeSession(second)

        let history = TroubleshootingHistory.load(from: tempDir)
        XCTAssertEqual(history.entries.count, 2)
        XCTAssertEqual(history.entries.map(\.outcome), [.resolved, .unresolved])
    }
}
