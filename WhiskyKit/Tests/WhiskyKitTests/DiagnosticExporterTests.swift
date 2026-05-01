//
//  DiagnosticExporterTests.swift
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

final class DiagnosticExporterTests: XCTestCase {
    // MARK: - Redactor Tests

    func testRedactorHomePaths() {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        let normalizedHome = homePath.hasSuffix("/") ? String(homePath.dropLast()) : homePath
        let input = "\(normalizedHome)/Documents/test.txt"
        let result = Redactor.redactHomePaths(input)
        XCTAssertEqual(result, "/Users/<redacted>/Documents/test.txt")
        XCTAssertFalse(result.contains(normalizedHome))
    }

    func testRedactorHomePathsMultipleOccurrences() {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        let normalizedHome = homePath.hasSuffix("/") ? String(homePath.dropLast()) : homePath
        let input = "prefix=\(normalizedHome)/A suffix=\(normalizedHome)/B"
        let result = Redactor.redactHomePaths(input)
        XCTAssertFalse(result.contains(normalizedHome))
        XCTAssertTrue(result.contains("/Users/<redacted>/A"))
        XCTAssertTrue(result.contains("/Users/<redacted>/B"))
    }

    func testRedactorSensitiveKeys() {
        let env: [String: String] = [
            "PATH": "/usr/bin",
            "OPENAI_API_KEY": "sk-secret-123",
            "AUTH_TOKEN": "bearer-abc",
            "SECRET_VALUE": "hidden",
            "MY_PASSWORD": "pass123",
            "WINEPREFIX": "/some/path"
        ]
        let result = Redactor.redactEnvironment(env)

        // Sensitive keys should be removed
        XCTAssertNil(result["OPENAI_API_KEY"])
        XCTAssertNil(result["AUTH_TOKEN"])
        XCTAssertNil(result["SECRET_VALUE"])
        XCTAssertNil(result["MY_PASSWORD"])

        // Non-sensitive keys should be kept
        XCTAssertNotNil(result["PATH"])
        XCTAssertNotNil(result["WINEPREFIX"])
    }

    func testRedactorIncludeSensitive() {
        let env: [String: String] = [
            "PATH": "/usr/bin",
            "OPENAI_API_KEY": "sk-secret-123",
            "AUTH_TOKEN": "bearer-abc"
        ]
        let result = Redactor.redactEnvironment(env, includeSensitive: true)

        // All keys should be kept when includeSensitive is true
        XCTAssertNotNil(result["OPENAI_API_KEY"])
        XCTAssertNotNil(result["AUTH_TOKEN"])
        XCTAssertNotNil(result["PATH"])
    }

    func testRedactorEnvironmentRedactsHomePaths() {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        let normalizedHome = homePath.hasSuffix("/") ? String(homePath.dropLast()) : homePath
        let env = [
            "WINEPREFIX": "\(normalizedHome)/Library/Bottles/default"
        ]
        let result = Redactor.redactEnvironment(env)
        XCTAssertNotNil(result["WINEPREFIX"])
        XCTAssertTrue(result["WINEPREFIX"]?.contains("<redacted>") ?? false)
        XCTAssertFalse(result["WINEPREFIX"]?.contains(normalizedHome) ?? true)
    }

    func testRedactorSensitiveKeyCaseInsensitive() {
        let env: [String: String] = [
            "api_key": "value1",
            "Api_Token": "value2",
            "my_secret": "value3",
            "password_hash": "value4",
            "oauth_auth": "value5"
        ]
        let result = Redactor.redactEnvironment(env)

        // All should be removed (case-insensitive match)
        XCTAssertNil(result["api_key"])
        XCTAssertNil(result["Api_Token"])
        XCTAssertNil(result["my_secret"])
        XCTAssertNil(result["password_hash"])
        XCTAssertNil(result["oauth_auth"])
    }

