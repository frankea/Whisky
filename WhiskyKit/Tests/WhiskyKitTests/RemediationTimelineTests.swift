//
//  RemediationTimelineTests.swift
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

final class RemediationTimelineTests: XCTestCase {
    private var bottleURL: URL!

    override func setUpWithError() throws {
        bottleURL = FileManager.default.temporaryDirectory
            .appending(path: "RemediationTimelineTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: bottleURL)
    }

    private func makeEntry(_ index: Int, before: String? = nil, after: String? = nil) -> RemediationTimelineEntry {
        RemediationTimelineEntry(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)),
            actionId: "action-\(index)",
            actionTitle: "Action \(index)",
            beforeValue: before,
            afterValue: after
        )
    }

    // MARK: - In-memory timeline

    func testRemediationTimelineFIFO() {
        var timeline = RemediationTimeline()
        XCTAssertTrue(timeline.isEmpty)

        // Add 11 entries; first should be evicted
        for index in 0 ..< 11 {
            timeline.record(makeEntry(index, before: "before-\(index)", after: "after-\(index)"))
        }

        XCTAssertEqual(timeline.entries.count, RemediationTimeline.maxEntries)
        // First entry (action-0) should have been evicted
        XCTAssertEqual(timeline.entries.first?.actionId, "action-1")
        XCTAssertEqual(timeline.entries.last?.actionId, "action-10")
    }

    func testRemediationTimelineRoundTrip() throws {
        var timeline = RemediationTimeline()
        timeline.record(RemediationTimelineEntry(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            actionId: "install-vcredist",
            actionTitle: "Install Visual C++ Redistributable",
            beforeValue: "not installed",
            afterValue: "installed"
        ))

        let url = bottleURL.appending(path: "timeline.plist")
        try timeline.save(to: url)
        let loaded = RemediationTimeline.load(from: url)

        XCTAssertEqual(loaded.entries.count, 1)
        XCTAssertEqual(loaded.entries.first?.actionId, "install-vcredist")
        XCTAssertEqual(loaded.entries.first?.actionTitle, "Install Visual C++ Redistributable")
        XCTAssertEqual(loaded.entries.first?.beforeValue, "not installed")
        XCTAssertEqual(loaded.entries.first?.afterValue, "installed")
    }

    func testRemediationTimelineClear() {
        var timeline = RemediationTimeline()
        timeline.record(makeEntry(0))
        XCTAssertFalse(timeline.isEmpty)

        timeline.clear()
        XCTAssertTrue(timeline.isEmpty)
    }

    // MARK: - Stored per program

    func testUrlMatchesProgramName() {
        // Program.name is the executable's file name, extension included, and
        // the export sheet looks the file up under that name.
        let programURL = bottleURL.appending(path: "drive_c/Games/My Game.exe")
        let url = RemediationTimeline.url(forProgramAt: programURL, inBottleAt: bottleURL)

        XCTAssertEqual(url.lastPathComponent, "My Game.exe.remediation-timeline.plist")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "Program Settings")
        XCTAssertEqual(
            url.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL,
            bottleURL.standardizedFileURL
        )
    }

    func testRecordCreatesProgramSettingsFile() throws {
        let programURL = bottleURL.appending(path: "drive_c/Game.exe")
        let settingsFolder = bottleURL.appending(path: "Program Settings")
        XCTAssertFalse(FileManager.default.fileExists(atPath: settingsFolder.path(percentEncoded: false)))

        RemediationTimeline.record(
            RemediationTimelineEntry(
                timestamp: Date(),
                actionId: "enable-dxr",
                actionTitle: "Enable DirectX Raytracing",
                beforeValue: "false",
                afterValue: "true"
            ),
            forProgramAt: programURL,
            inBottleAt: bottleURL
        )

        let fileURL = settingsFolder.appending(path: "Game.exe.remediation-timeline.plist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)))
        let loaded = RemediationTimeline.load(from: fileURL)
        XCTAssertEqual(loaded.entries.count, 1)
        let entry = try XCTUnwrap(loaded.entries.first)
        XCTAssertEqual(entry.actionId, "enable-dxr")
        XCTAssertEqual(entry.actionTitle, "Enable DirectX Raytracing")
        XCTAssertEqual(entry.beforeValue, "false")
        XCTAssertEqual(entry.afterValue, "true")
    }

    func testRecordAppendsAcrossCallsAndCapsAtMax() {
        let programURL = bottleURL.appending(path: "drive_c/Game.exe")
        for index in 0 ..< 12 {
            RemediationTimeline.record(makeEntry(index), forProgramAt: programURL, inBottleAt: bottleURL)
        }

        let loaded = RemediationTimeline.load(
            from: RemediationTimeline.url(forProgramAt: programURL, inBottleAt: bottleURL)
        )
        XCTAssertEqual(loaded.entries.count, RemediationTimeline.maxEntries)
        XCTAssertEqual(loaded.entries.first?.actionId, "action-2")
        XCTAssertEqual(loaded.entries.last?.actionId, "action-11")
    }

    func testLoadIgnoresLegacyKeys() throws {
        // The original entry shape also carried a bottle identifier and the
        // program's full path; a file in that shape must still load.
        let legacy: [String: Any] = [
            "entries": [
                [
                    "timestamp": Date(timeIntervalSince1970: 1_700_000_000),
                    "actionId": "enable-dxr",
                    "actionTitle": "Enable DirectX Raytracing",
                    "beforeValue": "false",
                    "afterValue": "true",
                    "bottleIdentifier": "bottle-1",
                    "programPath": "/Users/someone/Game.exe"
                ]
            ]
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: legacy, format: .xml, options: 0)
        let url = bottleURL.appending(path: "legacy.plist")
        try data.write(to: url)

        let loaded = RemediationTimeline.load(from: url)
        XCTAssertEqual(loaded.entries.count, 1)
        XCTAssertEqual(loaded.entries.first?.actionId, "enable-dxr")
        XCTAssertEqual(loaded.entries.first?.afterValue, "true")
    }
}
