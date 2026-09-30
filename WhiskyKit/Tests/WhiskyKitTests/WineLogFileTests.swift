//
//  WineLogFileTests.swift
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

final class WineLogFileTests: XCTestCase {
    /// 2026-09-21T14:13:20.250Z
    private let launchTime = Date(timeIntervalSince1970: 1_790_000_000.25)

    /// A launch opens its log, then the DLL override import opens one a moment
    /// later in the same second. The import used to replace the launch's log, so
    /// the program's output went to a file no longer on disk and the log recorded
    /// for the run held only the import's output.
    func testLogsOpenedInTheSameSecondKeepTheirOwnContent() throws {
        let folder = try makeTempDirectory()

        let (launch, launchURL) = try Wine.makeLogFile(in: folder, date: launchTime)
        launch.writeWineLog(line: "launch header\n")

        let (helper, helperURL) = try Wine.makeLogFile(in: folder, date: launchTime.addingTimeInterval(0.5))
        helper.writeWineLog(line: "reg import output\n")
        try helper.closeWineLog()

        launch.writeWineLog(line: "program output\n")
        try launch.closeWineLog()

        XCTAssertNotEqual(launchURL, helperURL)
        XCTAssertEqual(try String(contentsOf: launchURL, encoding: .utf8), "launch header\nprogram output\n")
        XCTAssertEqual(try String(contentsOf: helperURL, encoding: .utf8), "reg import output\n")
    }

    /// Two logs in the same millisecond get numbered names instead of sharing one.
    /// The number goes before the extension: retention, Delete Old Logs and the
    /// diagnostics summary pick log files out of the folder by `.log`.
    func testLogsOpenedInTheSameMillisecondGetNumberedNames() throws {
        let folder = try makeTempDirectory()

        let (first, firstURL) = try Wine.makeLogFile(in: folder, date: launchTime)
        let (second, secondURL) = try Wine.makeLogFile(in: folder, date: launchTime)
        first.writeWineLog(line: "first\n")
        second.writeWineLog(line: "second\n")
        try first.closeWineLog()
        try second.closeWineLog()

        XCTAssertEqual(firstURL.lastPathComponent, "2026-09-21T14:13:20.250Z.log")
        XCTAssertEqual(secondURL.lastPathComponent, "2026-09-21T14:13:20.250Z-2.log")
        XCTAssertEqual(try String(contentsOf: firstURL, encoding: .utf8), "first\n")
        XCTAssertEqual(try String(contentsOf: secondURL, encoding: .utf8), "second\n")
    }

    /// The app and WhiskyCmd write to the same folder, so creating a log cannot be
    /// a check for the name followed by a write. Logs opened all at once for the
    /// same instant each get a file of their own.
    func testLogsOpenedConcurrentlyEachGetTheirOwnFile() async throws {
        let folder = try makeTempDirectory()
        let date = launchTime
        let count = 32

        let logs = await withTaskGroup(of: (index: Int, url: URL)?.self) { group in
            for index in 0 ..< count {
                group.addTask {
                    do {
                        let (handle, url) = try Wine.makeLogFile(in: folder, date: date)
                        handle.writeWineLog(line: "log \(index)\n")
                        try handle.closeWineLog()
                        return (index, url)
                    } catch {
                        return nil
                    }
                }
            }
            var logs: [(index: Int, url: URL)] = []
            for await log in group {
                if let log {
                    logs.append(log)
                }
            }
            return logs
        }

        XCTAssertEqual(logs.count, count)
        XCTAssertEqual(Set(logs.map(\.url)).count, count)
        for log in logs {
            XCTAssertEqual(try String(contentsOf: log.url, encoding: .utf8), "log \(log.index)\n")
        }
    }

    // MARK: - Helpers

    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: dir)
        }
        return dir
    }
}