    func testRedactorLogText() {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        let normalizedHome = homePath.hasSuffix("/") ? String(homePath.dropLast()) : homePath
        let logText = """
        wine: loading \(normalizedHome)/Library/Bottles/test/drive_c/game.exe
        fixme:ntdll:NtQuerySystemInformation
        """
        let result = Redactor.redactLogText(logText)
        XCTAssertFalse(result.contains(normalizedHome))
        XCTAssertTrue(result.contains("/Users/<redacted>/Library/Bottles/test/drive_c/game.exe"))
    }

    // MARK: - DiagnosisHistory Tests

    func testDiagnosisHistoryFIFO() {
        var history = DiagnosisHistory()
        XCTAssertTrue(history.isEmpty)

        // Add 6 entries; first should be evicted
        for index in 0 ..< 6 {
            let entry = DiagnosisHistoryEntry(
                timestamp: Date(),
                logFileRef: "log-\(index).log",
                primaryCategory: .coreCrashFatal,
                confidenceTier: .high,
                topSignatures: ["sig-\(index)"],
                remediationCardIds: [],
                wineDebugPreset: nil,
                bottleIdentifier: "bottle-1",
                programPath: "/game.exe"
            )
            history.append(entry)
        }

        XCTAssertEqual(history.entries.count, DiagnosisHistory.maxEntries)
        // First entry (log-0) should have been evicted
        XCTAssertEqual(history.entries.first?.logFileRef, "log-1.log")
        XCTAssertEqual(history.entries.last?.logFileRef, "log-5.log")
    }

    func testDiagnosisHistoryRoundTrip() throws {
        var history = DiagnosisHistory()
        let entry = DiagnosisHistoryEntry(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            logFileRef: "test.log",
            primaryCategory: .graphics,
            confidenceTier: .medium,
            topSignatures: ["gpu-device-lost", "metal-validation"],
            remediationCardIds: ["switch-backend"],
            wineDebugPreset: .crash,
            bottleIdentifier: "bottle-abc",
            programPath: "/path/to/game.exe"
        )
        history.append(entry)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-diagnosis-history-\(UUID()).plist")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try history.save(to: tempURL)
        let loaded = DiagnosisHistory.load(from: tempURL)

        XCTAssertEqual(loaded.entries.count, 1)
        XCTAssertEqual(loaded.entries.first?.logFileRef, "test.log")
        XCTAssertEqual(loaded.entries.first?.primaryCategory, .graphics)
        XCTAssertEqual(loaded.entries.first?.confidenceTier, .medium)
        XCTAssertEqual(loaded.entries.first?.topSignatures, ["gpu-device-lost", "metal-validation"])
        XCTAssertEqual(loaded.entries.first?.remediationCardIds, ["switch-backend"])
        XCTAssertEqual(loaded.entries.first?.wineDebugPreset, .crash)
        XCTAssertEqual(loaded.entries.first?.bottleIdentifier, "bottle-abc")
        XCTAssertEqual(loaded.entries.first?.programPath, "/path/to/game.exe")
    }

    func testDiagnosisHistoryClear() {
        var history = DiagnosisHistory()
        let entry = DiagnosisHistoryEntry(
            timestamp: Date(),
            logFileRef: "test.log",
            primaryCategory: .coreCrashFatal,
            confidenceTier: .high,
            topSignatures: [],
            remediationCardIds: [],
            wineDebugPreset: nil,
            bottleIdentifier: "bottle-1",
            programPath: "/game.exe"
        )
        history.append(entry)
        XCTAssertFalse(history.isEmpty)

        history.clear()
        XCTAssertTrue(history.isEmpty)
        XCTAssertEqual(history.entries.count, 0)
    }

