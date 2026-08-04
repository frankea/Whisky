//
//  BottleOperationsTests.swift
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

// swiftlint:disable file_length
import Foundation
@testable import WhiskyKit
import XCTest

// MARK: - Fixtures

/// In-memory ``BottleRegistry`` so operation tests can observe path mutations
/// and reload requests without the app's view model.
@MainActor
final class RegistryFixture: BottleRegistry {
    var bottles: [Bottle] = []
    var bottlePaths: [URL] = []
    private(set) var loadCount = 0

    func bottle(for url: URL) -> Bottle? {
        bottles.first(where: { $0.url == url })
    }

    func loadBottles() {
        loadCount += 1
    }
}

/// Thread-safe collector for duplication progress phases; the early phases are
/// reported from a background task, the later ones from the main actor.
private final class PhaseRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [DuplicationPhase] = []

    func record(_ phase: DuplicationPhase) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(phase)
    }

    var phases: [DuplicationPhase] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

/// Shared temp-dir bottle fixture: a bottle directory with one installed
/// program, one pin, and one blocklist entry, all backed by a real
/// `Metadata.plist`.
class BottleOperationsTestCase: XCTestCase {
    var tempDir: URL!
    var bottleURL: URL!
    var exeURL: URL!
    var blockedURL: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appending(path: "bottle_ops_\(UUID().uuidString)")
        bottleURL = tempDir.appending(path: "Original")
        let gameDir = bottleURL.appending(path: "drive_c/Program Files/Game")
        try? FileManager.default.createDirectory(at: gameDir, withIntermediateDirectories: true)
        exeURL = gameDir.appending(path: "game.exe")
        blockedURL = gameDir.appending(path: "helper.exe")
        try? Data("game".utf8).write(to: exeURL)
        try? Data("helper".utf8).write(to: blockedURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    /// Creates the live bottle with a pin and a blocklist entry and registers
    /// both the instance and its path in `registry`.
    @MainActor
    func makeRegisteredBottle(in registry: RegistryFixture) -> Bottle {
        let bottle = Bottle(bottleUrl: bottleURL)
        bottle.settings.pins = [PinnedProgram(name: "Game", url: exeURL)]
        bottle.settings.blocklist = [blockedURL]
        registry.bottles = [bottle]
        registry.bottlePaths = [bottleURL]
        return bottle
    }

    /// Decodes the persisted settings for the bottle directory at `url`.
    func persistedSettings(at url: URL) throws -> BottleSettings {
        try BottleSettings.decode(from: url.appending(path: "Metadata.plist"))
    }
}

// MARK: - Move

final class BottleOperationsMoveTests: BottleOperationsTestCase {
    @MainActor
    func testMoveRewritesSettingsBeforeMoveAndUpdatesRegistry() throws {
        let registry = RegistryFixture()
        let bottle = makeRegisteredBottle(in: registry)
        let destination = tempDir.appending(path: "Moved")

        BottleOperations.move(bottleAt: bottleURL, to: destination, registry: registry)

        let fileManager = FileManager.default
        XCTAssertFalse(fileManager.fileExists(atPath: bottleURL.path(percentEncoded: false)))
        XCTAssertTrue(fileManager.fileExists(atPath: destination.path(percentEncoded: false)))
        XCTAssertEqual(registry.bottlePaths, [destination])
        XCTAssertEqual(registry.loadCount, 1)
        XCTAssertFalse(bottle.inFlight)

        // The rewrite ran before the file move, so the persisted settings
        // traveled with the bottle and now point inside the destination.
        let moved = try persistedSettings(at: destination)
        XCTAssertEqual(
            moved.pins.compactMap { $0.url?.path(percentEncoded: false) },
            [destination.appending(path: "drive_c/Program Files/Game/game.exe").path(percentEncoded: false)]
        )
        XCTAssertEqual(
            moved.blocklist.map { $0.path(percentEncoded: false) },
            [destination.appending(path: "drive_c/Program Files/Game/helper.exe").path(percentEncoded: false)]
        )
    }

