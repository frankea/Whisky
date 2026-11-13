//
//  KitLocalizationTests.swift
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

/// Checks the split between text shown in the UI, which comes from the string
/// catalog, and the English kept for environment provenance, diagnostics, and exports.
final class KitLocalizationTests: XCTestCase {
    // MARK: - Launcher Fixes

    func testEveryLauncherFixReasonMapsToTheCatalogEntryWithTheSameEnglish() {
        for launcher in LauncherType.allCases {
            for detail in launcher.fixDetails() {
                let localized = detail.localizedReason
                assertCatalogKey(localized)
                // The English provenance and the catalog's English must say the same.
                XCTAssertEqual(StringCatalog.english[localized], detail.reason, "\(launcher) \(detail.key)")
                XCTAssertFalse(detail.reason.contains("launcher.fix."), "reason should stay English")
            }
        }
    }

    func testFixReasonsWithoutACatalogEntryShowTheirEnglishReason() {
        let detail = LauncherFixDetail(
            key: "SOME_VAR", value: "1", reason: "A reason nobody mapped", category: .network
        )
        XCTAssertEqual(detail.localizedReason, "A reason nobody mapped")
    }

    func testSharedReasonsShareOneKey() {
        // Several launchers' locale fixes give the same reason, so they show the same text.
        let chromium = String(localized: "launcher.fix.reason.chromiumLocale")
        let locale = LauncherType.allCases
            .flatMap { $0.fixDetails() }
            .filter { $0.reason == StringCatalog.english[chromium] }
        XCTAssertGreaterThan(locale.count, 2)
        XCTAssertEqual(Set(locale.map(\.localizedReason)), [chromium])
        XCTAssertTrue(locale.allSatisfy { $0.category == .locale })
    }

    func testEveryFixCategoryHasItsOwnName() {
        let names = FixCategory.allCases.map(\.displayName)
        names.forEach { assertCatalogKey($0) }
        XCTAssertEqual(Set(names).count, FixCategory.allCases.count)
        XCTAssertEqual(FixCategory.locale.displayName, String(localized: "locale.title"))
        XCTAssertEqual(FixCategory.graphics.displayName, String(localized: "config.title.graphics"))
    }

    func testEveryLauncherHasItsOwnFixesDescription() {
        let descriptions = LauncherType.allCases.map(\.fixesDescription)
        for (launcher, description) in zip(LauncherType.allCases, descriptions) {
            assertCatalogKey(description)
            XCTAssertTrue(description.hasSuffix(".\(launcher)"), description)
        }
        XCTAssertEqual(Set(descriptions).count, LauncherType.allCases.count)
    }

    // MARK: - macOS Fixes

    func testEveryPlatformFixReasonMapsToTheCatalogEntryWithTheSameEnglish() {
        XCTAssertFalse(MacOSCompatibilityFixes.allFixes.isEmpty)
        for fix in MacOSCompatibilityFixes.allFixes {
            let localized = fix.localizedReason
            assertCatalogKey(localized)
            XCTAssertEqual(StringCatalog.english[localized], fix.reason, fix.key)
        }
    }

    func testBothCEFSandboxFixesShareTheirReason() {
        let sandbox = MacOSCompatibilityFixes.allFixes.filter { $0.category == .sandbox }.map(\.localizedReason)
        XCTAssertEqual(sandbox.count, 2)
        XCTAssertEqual(Set(sandbox), [String(localized: "launcher.platformFix.reason.cefSandbox")])
    }

    func testPlatformFixWithoutACatalogEntryShowsItsEnglishReason() {
        let fix = MacOSFix(
            key: "NEW_FIX", value: "1", reason: "Not in the catalog yet",
            appliesFrom: MacOSVersion(major: 26, minor: 0, patch: 0), category: .compatibility
        )
        XCTAssertEqual(fix.localizedReason, "Not in the catalog yet")
    }

