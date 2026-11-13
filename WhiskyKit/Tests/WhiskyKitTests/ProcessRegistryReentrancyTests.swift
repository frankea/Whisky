//
//  ProcessRegistryReentrancyTests.swift
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

/// Records whether the registry could be read from inside each change announcement.
private final class ReadableDuringPostRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Bool] = []

    var recorded: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return results
    }

    func append(_ result: Bool) {
        lock.lock()
        results.append(result)
        lock.unlock()
    }
}

/// Views observe ``ProcessRegistry/didChangeNotification`` and read the
/// registry right away. On the main thread the post is synchronous, so the
/// registry must not hold its lock while it posts.
@MainActor
final class ProcessRegistryReentrancyTests: XCTestCase {
    private var bottleURL: URL!
    private var bottle: Bottle!
    private let registry = ProcessRegistry.shared

    override func setUp() async throws {
        try await super.setUp()
        bottleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("reentrancy-bottle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)
        bottle = Bottle(bottleUrl: bottleURL, isAvailable: true)
        registry.reset()
    }

    override func tearDown() async throws {
        registry.reset()
        try? FileManager.default.removeItem(at: bottleURL)
        try await super.tearDown()
    }

    /// Observes this bottle's announcements, reading the registry from each one.
    ///
    /// The read runs on another thread with a timeout, so a lock still held
    /// during the post shows up as `false` instead of hanging the suite.
    private func observeReads(into recorder: ReadableDuringPostRecorder) -> NSObjectProtocol {
        let url = bottleURL
        let registry = registry
        return NotificationCenter.default.addObserver(
            forName: ProcessRegistry.didChangeNotification, object: nil, queue: nil
        ) { note in
            guard let url, note.userInfo?[ProcessRegistry.bottleURLKey] as? URL == url else { return }
            let done = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                _ = registry.getProcessCount(for: url)
                done.signal()
            }
            recorder.append(done.wait(timeout: .now() + 2) == .success)
        }
    }

    func testRegisterAnnouncesWithTheLockReleased() {
        XCTAssertTrue(Thread.isMainThread)
        let recorder = ReadableDuringPostRecorder()
        let observer = observeReads(into: recorder)
        defer { NotificationCenter.default.removeObserver(observer) }

        registry.register(process: Process(), bottle: bottle, programName: "game.exe")

        XCTAssertEqual(recorder.recorded, [true])
    }

    func testUnregisterByPIDAnnouncesWithTheLockReleased() {
        let launcher = Process()
        registry.register(process: launcher, bottle: bottle, programName: "game.exe")
        registry.updatePID(pid: 424_242, for: launcher)
        let recorder = ReadableDuringPostRecorder()
        let observer = observeReads(into: recorder)
        defer { NotificationCenter.default.removeObserver(observer) }

        registry.unregister(pid: 424_242)

        XCTAssertEqual(recorder.recorded, [true])
        XCTAssertEqual(registry.getProcessCount(for: bottleURL), 0)
    }

    func testEveryAnnouncingChangeReleasesTheLock() {
        let launcher = Process()
        let recorder = ReadableDuringPostRecorder()
        let observer = observeReads(into: recorder)
        defer { NotificationCenter.default.removeObserver(observer) }

        registry.noteLaunch(bottleURL: bottleURL)
        registry.register(process: launcher, bottle: bottle, programName: "game.exe")
        registry.unregister(process: launcher)
        registry.register(process: Process(), bottle: bottle, programName: "other.exe")
        registry.clearRegistry(for: bottleURL)
        registry.endSession(for: bottleURL)

        XCTAssertEqual(recorder.recorded, Array(repeating: true, count: 6))
    }
}
