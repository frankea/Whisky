//
//  ProcessRegistrySessionTests.swift
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

/// Collects the bottle URLs ``ProcessRegistry/didChangeNotification`` announces.
private final class AnnouncementRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URL] = []

    var urls: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func append(_ url: URL) {
        lock.lock()
        recorded.append(url)
        lock.unlock()
    }
}

/// The launch session a bottle's tracked processes belong to, and how a
/// program launch is tracked. Nothing here starts Wine: the launches run
/// `/usr/bin/true` and `/usr/bin/false`.
@MainActor
final class ProcessRegistrySessionTests: XCTestCase {
    private var bottleURL: URL!
    private var bottle: Bottle!
    private var registry: ProcessRegistry { .shared }

    override func setUp() async throws {
        try await super.setUp()
        bottleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("session-bottle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)
        bottle = Bottle(bottleUrl: bottleURL, isAvailable: true)
        registry.reset()
    }

    override func tearDown() async throws {
        registry.reset()
        try? FileManager.default.removeItem(at: bottleURL)
        try await super.tearDown()
    }

    private func process(_ path: String) -> Process {
        Wine.makeProcess(args: [], environment: [:], executableURL: URL(filePath: path))
    }

    // MARK: - Session

    func testRegisterStartsASession() {
        XCTAssertNil(registry.lastLaunch(for: bottleURL))

        registry.register(process: Process(), bottle: bottle, programName: "game.exe")

        XCTAssertNotNil(registry.lastLaunch(for: bottleURL))
        XCTAssertEqual(registry.getProcessCount(for: bottleURL), 1)
    }

    func testNoteLaunchStartsASessionWithoutAnEntry() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)

        registry.noteLaunch(bottleURL: bottleURL, at: date)