    @MainActor
    func testFailedMoveRestoresPinsAndBlocklistAndClearsInFlight() throws {
        let registry = RegistryFixture()
        let bottle = makeRegisteredBottle(in: registry)
        let originalPins = bottle.settings.pins
        let originalBlocklist = bottle.settings.blocklist
        // The destination's parent doesn't exist, so the file move throws
        // after the settings were already rewritten (the issue #154 scenario).
        let destination = tempDir.appending(path: "missing/Moved")

        BottleOperations.move(bottleAt: bottleURL, to: destination, registry: registry)

        XCTAssertTrue(FileManager.default.fileExists(atPath: bottleURL.path(percentEncoded: false)))
        XCTAssertEqual(bottle.settings.pins, originalPins)
        XCTAssertEqual(bottle.settings.blocklist, originalBlocklist)

        // The rollback must reach the persisted plist, not just memory.
        let persisted = try persistedSettings(at: bottleURL)
        XCTAssertEqual(
            persisted.pins.compactMap { $0.url?.path(percentEncoded: false) },
            [exeURL.path(percentEncoded: false)]
        )
        XCTAssertEqual(
            persisted.blocklist.map { $0.path(percentEncoded: false) },
            [blockedURL.path(percentEncoded: false)]
        )

        XCTAssertEqual(registry.bottlePaths, [bottleURL])
        XCTAssertEqual(registry.loadCount, 0)
        XCTAssertFalse(bottle.inFlight)
    }

    @MainActor
    func testMoveWithNoRegisteredBottleStillMovesDirectory() {
        let registry = RegistryFixture()
        registry.bottlePaths = [bottleURL]
        let destination = tempDir.appending(path: "Moved")

        BottleOperations.move(bottleAt: bottleURL, to: destination, registry: registry)

        XCTAssertFalse(FileManager.default.fileExists(atPath: bottleURL.path(percentEncoded: false)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)))
        XCTAssertEqual(registry.bottlePaths, [destination])
        XCTAssertEqual(registry.loadCount, 1)
    }
}

// MARK: - Export

final class BottleOperationsExportTests: BottleOperationsTestCase {
    @MainActor
    func testExportWritesArchiveAndClearsInFlight() async throws {
        let registry = RegistryFixture()
        let bottle = makeRegisteredBottle(in: registry)
        let destination = tempDir.appending(path: "export.tar.gz")

        try await BottleOperations.export(bottleAt: bottleURL, to: destination, registry: registry)

        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)))
        XCTAssertFalse(bottle.inFlight)
    }

    @MainActor
    func testExportThrowsWhenBottleIsNotRegistered() async {
        let registry = RegistryFixture()
        let destination = tempDir.appending(path: "export.tar.gz")

        do {
            try await BottleOperations.export(bottleAt: bottleURL, to: destination, registry: registry)
            XCTFail("expected export to throw for an unregistered bottle")
        } catch {
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, "com.franke.Whisky")
            XCTAssertEqual(nsError.code, 1)
        }
    }
}

// MARK: - Duplicate

final class BottleOperationsDuplicateTests: BottleOperationsTestCase {
    @MainActor
    func testDuplicateCopiesRewritesMetadataAndRegisters() async throws {
        let registry = RegistryFixture()
        let bottle = makeRegisteredBottle(in: registry)

        let newURL = try await BottleOperations.duplicate(
            bottleAt: bottleURL,
            newName: "Original Copy",
            registry: registry
        )

        // The clone lives beside the source and contains the copied program.
        let clonedExe = newURL.appending(path: "drive_c/Program Files/Game/game.exe")
        XCTAssertTrue(FileManager.default.fileExists(atPath: clonedExe.path(percentEncoded: false)))

        // The clone's metadata was renamed and rewritten to its own paths.
        let cloned = try persistedSettings(at: newURL)
        XCTAssertEqual(cloned.name, "Original Copy")
        XCTAssertEqual(
            cloned.pins.compactMap { $0.url?.path(percentEncoded: false) },
            [clonedExe.path(percentEncoded: false)]
        )
        XCTAssertEqual(
            cloned.blocklist.map { $0.path(percentEncoded: false) },
            [newURL.appending(path: "drive_c/Program Files/Game/helper.exe").path(percentEncoded: false)]
        )

        // The source bottle's settings are untouched.
        let source = try persistedSettings(at: bottleURL)
        XCTAssertEqual(
            source.pins.compactMap { $0.url?.path(percentEncoded: false) },
            [exeURL.path(percentEncoded: false)]
        )

        // Registered, reloaded, and the guard released.
        XCTAssertEqual(registry.bottlePaths, [bottleURL, newURL])
        XCTAssertEqual(registry.loadCount, 1)
        XCTAssertFalse(bottle.inFlight)
    }

