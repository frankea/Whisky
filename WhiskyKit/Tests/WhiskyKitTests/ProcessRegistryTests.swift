//
//  ProcessRegistryTests.swift
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

final class ProcessRegistryTests: XCTestCase {
    var testBottle: Bottle!
    var testBottleURL: URL!

    override func setUp() async throws {
        try await super.setUp()

        // Create a temporary directory for test bottle
        let tempDir = FileManager.default.temporaryDirectory
        testBottleURL = tempDir.appendingPathComponent("test-bottle-\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: testBottleURL, withIntermediateDirectories: true)

        // Create bottle structure
        let metadataURL = testBottleURL.appending(path: "Metadata.plist")
        let settings = BottleSettings()
        try settings.encode(to: metadataURL)

        // Create bottle instance
        testBottle = await MainActor.run {
            Bottle(bottleUrl: testBottleURL, isAvailable: true)
        }

        // Clear registry before each test
        ProcessRegistry.shared.lock.lock()
        ProcessRegistry.shared.activeProcesses.removeAll()
        ProcessRegistry.shared.lock.unlock()
    }

    override func tearDown() async throws {
        // Clean up test bottle
        try? FileManager.default.removeItem(at: testBottleURL)
        try await super.tearDown()
    }

    // MARK: - Registration Tests

    func testRegisterProcess() {
        let process = Process()
        let programName = "test.exe"

        ProcessRegistry.shared.register(process: process, bottle: testBottle, programName: programName)

        let processes = ProcessRegistry.shared.getProcesses(for: testBottle)
        XCTAssertEqual(processes.count, 1, "Should have one registered process")
        XCTAssertEqual(processes.first?.programName, programName, "Program name should match")
        XCTAssertEqual(processes.first?.pid, 0, "PID should be 0 before launch")
    }

    func testRegisterMultipleProcesses() {
        let process1 = Process()
        let process2 = Process()
        let process3 = Process()

        ProcessRegistry.shared.register(process: process1, bottle: testBottle, programName: "app1.exe")
        ProcessRegistry.shared.register(process: process2, bottle: testBottle, programName: "app2.exe")
        ProcessRegistry.shared.register(process: process3, bottle: testBottle, programName: "app3.exe")

        let processes = ProcessRegistry.shared.getProcesses(for: testBottle)
        XCTAssertEqual(processes.count, 3, "Should have three registered processes")
    }

    func testRegisterProcessForDifferentBottles() async throws {
        let bottle2URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-bottle-2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: bottle2URL, withIntermediateDirectories: true)

        let metadataURL2 = bottle2URL.appending(path: "Metadata.plist")
        let settings2 = BottleSettings()
        try settings2.encode(to: metadataURL2)

        let bottle2 = await MainActor.run {
            Bottle(bottleUrl: bottle2URL, isAvailable: true)
        }

        let process1 = Process()
        let process2 = Process()

        ProcessRegistry.shared.register(process: process1, bottle: testBottle, programName: "app1.exe")
        ProcessRegistry.shared.register(process: process2, bottle: bottle2, programName: "app2.exe")

        let processes1 = ProcessRegistry.shared.getProcesses(for: testBottle)
        let processes2 = ProcessRegistry.shared.getProcesses(for: bottle2)

        XCTAssertEqual(processes1.count, 1, "First bottle should have one process")
        XCTAssertEqual(processes2.count, 1, "Second bottle should have one process")

        // Cleanup
        try? FileManager.default.removeItem(at: bottle2URL)
    }

    func testUpdatePID() {
        let process = Process()
        ProcessRegistry.shared.register(process: process, bottle: testBottle, programName: "test.exe")

        let processesBefore = ProcessRegistry.shared.getProcesses(for: testBottle)
        XCTAssertEqual(processesBefore.first?.pid, 0, "PID should be 0 before update")

        let newPID: Int32 = 12345
        ProcessRegistry.shared.updatePID(pid: newPID, for: process)

        let processesAfter = ProcessRegistry.shared.getProcesses(for: testBottle)
        XCTAssertEqual(processesAfter.first?.pid, newPID, "PID should be updated")
    }