    func testDiagnosisHistoryLoadNonexistent() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent-\(UUID()).plist")
        let history = DiagnosisHistory.load(from: url)
        XCTAssertTrue(history.isEmpty)
    }

    func testDiagnosisHistoryTopSignaturesCapped() {
        let entry = DiagnosisHistoryEntry(
            timestamp: Date(),
            logFileRef: "test.log",
            primaryCategory: .coreCrashFatal,
            confidenceTier: .high,
            topSignatures: ["a", "b", "c", "d", "e"],
            remediationCardIds: [],
            wineDebugPreset: nil,
            bottleIdentifier: "bottle-1",
            programPath: "/game.exe"
        )
        XCTAssertEqual(entry.topSignatures.count, 3, "topSignatures should be capped at 3")
    }

    // MARK: - RemediationTimeline Tests

    func testRemediationTimelineFIFO() {
        var timeline = RemediationTimeline()
        XCTAssertTrue(timeline.isEmpty)

        // Add 11 entries; first should be evicted
        for index in 0 ..< 11 {
            let entry = RemediationTimelineEntry(
                timestamp: Date(),
                actionId: "action-\(index)",
                actionTitle: "Action \(index)",
                beforeValue: "before-\(index)",
                afterValue: "after-\(index)",
                bottleIdentifier: "bottle-1",
                programPath: "/game.exe"
            )
            timeline.record(entry)
        }

        XCTAssertEqual(timeline.entries.count, RemediationTimeline.maxEntries)
        // First entry (action-0) should have been evicted
        XCTAssertEqual(timeline.entries.first?.actionId, "action-1")
        XCTAssertEqual(timeline.entries.last?.actionId, "action-10")
    }

    func testRemediationTimelineRoundTrip() throws {
        var timeline = RemediationTimeline()
        let entry = RemediationTimelineEntry(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            actionId: "install-vcredist",
            actionTitle: "Install Visual C++ Redistributable",
            beforeValue: "not installed",
            afterValue: "installed",
            bottleIdentifier: "bottle-abc",
            programPath: "/path/to/game.exe"
        )
        timeline.record(entry)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-remediation-timeline-\(UUID()).plist")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try timeline.save(to: tempURL)
        let loaded = RemediationTimeline.load(from: tempURL)

        XCTAssertEqual(loaded.entries.count, 1)
        XCTAssertEqual(loaded.entries.first?.actionId, "install-vcredist")
        XCTAssertEqual(loaded.entries.first?.actionTitle, "Install Visual C++ Redistributable")
        XCTAssertEqual(loaded.entries.first?.beforeValue, "not installed")
        XCTAssertEqual(loaded.entries.first?.afterValue, "installed")
    }

    func testRemediationTimelineClear() {
        var timeline = RemediationTimeline()
        let entry = RemediationTimelineEntry(
            timestamp: Date(),
            actionId: "test",
            actionTitle: "Test",
            beforeValue: nil,
            afterValue: nil,
            bottleIdentifier: "bottle-1",
            programPath: "/game.exe"
        )
        timeline.record(entry)
        XCTAssertFalse(timeline.isEmpty)

        timeline.clear()
        XCTAssertTrue(timeline.isEmpty)
    }

    // MARK: - DiagnosticExporter Helper Tests

    func testSanitizeName() {
        XCTAssertEqual(DiagnosticExporter.sanitizeName("My Game 2024!"), "My-Game-2024")
        XCTAssertEqual(DiagnosticExporter.sanitizeName("simple"), "simple")
        XCTAssertEqual(DiagnosticExporter.sanitizeName("a/b\\c:d"), "a-b-c-d")
        XCTAssertEqual(DiagnosticExporter.sanitizeName("---test---"), "test")
    }

    func testFormatDateForFilename() {
        // Create a known date
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let components = DateComponents(year: 2_025, month: 1, day: 15, hour: 14, minute: 30, second: 45)
        guard let date = calendar.date(from: components) else {
            XCTFail("Failed to create test date")
            return
        }
        let result = DiagnosticExporter.formatDateForFilename(date)
        XCTAssertEqual(result, "20250115-143045")
    }
}
