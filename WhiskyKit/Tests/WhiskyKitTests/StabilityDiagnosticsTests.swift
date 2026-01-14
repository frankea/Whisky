//
//  StabilityDiagnosticsTests.swift
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

@MainActor
final class StabilityDiagnosticsTests: XCTestCase {
    func testReportGenerationWithMissingLogsFolder() async throws {
        let bottleURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bottleURL) }

        let bottle = Bottle(bottleUrl: bottleURL, inFlight: false, isAvailable: true)

        let missingLogsFolder = bottleURL.appendingPathComponent("does-not-exist")
        let config = StabilityDiagnostics.Configuration(
            bundle: Bundle(for: StabilityDiagnosticsTests.self),
            logsFolder: missingLogsFolder,
            now: { Date(timeIntervalSince1970: 0) }
        )

        let report = await StabilityDiagnostics.generateDiagnosticReport(for: bottle, config: config)
        XCTAssertTrue(report.contains("Whisky Stability Diagnostics Report"))
        XCTAssertTrue(report.contains("[LOGS]"))
        XCTAssertTrue(report.contains("Logs Folder Status: Not found"))
    }

    func testReportGenerationWithEmptyLogsFolder() async throws {
        let bottleURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bottleURL) }

        let bottle = Bottle(bottleUrl: bottleURL, inFlight: false, isAvailable: true)

        let logsFolder = bottleURL.appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: logsFolder, withIntermediateDirectories: true)

        let config = StabilityDiagnostics.Configuration(
            bundle: Bundle(for: StabilityDiagnosticsTests.self),
            logsFolder: logsFolder,
            now: Date.init
        )

        let report = await StabilityDiagnostics.generateDiagnosticReport(for: bottle, config: config)
        XCTAssertTrue(report.contains("Log Files: None found"))
    }

    func testTailHandlesInvalidUTF8() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let logURL = tempURL.appendingPathComponent("invalid.log")

        // Write bytes that are not valid UTF-8
        let bytes: [UInt8] = [0xFF, 0xFE, 0xFF, 0x00, 0xC3, 0x28]
        try Data(bytes).write(to: logURL)

        let tail = StabilityDiagnostics.tailOfLogFile(logURL)
        XCTAssertTrue(tail.contains("not UTF-8") || tail.contains("Failed to read"))
    }

    func testTailKeepsLastLinesBounded() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let logURL = tempURL.appendingPathComponent("many-lines.log")

        // 250 lines: tail should return <= 200 lines.
        let content = (0 ..< 250).map { "line-\($0)" }.joined(separator: "\n")
        try content.write(to: logURL, atomically: true, encoding: .utf8)

        let tail = StabilityDiagnostics.tailOfLogFile(logURL)
        let lineCount = tail.split(separator: "\n", omittingEmptySubsequences: false).count
        XCTAssertLessThanOrEqual(lineCount, 200)
        XCTAssertTrue(tail.contains("line-249"))
        XCTAssertFalse(tail.contains("line-0"))
    }
}