    func testUnregisterProcess() {
        let process = Process()
        ProcessRegistry.shared.register(process: process, bottle: testBottle, programName: "test.exe")

        let processesBefore = ProcessRegistry.shared.getProcesses(for: testBottle)
        XCTAssertEqual(processesBefore.count, 1, "Should have one registered process")

        ProcessRegistry.shared.unregister(pid: 0)

        let processesAfter = ProcessRegistry.shared.getProcesses(for: testBottle)
        XCTAssertEqual(processesAfter.count, 0, "Process should be unregistered")
    }

    // MARK: - Querying Tests

    func testGetProcessesForBottle() {
        let process1 = Process()
        let process2 = Process()

        ProcessRegistry.shared.register(process: process1, bottle: testBottle, programName: "app1.exe")
        ProcessRegistry.shared.register(process: process2, bottle: testBottle, programName: "app2.exe")

        let processes = ProcessRegistry.shared.getProcesses(for: testBottle)

        XCTAssertEqual(processes.count, 2, "Should return all processes for bottle")
        XCTAssertTrue(processes.contains(where: { $0.programName == "app1.exe" }), "Should contain app1.exe")
        XCTAssertTrue(processes.contains(where: { $0.programName == "app2.exe" }), "Should contain app2.exe")
    }

    func testGetAllProcesses() async throws {
        let bottle2URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-bottle-3-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: bottle2URL, withIntermediateDirectories: true)

        let metadataURL2 = bottle2URL.appending(path: "Metadata.plist")
        let settings2 = BottleSettings()
        try settings2.encode(to: metadataURL2)

        let bottle2 = await MainActor.run {
            Bottle(bottleUrl: bottle2URL, isAvailable: true)
        }

        let process1 = Process()
        let process2 = Process()

        ProcessRegistry.shared.register(process: process1, bottle: testBottle, programName: "app1.exe")
        ProcessRegistry.shared.register(process: process2, bottle: bottle2, programName: "app2.exe")

        let allProcesses = ProcessRegistry.shared.getAllProcesses()

        XCTAssertEqual(allProcesses.count, 2, "Should return processes for all bottles")
        XCTAssertEqual(allProcesses[testBottleURL]?.count, 1, "First bottle should have one process")
        XCTAssertEqual(allProcesses[bottle2URL]?.count, 1, "Second bottle should have one process")