    @MainActor
    func testDuplicateReportsPhasesInOrder() async throws {
        let registry = RegistryFixture()
        _ = makeRegisteredBottle(in: registry)
        let recorder = PhaseRecorder()

        _ = try await BottleOperations.duplicate(
            bottleAt: bottleURL,
            newName: "Original Copy",
            registry: registry
        ) { recorder.record($0) }

        let phases = recorder.phases
        XCTAssertEqual(phases.count, 5)
        guard phases.count == 5 else { return }
        XCTAssertEqual(phases[0], .calculatingSize)
        guard case let .copying(bytesCopied: startBytes, totalBytes: total) = phases[1] else {
            return XCTFail("expected a copying start phase, got \(phases[1])")
        }
        XCTAssertEqual(startBytes, 0)
        XCTAssertEqual(phases[2], .copying(bytesCopied: total, totalBytes: total))
        XCTAssertEqual(phases[3], .updatingMetadata)
        XCTAssertEqual(phases[4], .finalizing)
    }

    @MainActor
    func testDuplicateStripsTransientArtifactsFromClone() async throws {
        let registry = RegistryFixture()
        _ = makeRegisteredBottle(in: registry)
        let logFile = bottleURL.appending(path: "logs/old-run.log")
        try FileManager.default.createDirectory(
            at: bottleURL.appending(path: "logs"),
            withIntermediateDirectories: true
        )
        try Data("log".utf8).write(to: logFile)
        let historyFile = bottleURL.appending(path: "drive_c/game.exe.diagnosis-history.plist")
        try Data("history".utf8).write(to: historyFile)

        let newURL = try await BottleOperations.duplicate(
            bottleAt: bottleURL,
            newName: "Original Copy",
            registry: registry
        )

        let fileManager = FileManager.default
        XCTAssertFalse(
            fileManager.fileExists(atPath: newURL.appending(path: "logs/old-run.log").path(percentEncoded: false))
        )
        let clonedHistory = newURL.appending(path: "drive_c/game.exe.diagnosis-history.plist")
        XCTAssertFalse(fileManager.fileExists(atPath: clonedHistory.path(percentEncoded: false)))
        // The source keeps its artifacts.
        XCTAssertTrue(fileManager.fileExists(atPath: logFile.path(percentEncoded: false)))
        XCTAssertTrue(fileManager.fileExists(atPath: historyFile.path(percentEncoded: false)))
    }

    @MainActor
    func testDuplicateThrowsWhenBottleIsNotRegistered() async {
        let registry = RegistryFixture()

        do {
            _ = try await BottleOperations.duplicate(
                bottleAt: bottleURL,
                newName: "Original Copy",
                registry: registry
            )
            XCTFail("expected duplicate to throw for an unregistered bottle")
        } catch {
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, "com.franke.Whisky")
            XCTAssertEqual(nsError.code, 1)
        }
    }
}

// MARK: - Duplicate Naming

final class NextDuplicateNameTests: XCTestCase {
    func testFirstDuplicateAppendsCopy() {
        XCTAssertEqual(
            BottleOperations.nextDuplicateName(baseName: "Games", existingNames: ["Games"]),
            "Games Copy"
        )
    }

    func testSubsequentDuplicatesCountUp() {
        XCTAssertEqual(
            BottleOperations.nextDuplicateName(baseName: "Games", existingNames: ["Games", "Games Copy"]),
            "Games Copy 2"
        )
        XCTAssertEqual(
            BottleOperations.nextDuplicateName(
                baseName: "Games",
                existingNames: ["Games", "Games Copy", "Games Copy 2"]
            ),
            "Games Copy 3"
        )
    }
}

