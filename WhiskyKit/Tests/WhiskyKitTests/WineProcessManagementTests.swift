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
        let (bottle, logsFolder) = try makeBottleWithoutRuntime()

        await Wine.$logsFolderOverride.withValue(logsFolder) {
            _ = try? await Wine.listProcesses(for: bottle)
        }

        XCTAssertEqual(logFiles(in: logsFolder), [])
    }

    /// The Steam client driver polls the process list while it watches Steam.
    @MainActor
    func testSteamDriverProcessListLeavesNoLogFile() async throws {
        let (bottle, logsFolder) = try makeBottleWithoutRuntime()

        await Wine.$logsFolderOverride.withValue(logsFolder) {
            _ = await WineSteamClientDriver(bottle: bottle).processList()
        }

        XCTAssertEqual(logFiles(in: logsFolder), [])
    }

    /// Keeps the two tests above honest: any other helper run still gets a log
    /// file, and it lands in the logs folder the test binds.
    @MainActor
    func testOtherHelperRunsStillWriteALogFile() async throws {
        let (bottle, logsFolder) = try makeBottleWithoutRuntime()

        await Wine.$logsFolderOverride.withValue(logsFolder) {
            _ = try? await Wine.runWine(["tasklist.exe", "/FO", "CSV"], bottle: bottle)
        }

        XCTAssertEqual(logFiles(in: logsFolder).count, 1)
    }

    // MARK: - Helpers

    /// A bottle in a temporary folder, and a logs folder next to it for the test
    /// to bind as `Wine.logsFolderOverride`. Nothing is written under
    /// `~/Library/Logs`, and tests running in parallel processes never share a
    /// logs folder. Skips the test where a Wine runtime is installed for the test
    /// host, since tasklist.exe would really run there.
    @MainActor
    private func makeBottleWithoutRuntime() throws -> (bottle: Bottle, logsFolder: URL) {
        try XCTSkipIf(
            FileManager.default.isExecutableFile(atPath: Wine.wineBinary.path(percentEncoded: false)),
            "A Wine runtime is installed for the test host"
        )
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let bottleURL = dir.appending(path: "bottle", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: dir)
        }
        let bottle = Bottle(bottleUrl: bottleURL, inFlight: false, isAvailable: true)
        return (bottle, dir.appending(path: "logs", directoryHint: .isDirectory))
    }

    /// The log files in `folder`, which the test owns.
    private func logFiles(in folder: URL) -> [URL] {
        let contents = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        return (contents ?? []).filter { $0.pathExtension == "log" }
    }
}
