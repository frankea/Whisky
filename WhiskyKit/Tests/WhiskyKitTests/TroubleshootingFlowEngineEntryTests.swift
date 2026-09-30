//
//  TroubleshootingFlowEngineEntryTests.swift
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

/// Where a fresh wizard session lands for each entry point, with the flows
/// the app ships. It has to be a flow step or symptom selection. Anything
/// else is the "Running checks" spinner with no check behind it, where Skip
/// and Back are disabled and Close is the only way out.
@MainActor
final class TroubleshootingFlowEngineEntryTests: XCTestCase {
    private let bottleURL = URL(filePath: "/tmp/engine-entry-test-bottle")
    private let programURL = URL(filePath: "/tmp/engine-entry-test-bottle/drive_c/Game/Game.exe")

    /// Does what the wizard does on appear when there is no session to
    /// resume: binds the session to the entry point, takes the preflight
    /// snapshot, then starts.
    private func startEngine(from context: EntryContext) -> (TroubleshootingFlowEngine, SpySessionStore) {
        let store = SpySessionStore()
        let engine = TroubleshootingFlowEngine(
            flowDefinitions: FlowLoader.loadAllFlows(),
            fragments: FlowLoader.loadFragments(),
            checkRegistry: CheckRegistry(),
            sessionStore: store
        )
        engine.session.bottleURL = context.bottleURL
        engine.session.programURL = context.programURL
        engine.session.preflightSnapshot = PreflightData(
            bottleURL: context.bottleURL,
            bottleName: "Entry Test",
            programURL: context.programURL,
            isWineserverRunning: false,
            processCount: 0,
            graphicsBackend: "dxvk"
        )
        engine.start(from: context)
        return (engine, store)
    }

    private func assertHasSomethingToShow(
        _ engine: TroubleshootingFlowEngine,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            engine.currentNode != nil || engine.session.phase == .symptom,
            "landed in the \(engine.session.phase) phase with no step to show",
            file: file,
            line: line
        )
    }

    func testProgramEntryStartsAtSymptomSelection() {
        let (engine, store) = startEngine(from: .program(programURL: programURL, bottleURL: bottleURL))

        assertHasSomethingToShow(engine)
        XCTAssertEqual(engine.session.phase, .symptom)
        XCTAssertEqual(store.saveCount, 0)
    }

    func testLaunchFailureEntryStartsTheLaunchCrashFlow() {
        let (engine, _) = startEngine(from: .launchFailure(
            programURL: programURL,
            bottleURL: bottleURL,
            evidence: ["crashCategory": "unknown"]
        ))

        assertHasSomethingToShow(engine)
        XCTAssertEqual(engine.session.symptomCategory, .launchCrash)
        XCTAssertEqual(engine.currentNode?.id, FlowLoader.loadAllFlows()["launch-crash"]?.entryNodeId)
    }

    /// Bottle Configuration's Start Guided Troubleshooting. It has no
    /// program and no evidence, so there is no symptom to assume.
    func testBottleDiagnosticsEntryStartsAtSymptomSelection() {
        let (engine, store) = startEngine(from: .bottleDiagnostics(bottleURL: bottleURL))

        assertHasSomethingToShow(engine)
        XCTAssertEqual(engine.session.phase, .symptom)
        XCTAssertFalse(engine.isRunningCheck)
        // Opening the wizard and closing it again leaves nothing to resume.
        XCTAssertEqual(store.saveCount, 0)
    }

    func testHelpMenuEntryStartsAtSymptomSelection() {
        let contexts: [EntryContext] = [
            .helpMenu(bottleURL: bottleURL, programURL: nil),
            .helpMenu(bottleURL: bottleURL, programURL: programURL)
        ]
        for context in contexts {
            let (engine, store) = startEngine(from: context)

            assertHasSomethingToShow(engine)
            XCTAssertEqual(engine.session.phase, .symptom)
            XCTAssertEqual(store.saveCount, 0)
        }
    }
}
