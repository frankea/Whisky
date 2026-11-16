//
//  LocalizedCheckSummaryMoreTests.swift
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

/// The on-screen summaries of the file, registry, winetricks, process, and
/// audio checks, built from results the checks really produce.
///
/// In the test runner a lookup returns its key with the arguments
/// substituted, so each expected string is the catalog key followed by the
/// values the summary interpolates.
final class LocalizedCheckSummaryMoreTests: XCTestCase {
    private var bottleURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        bottleURL = FileManager.default.temporaryDirectory.appending(path: "check-summary-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: bottleURL)
        try super.tearDownWithError()
    }

    private func context() -> CheckContext {
        let preflight = PreflightData(
            bottleURL: bottleURL,
            bottleName: "Test Bottle",
            isWineserverRunning: false,
            processCount: 0,
            graphicsBackend: "dxmt"
        )
        return CheckContext(
            bottleURL: bottleURL,
            bottleName: "Test Bottle",
            programName: nil,
            preflight: preflight,
            session: TroubleshootingSession(bottleURL: bottleURL)
        )
    }

    private func placeDLL(_ name: String, in folder: String) throws {
        let directory = bottleURL.appending(path: "drive_c").appending(path: "windows").appending(path: folder)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: directory.appending(path: name))
    }

    // MARK: - DependencyCheck

    func testDependencyAllFoundCountsEveryCheckedDLL() async throws {
        try placeDLL("d3dx9_43.dll", in: "system32")
        try placeDLL("xinput1_3.dll", in: "syswow64")

        let result = await DependencyCheck().run(params: ["dlls": "d3dx9_43.dll, xinput1_3.dll"], context: context())
        let localized = try XCTUnwrap(DependencyCheck.localizedSummary(for: result))

        XCTAssertEqual(result.outcome, .pass)
        XCTAssertEqual(localized, "troubleshooting.check.dependency.allFound 2")
        assertCatalogKey(localized)
        XCTAssertEqual(result.summary, "All 2 DLL(s) found in prefix", "the exported summary stays English")
    }

    func testDependencyMissingCountsAndNamesOnlyTheMissingDLLs() async throws {
        try placeDLL("d3dx9_43.dll", in: "system32")

        let result = await DependencyCheck().run(
            params: ["dlls": "d3dx9_43.dll,xinput1_3.dll, msvcp140.dll"],
            context: context()
        )
        let localized = try XCTUnwrap(DependencyCheck.localizedSummary(for: result))

        XCTAssertEqual(result.outcome, .fail)
        XCTAssertEqual(localized, "troubleshooting.check.dependency.missing 2 xinput1_3.dll, msvcp140.dll")
        assertCatalogKey(localized)
        XCTAssertEqual(result.summary, "2 missing DLL(s): xinput1_3.dll, msvcp140.dll")
    }

    func testDependencyMissingListIgnoresBlankEntries() throws {
        let result = CheckResult(outcome: .fail, evidence: ["missing": "a.dll, ,b.dll,"], summary: "")

        XCTAssertEqual(
            DependencyCheck.localizedSummary(for: result),
            "troubleshooting.check.dependency.missing 2 a.dll, b.dll"
        )
    }

    func testDependencyHasNoLocalizedSummaryWithoutItsEvidence() async {
        let error = await DependencyCheck().run(params: [:], context: context())

        XCTAssertEqual(error.outcome, .error)
        XCTAssertNil(DependencyCheck.localizedSummary(for: error))
        XCTAssertNil(DependencyCheck.localizedSummary(for: CheckResult(outcome: .pass, summary: "foreign")))
        XCTAssertNil(DependencyCheck.localizedSummary(for: CheckResult(outcome: .fail, summary: "foreign")))
        XCTAssertNil(DependencyCheck.localizedSummary(
            for: CheckResult(outcome: .unknown, evidence: ["checked": "a.dll"], summary: "")
        ))
    }

    // MARK: - RegistryValueCheck

    private static let registryKey = #"HKCU\Software\Wine\Direct3D"#

    private func writeUserReg() throws {
        let userReg = #"""
        WINE REGISTRY Version 2
        [Software\\Wine\\Direct3D] 1788028146
        "renderer"="gl"
        """#
        try userReg.write(to: bottleURL.appending(path: "user.reg"), atomically: true, encoding: .utf8)
    }

    func testRegistryNotFoundNamesTheKeyAndTheValue() async throws {
        try writeUserReg()

        let result = await RegistryValueCheck().run(
            params: ["key": Self.registryKey, "valueName": "csmt"],
            context: context()
        )
        let localized = try XCTUnwrap(RegistryValueCheck.localizedSummary(for: result))

        XCTAssertEqual(result.outcome, .unknown)
        XCTAssertEqual(localized, "troubleshooting.check.registry.notFound \(Self.registryKey) csmt")
        assertCatalogKey(localized)
    }

    func testRegistryMismatchNamesTheValueTheCurrentAndTheExpected() async throws {
        try writeUserReg()

        let result = await RegistryValueCheck().run(
            params: ["key": Self.registryKey, "valueName": "renderer", "expected": "vulkan"],
            context: context()
        )
        let localized = try XCTUnwrap(RegistryValueCheck.localizedSummary(for: result))

        XCTAssertEqual(result.outcome, .fail)
        XCTAssertEqual(localized, "troubleshooting.check.value.mismatch renderer gl vulkan")
        assertCatalogKey(localized)
        XCTAssertEqual(result.summary, "renderer is gl, expected vulkan")
    }

    func testRegistryWordlessAndErrorResultsKeepTheirSummary() async throws {
        try writeUserReg()
        let matched = await RegistryValueCheck().run(
            params: ["key": Self.registryKey, "valueName": "renderer", "expected": "gl"],
            context: context()
        )
        let unchecked = await RegistryValueCheck().run(
            params: ["key": Self.registryKey, "valueName": "renderer"],
            context: context()
        )
        let error = await RegistryValueCheck().run(params: ["key": Self.registryKey], context: context())

        XCTAssertEqual(matched.outcome, .pass)
        XCTAssertNil(RegistryValueCheck.localizedSummary(for: matched))
        XCTAssertEqual(unchecked.outcome, .pass)
        XCTAssertNil(RegistryValueCheck.localizedSummary(for: unchecked))
        XCTAssertEqual(error.outcome, .error)
        XCTAssertNil(RegistryValueCheck.localizedSummary(for: error))
        let failWithoutExpected = CheckResult(
            outcome: .fail,
            evidence: ["key": Self.registryKey, "valueName": "renderer", "currentValue": "gl"],
            summary: ""
        )
        XCTAssertNil(RegistryValueCheck.localizedSummary(for: failWithoutExpected))
    }

    // MARK: - WinetricksVerbCheck

    func testWinetricksAllInstalled() async throws {
        try WinetricksVerbCache.save(WinetricksVerbCache(installedVerbs: ["vcrun2019", "d3dx9"]), to: bottleURL)

        let result = await WinetricksVerbCheck().run(params: ["verbs": "vcrun2019, d3dx9"], context: context())
        let localized = try XCTUnwrap(WinetricksVerbCheck.localizedSummary(for: result))

        XCTAssertEqual(result.outcome, .alreadyConfigured)
        XCTAssertEqual(localized, "troubleshooting.check.winetricks.allInstalled")
        assertCatalogKey(localized)
    }

    func testWinetricksMissingCountsAndNamesTheMissingVerbs() async throws {
        try WinetricksVerbCache.save(WinetricksVerbCache(installedVerbs: ["vcrun2019"]), to: bottleURL)

        let result = await WinetricksVerbCheck().run(
            params: ["verbs": "vcrun2019, d3dx9, dotnet48"],
            context: context()
        )
        let localized = try XCTUnwrap(WinetricksVerbCheck.localizedSummary(for: result))

        XCTAssertEqual(result.outcome, .fail)
        XCTAssertEqual(localized, "troubleshooting.check.winetricks.missing 2 d3dx9, dotnet48")
        assertCatalogKey(localized)
        XCTAssertEqual(result.summary, "2 missing verb(s): d3dx9, dotnet48")
    }

    func testWinetricksWithoutACacheReportsASingleMissingVerb() async throws {
        let result = await WinetricksVerbCheck().run(params: ["verbs": "corefonts"], context: context())

        XCTAssertEqual(
            WinetricksVerbCheck.localizedSummary(for: result),
            "troubleshooting.check.winetricks.missing 1 corefonts"
        )
    }

    func testWinetricksHasNoLocalizedSummaryForOtherResults() async {
        let error = await WinetricksVerbCheck().run(params: [:], context: context())

        XCTAssertEqual(error.outcome, .error)
        XCTAssertNil(WinetricksVerbCheck.localizedSummary(for: error))
        XCTAssertNil(WinetricksVerbCheck.localizedSummary(for: CheckResult(outcome: .pass, summary: "")))
        XCTAssertNil(WinetricksVerbCheck.localizedSummary(for: CheckResult(outcome: .unknown, summary: "")))
        XCTAssertNil(WinetricksVerbCheck.localizedSummary(
            for: CheckResult(outcome: .fail, evidence: ["missing": ""], summary: "")
        ))
    }

    // MARK: - ProcessRunningCheck

    @MainActor
    func testProcessRunningCountsTheBottlesProcesses() async throws {
        let bottle = Bottle(bottleUrl: bottleURL, inFlight: false, isAvailable: true)
        let processes = [Process(), Process()]
        for process in processes {
            ProcessRegistry.shared.register(process: process, bottle: bottle, programName: "game.exe")
        }
        defer { ProcessRegistry.shared.clearRegistry(for: bottle.url) }

        let result = await ProcessRunningCheck().run(params: [:], context: context())
        let localized = try XCTUnwrap(ProcessRunningCheck.localizedSummary(for: result))

        XCTAssertEqual(result.outcome, .pass)
        XCTAssertEqual(localized, "troubleshooting.check.process.running 2")
        assertCatalogKey(localized)
    }

    func testProcessRunningNone() async throws {
        let result = await ProcessRunningCheck().run(params: [:], context: context())
        let localized = try XCTUnwrap(ProcessRunningCheck.localizedSummary(for: result))

        XCTAssertEqual(result.outcome, .fail)
        XCTAssertEqual(localized, "troubleshooting.check.process.none")
        assertCatalogKey(localized)
        XCTAssertEqual(result.summary, "No Wine processes running for this bottle")
    }

    func testProcessRunningHasNoLocalizedSummaryWithoutACount() {
        XCTAssertNil(ProcessRunningCheck.localizedSummary(
            for: CheckResult(outcome: .pass, evidence: ["count": "many"], summary: "")
        ))
        XCTAssertNil(ProcessRunningCheck.localizedSummary(for: CheckResult(outcome: .pass, summary: "")))
        XCTAssertNil(ProcessRunningCheck.localizedSummary(for: CheckResult(outcome: .error, summary: "")))
    }

    // MARK: - AudioTestCheck

    func testAudioTestUnavailableIsLocalizedOnScreenAndEnglishInTheSummary() async throws {
        let result = await AudioTestCheck().run(params: [:], context: context())
        let localized = try XCTUnwrap(AudioTestCheck.localizedSummary(for: result))
        let reason = try XCTUnwrap(result.evidence["reason"])

        XCTAssertEqual(result.outcome, .unknown)
        XCTAssertEqual(localized, "troubleshooting.check.audioTest.unavailable")
        assertCatalogKey(localized)
        XCTAssertEqual(reason, "troubleshooting.check.audioTest.unavailableReason")
        assertCatalogKey(reason)
        XCTAssertEqual(result.summary, "Audio playback test is not available (MinGW not compiled)")
    }

    func testAudioTestHasNoLocalizedSummaryForOtherOutcomes() {
        for outcome in [CheckOutcome.pass, .fail, .alreadyConfigured, .error] {
            XCTAssertNil(AudioTestCheck.localizedSummary(for: CheckResult(outcome: outcome, summary: "")), "\(outcome)")
        }
    }
}
