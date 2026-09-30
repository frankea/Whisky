//
//  WineProcessManagementTests.swift
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

final class WineProcessManagementTests: XCTestCase {
    /// A fresh prefix can never have a live wineserver, so the probe must
    /// report false — whether wineserver spawns and exits nonzero (runtime
    /// installed) or the spawn itself fails (no runtime, e.g. CI).
    @MainActor
    func testWineserverProbeReturnsFalseForBottleWithoutServer() async {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let bottle = Bottle(bottleUrl: tempDir, inFlight: false, isAvailable: true)

        let running = await Wine.isWineserverRunning(for: bottle)

        XCTAssertFalse(running)
    }

    /// The Processes page lists processes every few seconds, and a log file per
    /// listing buried the launch logs people are asked to attach. No runtime is
    /// installed for the test host, so tasklist.exe never starts, but a helper
    /// run creates its log before it starts the process.
    @MainActor
    func testListingProcessesLeavesNoLogFile() async throws {
        let bottle = try makeBottleWithoutRuntime()

        _ = try? await Wine.listProcesses(for: bottle)

        XCTAssertEqual(logFiles(naming: bottle), [])
    }

    /// The Steam client driver polls the process list while it watches Steam.
    @MainActor
    func testSteamDriverProcessListLeavesNoLogFile() async throws {
        let bottle = try makeBottleWithoutRuntime()

        _ = await WineSteamClientDriver(bottle: bottle).processList()

        XCTAssertEqual(logFiles(naming: bottle), [])
    }

    /// Keeps the two tests above honest: any other helper run still gets a log
    /// file, and it is found by the bottle it names.
    @MainActor
    func testOtherHelperRunsStillWriteALogFile() async throws {
        let bottle = try makeBottleWithoutRuntime()

        _ = try? await Wine.runWine(["tasklist.exe", "/FO", "CSV"], bottle: bottle)

        XCTAssertEqual(logFiles(naming: bottle).count, 1)
    }

    // MARK: - Helpers

    /// A bottle in a temporary folder. Skips the test where a Wine runtime is
    /// installed for the test host, since tasklist.exe would really run there.
    /// Afterwards it removes the logs that name the bottle, and the logs folder
    /// itself if the test created it.
    @MainActor
    private func makeBottleWithoutRuntime() throws -> Bottle {
        try XCTSkipIf(
            FileManager.default.isExecutableFile(atPath: Wine.wineBinary.path(percentEncoded: false)),
            "A Wine runtime is installed for the test host"
        )
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let bottle = Bottle(bottleUrl: dir, inFlight: false, isAvailable: true)

        let logsFolder = Wine.logsFolder
        let logsFolderExisted = FileManager.default.fileExists(atPath: logsFolder.path(percentEncoded: false))
        let header = Self.logHeader(naming: bottle)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: dir)
            if logsFolderExisted {
                for log in Self.logFiles(in: logsFolder, containing: header) {
                    try? FileManager.default.removeItem(at: log)
                }
            } else {
                try? FileManager.default.removeItem(at: logsFolder)
            }
        }
        return bottle
    }

    /// The log files whose header names `bottle`.
    @MainActor
    private func logFiles(naming bottle: Bottle) -> [URL] {
        Self.logFiles(in: Wine.logsFolder, containing: Self.logHeader(naming: bottle))
    }

    /// The line a helper run's log header uses to name its bottle.
    @MainActor
    private static func logHeader(naming bottle: Bottle) -> String {
        "Bottle URL: \(bottle.url.path)\n"
    }

    private static func logFiles(in folder: URL, containing text: String) -> [URL] {
        let contents = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        return (contents ?? []).filter { url in
            guard url.pathExtension == "log",
                  let log = try? String(contentsOf: url, encoding: .utf8)
            else {
                return false
            }
            return log.contains(text)
        }
    }
}
