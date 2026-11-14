//
//  RemediationHistoryExportTests.swift
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

/// The "Include remediation history" option, end to end through the public
/// export entry points: Copy Report and the ZIP's `report.md`.
final class RemediationHistoryExportTests: XCTestCase {
    private var root = URL(filePath: "/dev/null")

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appending(path: "RemediationHistoryExportTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    private var diagnosis: CrashDiagnosis {
        CrashDiagnosis(
            matches: [],
            categoryCounts: [:],
            primaryCategory: nil,
            primaryConfidence: nil,
            headline: nil,
            exitCode: 1,
            applicableRemediationIds: []
        )
    }

    private var timeline: RemediationTimeline {
        var timeline = RemediationTimeline()
        timeline.record(RemediationTimelineEntry(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            actionId: "enable-dxr",
            actionTitle: "Enable DirectX Raytracing",
            beforeValue: "false",
            afterValue: "true"
        ))
        return timeline
    }

    @MainActor
    private func makeProgram() throws -> (bottle: Bottle, program: Program) {
        let bottleURL = root.appending(path: "Bottle")
        let programURL = bottleURL.appending(path: "drive_c/game.exe")
        try FileManager.default.createDirectory(
            at: programURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("MZ".utf8).write(to: programURL)
        let bottle = Bottle(bottleUrl: bottleURL)
        return (bottle, Program(url: programURL, bottle: bottle, peFile: nil))
    }

    // MARK: - Copy Report

    @MainActor
    func testCopyReportListsHistoryWhenEnabled() async throws {
        let (bottle, program) = try makeProgram()
        let markdown = await DiagnosticExporter.generateMarkdownReport(
            diagnosis: diagnosis,
            bottle: bottle,
            program: program,
            timeline: timeline,
            options: ExportOptions(includeRemediationHistory: true)
        )
        XCTAssertTrue(markdown.contains("### Remediation History"))
        XCTAssertTrue(markdown.contains("`enable-dxr`"))
    }

    @MainActor
    func testCopyReportLeavesHistoryOutWhenDisabled() async throws {
        let (bottle, program) = try makeProgram()
        let markdown = await DiagnosticExporter.generateMarkdownReport(
            diagnosis: diagnosis,
            bottle: bottle,
            program: program,
            timeline: timeline,
            options: ExportOptions(includeRemediationHistory: false)
        )
        XCTAssertFalse(markdown.contains("### Remediation History"))
        XCTAssertFalse(markdown.contains("enable-dxr"))
    }

    // MARK: - ZIP

    /// Exports a ZIP with `options` and returns the folder it was extracted to.
    @MainActor
    private func exportAndExtract(options: ExportOptions) async throws -> URL {
        let (bottle, program) = try makeProgram()
        let zip = root.appending(path: "Report.zip")
        try await DiagnosticExporter.exportZIP(
            diagnosis: diagnosis,
            bottle: bottle,
            program: program,
            logFileURL: nil,
            timeline: timeline,
            options: options,
            to: zip
        )

        let extracted = root.appending(path: "extracted")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path(percentEncoded: false), extracted.path(percentEncoded: false)]
        try ditto.run()
        ditto.waitUntilExit()
        XCTAssertEqual(ditto.terminationStatus, 0)
        // The archive holds the content folder's files at its top level.
        return extracted
    }

    @MainActor
    func testZIPReportListsHistoryWhenEnabled() async throws {
        let content = try await exportAndExtract(options: ExportOptions(includeRemediationHistory: true))

        let report = try String(contentsOf: content.appending(path: "report.md"), encoding: .utf8)
        XCTAssertTrue(report.contains("### Remediation History"))
        XCTAssertTrue(report.contains("`enable-dxr`"))
        let history = content.appending(path: "remediation-history.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: history.path(percentEncoded: false)))
    }

    @MainActor
    func testZIPReportLeavesHistoryOutWhenDisabled() async throws {
        let content = try await exportAndExtract(options: ExportOptions(includeRemediationHistory: false))

        let report = try String(contentsOf: content.appending(path: "report.md"), encoding: .utf8)
        XCTAssertFalse(report.contains("### Remediation History"))
        let history = content.appending(path: "remediation-history.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: history.path(percentEncoded: false)))
    }

    func testHistoryValuesAreRedactedUnlessSensitiveDetailsAreAsked() throws {
        let logPath = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/winetricks.log").path(percentEncoded: false)
        var timeline = RemediationTimeline()
        timeline.record(RemediationTimelineEntry(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            actionId: "install-vcrun2019",
            actionTitle: "Install Visual C++ 2019",
            beforeValue: nil,
            afterValue: "failed: \(logPath)"
        ))
        let redactedValue = "failed: /Users/<redacted>/Library/winetricks.log"

        let section = DiagnosticExporter.generateRemediationHistorySection(
            timeline: timeline,
            options: ExportOptions(includeRemediationHistory: true)
        )
        XCTAssertFalse(section.contains(logPath))
        XCTAssertTrue(section.contains(redactedValue))

        let json = try DiagnosticExporter.remediationHistoryJSON(
            DiagnosticExporter.exportedTimeline(timeline, options: ExportOptions())
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let exported = try decoder.decode(RemediationTimeline.self, from: json)
        XCTAssertEqual(exported.entries.first?.afterValue, redactedValue)

        let sensitive = DiagnosticExporter.exportedTimeline(
            timeline,
            options: ExportOptions(includeSensitiveDetails: true)
        )
        XCTAssertEqual(sensitive.entries.first?.afterValue, "failed: \(logPath)")
    }
}