    // MARK: - Crash Headlines

    private func makeDiagnosis(
        category: CrashCategory = .dependenciesLoading,
        confidence: Double = 0.9,
        captures: [String]
    ) -> CrashDiagnosis {
        let pattern = CrashPattern(
            id: "test-pattern", category: category, severity: .error, confidence: confidence,
            substringPrefilter: nil, regex: "x", tags: [], captureGroups: nil, remediationActionIds: nil
        )
        let match = DiagnosisMatch(pattern: pattern, lineIndex: 0, lineText: "x", captures: captures)
        return CrashDiagnosis(
            matches: [match],
            categoryCounts: [category: 1],
            primaryCategory: category,
            primaryConfidence: ConfidenceTier(score: confidence),
            headline: "English headline",
            exitCode: 3,
            applicableRemediationIds: []
        )
    }

    func testDisplayHeadlineWithoutCapturesUsesTheShortKey() throws {
        let diagnosis = makeDiagnosis(category: .graphics, confidence: 0.6, captures: [])
        let headline = try XCTUnwrap(diagnosis.displayHeadline)
        assertCatalogKey(headline)
        let name = CrashCategory.graphics.displayName
        let label = ConfidenceTier.medium.confidenceLabel
        XCTAssertEqual(headline, String(localized: "diagnostics.headline \(name) \(label)"))
    }

    func testDisplayHeadlineCarriesTheCapturesVerbatim() throws {
        let diagnosis = makeDiagnosis(captures: ["d3dx9_43.dll", "0xc0000135"])
        let headline = try XCTUnwrap(diagnosis.displayHeadline)
        assertCatalogKey(headline)
        XCTAssertEqual(StringCatalog.stem(headline), "diagnostics.headline.detail")
        XCTAssertTrue(headline.contains("d3dx9_43.dll, 0xc0000135"), headline)
        XCTAssertTrue(headline.contains(ConfidenceTier.high.confidenceLabel), headline)
    }

    func testEmptyDetailFallsBackToTheShortHeadline() {
        let short = CrashDiagnosis.localizedHeadline(category: .graphics, confidence: .low, detail: nil)
        XCTAssertEqual(CrashDiagnosis.localizedHeadline(category: .graphics, confidence: .low, detail: ""), short)
        XCTAssertEqual(StringCatalog.stem(short), "diagnostics.headline")
    }

    func testDisplayHeadlineWithoutMatchesIsTheStoredHeadline() {
        let empty = CrashDiagnosis(
            matches: [], categoryCounts: [:], primaryCategory: nil, primaryConfidence: nil,
            headline: nil, exitCode: nil, applicableRemediationIds: []
        )
        XCTAssertNil(empty.displayHeadline)
    }

    func testClassifierHeadlineStaysEnglish() throws {
        let (patterns, remediations) = PatternLoader.loadDefaults()
        let classifier = CrashClassifier(patterns: patterns, remediations: remediations)
        let diagnosis = classifier.classify(log: "err:module:import_dll Library d3dx9_43.dll not found")
        let category = try XCTUnwrap(diagnosis.primaryCategory)
        let headline = try XCTUnwrap(diagnosis.headline)
        XCTAssertTrue(headline.hasPrefix(category.exportName), headline)
        XCTAssertTrue(headline.hasSuffix("confidence)"), headline)
        XCTAssertNotEqual(diagnosis.displayHeadline, headline)
    }

    // MARK: - Diagnostic Export

    @MainActor
    func testExportedReportUsesEnglishCategoryNames() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "KitLocalizationTests-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let bottle = Bottle(bottleUrl: dir, inFlight: false, isAvailable: true)
        let program = Program(url: dir.appending(path: "game.exe"), bottle: bottle, peFile: nil)