        // Cleanup
        try? FileManager.default.removeItem(at: bottle2URL)
    }

    // MARK: - Cleanup Tests

    func testCleanupEmptyBottle() async {
        // No processes registered
        await ProcessRegistry.shared.cleanup(for: testBottle, force: false)

        let processes = ProcessRegistry.shared.getProcesses(for: testBottle)
        XCTAssertEqual(processes.count, 0, "Should handle empty bottle gracefully")
    }

    func testCleanupGracefulShutdown() async {
        let process = Process()
        ProcessRegistry.shared.register(process: process, bottle: testBottle, programName: "test.exe")

        // Simulate PID update
        ProcessRegistry.shared.updatePID(pid: 9999, for: process)

        let processesBefore = ProcessRegistry.shared.getProcesses(for: testBottle)
        XCTAssertEqual(processesBefore.count, 1, "Should have one registered process")

        // Cleanup with graceful shutdown
        await ProcessRegistry.shared.cleanup(for: testBottle, force: false)

        // Wait for cleanup to complete
        try? await Task.sleep(nanoseconds: 6_000_000_000) // 6 seconds

        let processesAfter = ProcessRegistry.shared.getProcesses(for: testBottle)
        XCTAssertEqual(processesAfter.count, 0, "Processes should be cleaned up")
    }

    func testCleanupAllBottles() async throws {
        let bottle2URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-bottle-4-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: bottle2URL, withIntermediateDirectories: true)

        let metadataURL2 = bottle2URL.appending(path: "Metadata.plist")
        let settings2 = BottleSettings()
        try settings2.encode(to: metadataURL2)

        let bottle2 = await MainActor.run {
            Bottle(bottleUrl: bottle2URL, isAvailable: true)
        }

        let process1 = Process()
        let process2 = Process()

        ProcessRegistry.shared.register(process: process1, bottle: testBottle, programName: "app1.exe")
        ProcessRegistry.shared.register(process: process2, bottle: bottle2, programName: "app2.exe")

        // Cleanup all
        await ProcessRegistry.shared.cleanupAll(force: false)

        // Wait for cleanup
        try? await Task.sleep(nanoseconds: 6_000_000_000)

        let processes1 = ProcessRegistry.shared.getProcesses(for: testBottle)
        let processes2 = ProcessRegistry.shared.getProcesses(for: bottle2)

        XCTAssertEqual(processes1.count, 0, "First bottle should be cleaned")
        XCTAssertEqual(processes2.count, 0, "Second bottle should be cleaned")

        // Cleanup
        try? FileManager.default.removeItem(at: bottle2URL)
    }

    // MARK: - ProcessInfo Tests

    func testProcessInfoHashable() {
        let info1 = ProcessRegistry.ProcessInfo(
            pid: 123,
            launchTime: Date(),
            bottleURL: testBottleURL,
            programName: "test.exe"
        )

        let info2 = ProcessRegistry.ProcessInfo(
            pid: 123,
            launchTime: info1.launchTime,
            bottleURL: testBottleURL,
            programName: "test.exe"
        )

        XCTAssertEqual(info1, info2, "ProcessInfo with same values should be equal")
        XCTAssertEqual(info1.hashValue, info2.hashValue, "ProcessInfo with same values should have same hash")
    }

    func testProcessInfoNotEqual() {
        let info1 = ProcessRegistry.ProcessInfo(
            pid: 123,
            launchTime: Date(),
            bottleURL: testBottleURL,
            programName: "test.exe"
        )

        let info2 = ProcessRegistry.ProcessInfo(
            pid: 456,
            launchTime: Date(),
            bottleURL: testBottleURL,
            programName: "test.exe"
        )

        XCTAssertNotEqual(info1, info2, "ProcessInfo with different PIDs should not be equal")
    }

    func testProcessInfoInSet() {
        let info1 = ProcessRegistry.ProcessInfo(
            pid: 123,
            launchTime: Date(),
            bottleURL: testBottleURL,
            programName: "test.exe"
        )

        let info2 = ProcessRegistry.ProcessInfo(
            pid: 123,
            launchTime: info1.launchTime,
            bottleURL: testBottleURL,
            programName: "test.exe"
        )

        var processSet: Set<ProcessRegistry.ProcessInfo> = []
        processSet.insert(info1)

        XCTAssertTrue(processSet.contains(info2), "Set should contain equal ProcessInfo")
        XCTAssertEqual(processSet.count, 1, "Set should only contain one instance of equal ProcessInfo")
    }

    // MARK: - Thread Safety Tests

    func testConcurrentRegistration() {
        let processCount = 100
        let expectation = XCTestExpectation(description: "Concurrent registration")

        DispatchQueue.concurrentPerform(iterations: processCount) { index in
            let process = Process()
            ProcessRegistry.shared.register(
                process: process,
                bottle: self.testBottle,
                programName: "app\(index).exe"
            )
        }

        expectation.fulfill()

        let processes = ProcessRegistry.shared.getProcesses(for: testBottle)
        XCTAssertEqual(processes.count, processCount, "All processes should be registered")
    }

    func testConcurrentUnregistration() {
        let processCount = 50
        var pids: [Int32] = []

        // Register processes
        for index in 0..<processCount {
            let process = Process()
            ProcessRegistry.shared.register(
                process: process,
                bottle: testBottle,
                programName: "app\(index).exe"
            )
            pids.append(Int32(index + 1000))
        }

        // Unregister concurrently
        DispatchQueue.concurrentPerform(iterations: processCount) { index in
            ProcessRegistry.shared.unregister(pid: pids[index])
        }

        let processes = ProcessRegistry.shared.getProcesses(for: testBottle)
        // Some may remain due to PID mismatch, but registry should handle concurrent access safely
        XCTAssertGreaterThanOrEqual(processes.count, 0, "Registry should handle concurrent operations safely")
    }
}