        XCTAssertEqual(registry.lastLaunch(for: bottleURL), date)
        XCTAssertEqual(registry.getProcessCount(for: bottleURL), 0)
    }

    /// A stop takes a moment; until the wineserver is gone the bottle is still
    /// Whisky's, so clearing the entries must not make it look orphaned.
    func testClearRegistryKeepsTheSession() {
        registry.register(process: Process(), bottle: bottle, programName: "game.exe")

        registry.clearRegistry(for: bottleURL)

        XCTAssertEqual(registry.getProcessCount(for: bottleURL), 0)
        XCTAssertNotNil(registry.lastLaunch(for: bottleURL))
    }

    func testEndSessionClearsEntriesAndSession() {
        registry.register(process: Process(), bottle: bottle, programName: "game.exe")

        registry.endSession(for: bottleURL)

        XCTAssertEqual(registry.getProcessCount(for: bottleURL), 0)
        XCTAssertNil(registry.lastLaunch(for: bottleURL))
    }

    func testResetClearsSessions() {
        registry.noteLaunch(bottleURL: bottleURL)

        registry.reset()

        XCTAssertNil(registry.lastLaunch(for: bottleURL))
    }

    // MARK: - Unregistering

    func testUnregisterProcessRemovesOnlyItsEntry() {
        let first = Process()
        let second = Process()
        registry.register(process: first, bottle: bottle, programName: "launcher.exe")
        registry.register(process: second, bottle: bottle, programName: "game.exe")

        registry.unregister(process: first)

        XCTAssertEqual(registry.getProcesses(for: bottle).map(\.programName), ["game.exe"])
    }

    /// Exited launchers all have PID 0, so removing by PID could take the wrong one.
    func testUnregisterEntryRemovesExactlyThatEntry() throws {
        let otherURL = bottleURL.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: otherURL, withIntermediateDirectories: true)
        let other = Bottle(bottleUrl: otherURL, isAvailable: true)
        registry.register(process: Process(), bottle: other, programName: "other.exe")
        registry.register(process: Process(), bottle: bottle, programName: "game.exe")
        let entry = try XCTUnwrap(registry.getProcesses(for: bottle).first)
        XCTAssertEqual(entry.pid, 0)

        registry.unregister(entry)

        XCTAssertEqual(registry.getProcessCount(for: bottleURL), 0)
        XCTAssertEqual(registry.getProcessCount(for: otherURL), 1)
    }

    // MARK: - Notifications

    func testChangesAreAnnouncedForTheirBottle() {
        let recorder = AnnouncementRecorder()
        let observer = NotificationCenter.default.addObserver(
            forName: ProcessRegistry.didChangeNotification, object: nil, queue: nil
        ) { note in
            if let url = note.userInfo?[ProcessRegistry.bottleURLKey] as? URL {
                recorder.append(url)
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        registry.register(process: Process(), bottle: bottle, programName: "game.exe")
        registry.clearRegistry(for: bottleURL)
        registry.endSession(for: bottleURL)
        // Nothing left to change: no announcement.
        registry.endSession(for: bottleURL)
        registry.clearRegistry(for: bottleURL)

        // Only this bottle's: a launch elsewhere in the suite may announce its own.
        XCTAssertEqual(recorder.urls.filter { $0 == bottleURL }.count, 3)
    }

    // MARK: - Tracked launches

    func testTrackedLaunchIsRegisteredWithItsPID() async throws {
        let launcher = process("/usr/bin/true")

        let stream = try Wine.startTrackedProgram(launcher, name: "game.exe", bottle: bottle, fileHandle: nil)

        let entry = try XCTUnwrap(registry.getProcesses(for: bottle).first)
        XCTAssertEqual(entry.programName, "game.exe")
        XCTAssertEqual(entry.pid, launcher.processIdentifier)
        XCTAssertGreaterThan(entry.pid, 0)
        for await _ in stream {}
    }

    /// The program runs on under the wineserver after `wine start` exits, so
    /// the entry stays; its PID goes, since that process is gone.
    func testCleanLauncherExitKeepsTheEntryWithoutAPID() async throws {
        let launcher = process("/usr/bin/true")
        var exitCode: Int32 = -1
        for await output in try Wine.startTrackedProgram(launcher, name: "game.exe", bottle: bottle, fileHandle: nil) {
            if case let .terminated(code) = output {
                exitCode = code
            }
        }

        Wine.launcherDidExit(launcher, exitCode: exitCode)

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(registry.getProcesses(for: bottle).map(\.pid), [0])
    }

    func testFailedLauncherExitRemovesTheEntry() async throws {
        let launcher = process("/usr/bin/false")
        var exitCode: Int32 = 0
        for await output in try Wine.startTrackedProgram(launcher, name: "game.exe", bottle: bottle, fileHandle: nil) {
            if case let .terminated(code) = output {
                exitCode = code
            }
        }

        Wine.launcherDidExit(launcher, exitCode: exitCode)

        XCTAssertNotEqual(exitCode, 0)
        XCTAssertEqual(registry.getProcessCount(for: bottleURL), 0)
    }

    func testLauncherThatCannotStartLeavesNoEntry() {
        let launcher = process("/nonexistent/wine64-\(UUID().uuidString)")

        XCTAssertThrowsError(
            try Wine.startTrackedProgram(launcher, name: "game.exe", bottle: bottle, fileHandle: nil)
        )
        XCTAssertEqual(registry.getProcessCount(for: bottleURL), 0)
    }

    // MARK: - Run state

    /// A fresh prefix has no wineserver, with or without a runtime installed.
    func testRunStateOfAnUntouchedBottleIsIdle() async {
        let state = await Wine.runState(for: bottle)

        XCTAssertEqual(state, .idle)
    }

    func testRunStateCountsALaunchThatIsStillStarting() async {
        registry.noteLaunch(bottleURL: bottleURL)

        let state = await Wine.runState(for: bottle)

        XCTAssertEqual(state, .running(trackedCount: 0))
        XCTAssertNotNil(registry.lastLaunch(for: bottleURL))
    }

    func testRunStateEndsASessionWhoseWineserverIsGone() async {
        registry.register(process: Process(), bottle: bottle, programName: "game.exe")
        registry.noteLaunch(bottleURL: bottleURL, at: Date().addingTimeInterval(-600))

        let state = await Wine.runState(for: bottle)

        XCTAssertEqual(state, .idle)
        XCTAssertNil(registry.lastLaunch(for: bottleURL))
        XCTAssertEqual(registry.getProcessCount(for: bottleURL), 0)
    }
}