        let report = DiagnosticExporter.generateReportMarkdown(
            diagnosis: makeDiagnosis(category: .graphics, captures: ["0x887a0005"]),
            bottle: bottle,
            program: program,
            options: ExportOptions()
        )
        XCTAssertTrue(report.contains("- **Primary Category:** Graphics / GPU\n"), report)
        XCTAssertTrue(report.contains("- Graphics / GPU: 1\n"), report)
        XCTAssertTrue(report.contains("- **test-pattern** [Graphics / GPU] (High confidence)"), report)
        XCTAssertTrue(report.contains("**English headline**"), report)
        XCTAssertFalse(report.contains("diagnostics."), "the report should hold no catalog keys")
    }

    // MARK: - WINEDEBUG Presets

    func testPresetNamesAndDescriptionsAreLocalizedWhileExportNamesStayEnglish() {
        let english = ["Normal", "Crash Analysis", "DLL Loading", "Verbose"]
        XCTAssertEqual(WineDebugPreset.allCases.map(\.exportName), english)
        for preset in WineDebugPreset.allCases {
            assertCatalogKey(preset.displayName)
            assertCatalogKey(preset.presetDescription)
            // The catalog's English name is the export name.
            XCTAssertEqual(StringCatalog.english[preset.displayName], preset.exportName)
        }
        XCTAssertEqual(Set(WineDebugPreset.allCases.map(\.presetDescription)).count, WineDebugPreset.allCases.count)
    }

    // MARK: - Resolution Presets

    func testFixedSizesArePlainNumbersAndTheRestAreCatalogKeys() {
        XCTAssertEqual(ResolutionPreset.r1280x720.label, "1280 x 720")
        XCTAssertEqual(ResolutionPreset.r2560x1440.label, "2560 x 1440")
        XCTAssertEqual(ResolutionPreset.r3840x2160.label, "3840 x 2160")

        let defaultLabel = ResolutionPreset.r1920x1080.label
        assertCatalogKey(defaultLabel)
        XCTAssertTrue(defaultLabel.hasSuffix("1920 x 1080"), defaultLabel)
        assertCatalogKey(ResolutionPreset.matchDisplay.label)
        assertCatalogKey(ResolutionPreset.custom.label)
        let labels = ResolutionPreset.allCases.map(\.label)
        XCTAssertEqual(Set(labels).count, labels.count)
    }

    // MARK: - Tar Errors

    func testTarErrorsFallBackToTheirEnglishMessage() {
        let errors: [TarError] = [
            .pathTraversal(path: "../../etc/passwd"),
            .unsafeSymlink(path: "lib/link", target: "/usr/lib"),
            .commandFailed(output: "tar: truncated")
        ]
        for error in errors {
            // Without the app's catalog the lookup returns its English default,
            // which is the English diagnostics message.
            XCTAssertEqual(error.errorDescription, error.diagnosticMessage)
        }
        XCTAssertTrue(errors[0].diagnosticMessage.hasSuffix(": ../../etc/passwd"))
        XCTAssertEqual(errors[1].diagnosticMessage, "Archive contains symlink 'lib/link' with unsafe target '/usr/lib'")
        XCTAssertEqual(errors[2].diagnosticMessage, "Tar command failed: tar: truncated")
    }

    func testTarCatalogEnglishMatchesTheDiagnosticMessage() throws {
        func english(_ key: String, _ arguments: CVarArg...) throws -> String {
            try String(format: XCTUnwrap(StringCatalog.english[key], key), arguments: arguments)
        }
        XCTAssertEqual(
            try english("tar.error.pathTraversal", "../x"),
            TarError.pathTraversal(path: "../x").diagnosticMessage
        )
        XCTAssertEqual(
            try english("tar.error.unsafeSymlink", "a", "/b"),
            TarError.unsafeSymlink(path: "a", target: "/b").diagnosticMessage
        )
        XCTAssertEqual(
            try english("tar.error.commandFailed", "boom"),
            TarError.commandFailed(output: "boom").diagnosticMessage
        )
    }
}
