//
//  WinePrefixDiagnosticsTests.swift
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

final class WinePrefixDiagnosticsTests: XCTestCase {
    func testReportIncludesHeaderAndPrefixState() {
        var diagnostics = WinePrefixDiagnostics()
        diagnostics.prefixPath = "/path/to/prefix"
        diagnostics.prefixExists = true
        diagnostics.driveCExists = true
        diagnostics.detectedUsername = "testuser"
        diagnostics.record("Test event")

        let report = diagnostics.reportString(error: "Test error")

        XCTAssertTrue(report.contains("Wine Prefix Diagnostics"))
        XCTAssertTrue(report.contains("Error: Test error"))
        XCTAssertTrue(report.contains("[PREFIX STATE]"))
        XCTAssertTrue(report.contains("Prefix path: /path/to/prefix"))
        XCTAssertTrue(report.contains("Detected username: testuser"))
        XCTAssertTrue(report.contains("[EVENTS]"))
    }

    func testEventTruncationKeepsMostRecent() {
        var diagnostics = WinePrefixDiagnostics()
        let overflowEventCount = 5
        let totalCount = WinePrefixDiagnostics.maxEventCount + overflowEventCount
        let expectedFirstKeptEventIndex = overflowEventCount
        let expectedLastKeptEventIndex = totalCount - 1

        for index in 0 ..< totalCount {
            diagnostics.record("event-\(index)")
        }

        XCTAssertEqual(diagnostics.events.count, WinePrefixDiagnostics.maxEventCount)
        XCTAssertTrue(diagnostics.events.first?.contains("event-\(expectedFirstKeptEventIndex)") ?? false)
        XCTAssertTrue(diagnostics.events.last?.contains("event-\(expectedLastKeptEventIndex)") ?? false)
    }

    func testReportTruncationRespectsLimit() {
        var diagnostics = WinePrefixDiagnostics()
        let longMessage = String(repeating: "A", count: 200)
        let totalCount = WinePrefixDiagnostics.maxEventCount * 2

        for index in 0 ..< totalCount {
            diagnostics.record("event-\(index) \(longMessage)")
        }

        let report = diagnostics.reportString()
        XCTAssertLessThanOrEqual(report.utf8.count, WinePrefixDiagnostics.maxReportBytes)
        // Most recent events should be preserved
        XCTAssertTrue(report.contains("event-\(totalCount - 1)"))
    }

    func testReportIncludesAppDataState() {
        var diagnostics = WinePrefixDiagnostics()
        diagnostics.appDataExists = true
        diagnostics.roamingExists = true
        diagnostics.localAppDataExists = false

        let report = diagnostics.reportString()

        XCTAssertTrue(report.contains("AppData exists: true"))
        XCTAssertTrue(report.contains("AppData/Roaming exists: true"))
        XCTAssertTrue(report.contains("AppData/Local exists: false"))
    }

    func testSessionIDIsUnique() {
        let diagnostics1 = WinePrefixDiagnostics()
        let diagnostics2 = WinePrefixDiagnostics()

        XCTAssertNotEqual(diagnostics1.sessionID, diagnostics2.sessionID)
    }

    func testReportWithoutErrorOmitsErrorLine() {
        var diagnostics = WinePrefixDiagnostics()
        diagnostics.record("Test")

        let report = diagnostics.reportString()

        XCTAssertFalse(report.contains("Error:"))
    }

    func testEventsAreTimestamped() {
        var diagnostics = WinePrefixDiagnostics()
        diagnostics.record("Test message")

        // Events should contain ISO8601 timestamp format
        XCTAssertTrue(diagnostics.events.first?.contains("[") ?? false)
        XCTAssertTrue(diagnostics.events.first?.contains("]") ?? false)
        XCTAssertTrue(diagnostics.events.first?.contains("Test message") ?? false)
    }
}
