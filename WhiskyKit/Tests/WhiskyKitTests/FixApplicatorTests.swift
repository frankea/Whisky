//
//  FixApplicatorTests.swift
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

/// Covers the settings-mutating fixes end to end: preview describes the
/// change, apply performs and records it, undo restores the prior value.
/// The process-touching fix (restart-wineserver) is deliberately not
/// exercised — it spawns wineserver and is not hermetic.
@MainActor
final class FixApplicatorTests: XCTestCase {
    private var tempDir: URL!
    private var bottle: Bottle!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        bottle = Bottle(bottleUrl: tempDir, inFlight: false, isAvailable: true)
    }

    override func tearDownWithError() throws {
        bottle = nil
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        tempDir = nil
    }

    // MARK: - Preview

    func testPreviewSwitchBackendDescribesCurrentAndTarget() throws {
        bottle.settings.graphicsBackend = .wined3d

        let preview = try XCTUnwrap(FixApplicator.preview(
            fixId: "switch-backend", params: ["backend": "dxvk"], bottle: bottle, program: nil
        ))

        XCTAssertEqual(preview.settingName, "Graphics Backend")
        XCTAssertEqual(preview.currentValue, "WineD3D")
        XCTAssertEqual(preview.newValue, "DXVK")
        XCTAssertTrue(preview.isReversible)
    }

    func testPreviewNonReversibleInstallFix() throws {
        let preview = try XCTUnwrap(FixApplicator.preview(
            fixId: "install-winetricks-verb", params: ["verb": "vcrun2019"], bottle: bottle, program: nil
        ))

        XCTAssertEqual(preview.newValue, "vcrun2019")
        XCTAssertFalse(preview.isReversible)
    }

    func testPreviewUnknownFixIdReturnsNil() {
        XCTAssertNil(FixApplicator.preview(fixId: "no.such_fix", params: [:], bottle: bottle, program: nil))
    }

    // MARK: - Apply

    func testApplySwitchBackendMutatesSettingsAndRecordsValues() {
        bottle.settings.graphicsBackend = .wined3d

        let attempt = FixApplicator.apply(
            fixId: "switch-backend", params: ["backend": "dxmt"], bottle: bottle, program: nil
        )

        XCTAssertEqual(bottle.settings.graphicsBackend, .dxmt)
        XCTAssertEqual(attempt.beforeValue, "wined3d")
        XCTAssertEqual(attempt.afterValue, "dxmt")
        XCTAssertEqual(attempt.result, .applied)
    }

    func testApplySwitchBackendWithBadParamFallsBackToRecommended() {
        let attempt = FixApplicator.apply(
            fixId: "switch-backend", params: ["backend": "not-a-backend"], bottle: bottle, program: nil
        )

        XCTAssertEqual(bottle.settings.graphicsBackend, .recommended)
        XCTAssertEqual(attempt.afterValue, "recommended")
    }

    func testApplyEnableDXVKAsync() {
        bottle.settings.dxvkAsync = false

        let attempt = FixApplicator.apply(fixId: "enable-dxvk-async", params: [:], bottle: bottle, program: nil)

        XCTAssertTrue(bottle.settings.dxvkAsync)
        XCTAssertEqual(attempt.beforeValue, "false")
        XCTAssertEqual(attempt.result, .applied)
    }

    func testApplyEnableEsync() {
        bottle.settings.enhancedSync = .none

        let attempt = FixApplicator.apply(fixId: "enable-esync", params: [:], bottle: bottle, program: nil)

        XCTAssertEqual(bottle.settings.enhancedSync, .esync)
        XCTAssertEqual(attempt.result, .applied)
    }

    func testApplyRegistryBackedFixesStayPendingForVerification() {
        let attempt = FixApplicator.apply(
            fixId: "set-buffer-size", params: ["preset": "stable"], bottle: bottle, program: nil
        )

        XCTAssertEqual(attempt.result, .pending)
    }

    func testApplyUnknownFixIdFails() {
        let attempt = FixApplicator.apply(fixId: "no.such_fix", params: [:], bottle: bottle, program: nil)

        XCTAssertEqual(attempt.result, .failed)
        XCTAssertNil(attempt.beforeValue)
    }

    // MARK: - Undo

    func testApplyThenUndoRestoresOriginalBackend() {
        bottle.settings.graphicsBackend = .dxvk
        let attempt = FixApplicator.apply(
            fixId: "switch-backend", params: ["backend": "dxmt"], bottle: bottle, program: nil
        )
        XCTAssertEqual(bottle.settings.graphicsBackend, .dxmt)

        let undone = FixApplicator.undo(attempt: attempt, bottle: bottle, program: nil)

        XCTAssertTrue(undone)
        XCTAssertEqual(bottle.settings.graphicsBackend, .dxvk)
    }

    func testUndoEsyncRestoresPriorMode() {
        bottle.settings.enhancedSync = .msync
        let attempt = FixApplicator.apply(fixId: "enable-esync", params: [:], bottle: bottle, program: nil)

        XCTAssertTrue(FixApplicator.undo(attempt: attempt, bottle: bottle, program: nil))
        XCTAssertEqual(bottle.settings.enhancedSync, .msync)
    }

    func testUndoWithMissingBeforeValueFails() {
        let attempt = FixAttempt(fixId: "switch-backend", beforeValue: nil, afterValue: "dxvk", result: .applied)

        XCTAssertFalse(FixApplicator.undo(attempt: attempt, bottle: bottle, program: nil))
    }

    func testUndoNonReversibleFixFails() {
        let attempt = FixAttempt(fixId: "install-dependency", afterValue: "dotnet48", result: .applied)

        XCTAssertFalse(FixApplicator.undo(attempt: attempt, bottle: bottle, program: nil))
    }

    func testUndoUnknownFixIdFails() {
        let attempt = FixAttempt(fixId: "no.such_fix", result: .applied)

        XCTAssertFalse(FixApplicator.undo(attempt: attempt, bottle: bottle, program: nil))
    }
}
