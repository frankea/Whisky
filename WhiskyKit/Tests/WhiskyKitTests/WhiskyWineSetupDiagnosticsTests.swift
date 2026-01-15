//
//  WhiskyWineSetupDiagnosticsTests.swift
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

final class WhiskyWineSetupDiagnosticsTests: XCTestCase {
    func testReportIncludesHeaderAndStage() {
        var diagnostics = WhiskyWineSetupDiagnostics()
        diagnostics.record("Test event")

        let report = diagnostics.reportString(stage: "download", error: "boom")

        XCTAssertTrue(report.contains("WhiskyWine Setup Diagnostics"))
        XCTAssertTrue(report.contains("Stage: download"))
        XCTAssertTrue(report.contains("Error: boom"))
        XCTAssertTrue(report.contains("[NETWORK]"))
        XCTAssertTrue(report.contains("[EVENTS]"))
    }

    func testEventTruncationKeepsMostRecent() {
        var diagnostics = WhiskyWineSetupDiagnostics()
        let overflowEventCount = 5
        let totalCount = WhiskyWineSetupDiagnostics.maxEventCount + overflowEventCount
        let expectedFirstKeptEventIndex = overflowEventCount
        let expectedLastKeptEventIndex = totalCount - 1

        for index in 0..<totalCount {
            diagnostics.record("event-\(index)")
        }

        XCTAssertEqual(diagnostics.events.count, WhiskyWineSetupDiagnostics.maxEventCount)
        XCTAssertTrue(diagnostics.events.first?.contains("event-\(expectedFirstKeptEventIndex)") ?? false)
        XCTAssertTrue(diagnostics.events.last?.contains("event-\(expectedLastKeptEventIndex)") ?? false)
    }

    func testReportTruncationRespectsLimit() {
        var diagnostics = WhiskyWineSetupDiagnostics()
        let longMessage = String(repeating: "A", count: 200)
        let totalCount = WhiskyWineSetupDiagnostics.maxEventCount * 2

        for index in 0..<totalCount {
            diagnostics.record("event-\(index) \(longMessage)")
        }

        let report = diagnostics.reportString(stage: "download")
        XCTAssertLessThanOrEqual(report.utf8.count, WhiskyWineSetupDiagnostics.maxReportBytes)
        XCTAssertTrue(report.contains("event-\(totalCount - 1)"))
    }

    func testResetClearsSessionAndEvents() {
        var diagnostics = WhiskyWineSetupDiagnostics()
        diagnostics.record("event")
        diagnostics.versionPlistURL = "https://example.com/version.plist"
        diagnostics.downloadURL = "https://example.com/whiskywine.tar.gz"
        diagnostics.downloadStartedAt = Date()
        diagnostics.installStartedAt = Date()

        let previousSession = diagnostics.sessionID
        diagnostics.reset()

        XCTAssertNotEqual(diagnostics.sessionID, previousSession)
        XCTAssertTrue(diagnostics.events.isEmpty)
        XCTAssertNil(diagnostics.versionPlistURL)
        XCTAssertNil(diagnostics.downloadURL)
        XCTAssertNil(diagnostics.downloadStartedAt)
        XCTAssertNil(diagnostics.installStartedAt)
    }

    func testResetDownloadStatePreservesInstallTimestamps() {
        var diagnostics = WhiskyWineSetupDiagnostics()
        let installStart = Date()
        let installFinish = Date().addingTimeInterval(1)
        diagnostics.installStartedAt = installStart
        diagnostics.installFinishedAt = installFinish
        diagnostics.recordInstallAttempt(
            startedAt: installStart,
            finishedAt: installFinish,
            succeeded: false
        )
        diagnostics.downloadStartedAt = Date()
        diagnostics.downloadFinishedAt = Date()

        diagnostics.resetDownloadState(reason: "Retry requested")

        XCTAssertEqual(diagnostics.installStartedAt, installStart)
        XCTAssertEqual(diagnostics.installFinishedAt, installFinish)
        XCTAssertEqual(diagnostics.installAttempts.count, 1)
        XCTAssertNil(diagnostics.downloadStartedAt)
        XCTAssertNil(diagnostics.downloadFinishedAt)
    }

    func testReportIncludesInstallAttemptsSection() {
        var diagnostics = WhiskyWineSetupDiagnostics()
        let start = Date(timeIntervalSince1970: 0)
        let finish = Date(timeIntervalSince1970: 5)
        diagnostics.recordInstallAttempt(startedAt: start, finishedAt: finish, succeeded: false)

        let report = diagnostics.reportString(stage: "install")

        XCTAssertTrue(report.contains("[INSTALL ATTEMPTS]"))
        XCTAssertTrue(report.contains("Attempt 1:"))
    }

    func testReportSanitizesURLQueries() {
        var diagnostics = WhiskyWineSetupDiagnostics()
        diagnostics.versionPlistURL = "https://example.com/version.plist?token=secret#fragment"
        diagnostics.downloadURL = "https://example.com/whiskywine.tar.gz?sig=abc123"

        let report = diagnostics.reportString(stage: "download")

        XCTAssertFalse(report.contains("token=secret"))
        XCTAssertFalse(report.contains("sig=abc123"))
        XCTAssertFalse(report.contains("#fragment"))
        XCTAssertTrue(report.contains("https://example.com/version.plist"))
        XCTAssertTrue(report.contains("https://example.com/whiskywine.tar.gz"))
    }
}