// MARK: - Remove

final class BottleOperationsRemoveTests: BottleOperationsTestCase {
    /// A route store in the test's temp dir, pre-loaded with one route to the
    /// fixture bottle and one to an unrelated bottle.
    private func makeRouting() -> (routing: GameRouting, otherBottle: URL) {
        let routing = GameRouting(url: tempDir.appending(path: "GameRouting.plist"))
        let otherBottle = tempDir.appending(path: "Other")
        routing.record(appId: 1_245_620, bottleURL: bottleURL)
        routing.record(appId: 4_576_510, bottleURL: otherBottle)
        return (routing, otherBottle)
    }

    @MainActor
    func testRemoveDeletingFilesPrunesRoutesToTheBottle() {
        let registry = RegistryFixture()
        _ = makeRegisteredBottle(in: registry)
        let (routing, otherBottle) = makeRouting()

        BottleOperations.remove(bottleAt: bottleURL, deleteFiles: true, registry: registry, routing: routing)

        XCTAssertNil(routing.bottleURL(forAppId: 1_245_620))
        XCTAssertEqual(routing.bottleURL(forAppId: 4_576_510)?.lastPathComponent, otherBottle.lastPathComponent)
    }

    @MainActor
    func testRemoveKeepingFilesKeepsRoutes() {
        let registry = RegistryFixture()
        _ = makeRegisteredBottle(in: registry)
        let (routing, _) = makeRouting()

        BottleOperations.remove(bottleAt: bottleURL, deleteFiles: false, registry: registry, routing: routing)

        // The bottle is still on disk and can be re-imported; its routes wait
        // for it, inert until then because resolution ignores routes to
        // bottles it doesn't know.
        XCTAssertEqual(routing.bottleURL(forAppId: 1_245_620)?.lastPathComponent, bottleURL.lastPathComponent)
    }

    @MainActor
    func testRemoveFailureKeepsRoutes() throws {
        let registry = RegistryFixture()
        _ = makeRegisteredBottle(in: registry)
        let (routing, _) = makeRouting()
        // Deleting the directory up front makes the file removal throw.
        try FileManager.default.removeItem(at: bottleURL)

        BottleOperations.remove(bottleAt: bottleURL, deleteFiles: true, registry: registry, routing: routing)

        XCTAssertEqual(routing.bottleURL(forAppId: 1_245_620)?.lastPathComponent, bottleURL.lastPathComponent)
    }

    @MainActor
    func testRemoveDeletingFilesRemovesDirectoryAndRegistryEntry() {
        let registry = RegistryFixture()
        _ = makeRegisteredBottle(in: registry)

        BottleOperations.remove(bottleAt: bottleURL, deleteFiles: true, registry: registry)

        XCTAssertFalse(FileManager.default.fileExists(atPath: bottleURL.path(percentEncoded: false)))
        XCTAssertTrue(registry.bottlePaths.isEmpty)
        XCTAssertEqual(registry.loadCount, 1)
    }

    @MainActor
    func testRemoveKeepingFilesOnlyDeregisters() {
        let registry = RegistryFixture()
        _ = makeRegisteredBottle(in: registry)

        BottleOperations.remove(bottleAt: bottleURL, deleteFiles: false, registry: registry)

        XCTAssertTrue(FileManager.default.fileExists(atPath: bottleURL.path(percentEncoded: false)))
        XCTAssertTrue(registry.bottlePaths.isEmpty)
        XCTAssertEqual(registry.loadCount, 1)
    }

    @MainActor
    func testRemoveFailureKeepsRegistryEntry() throws {
        let registry = RegistryFixture()
        _ = makeRegisteredBottle(in: registry)
        // Deleting the directory up front makes the file removal throw.
        try FileManager.default.removeItem(at: bottleURL)

        BottleOperations.remove(bottleAt: bottleURL, deleteFiles: true, registry: registry)

        XCTAssertEqual(registry.bottlePaths, [bottleURL])
        XCTAssertEqual(registry.loadCount, 0)
    }
}
