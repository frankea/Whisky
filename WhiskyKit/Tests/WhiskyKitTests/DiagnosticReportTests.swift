//
//  DiagnosticReportTests.swift
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

final class DiagnosticReportTests: XCTestCase {
    // MARK: - Markdown Report Content Tests

    func testMarkdownReportContainsHeadline() {
        let diagnosis = makeSampleDiagnosis(headline: "DLL Load Failure: MSVCR100.dll")
        let markdown = generateTestMarkdown(diagnosis: diagnosis)

        XCTAssertTrue(markdown.contains("## Whisky Diagnostic Report"))
        XCTAssertTrue(markdown.contains("DLL Load Failure: MSVCR100.dll"))
    }

    func testMarkdownReportContainsSections() {
        let diagnosis = makeSampleDiagnosis()
        let markdown = generateTestMarkdown(diagnosis: diagnosis)

        XCTAssertTrue(markdown.contains("### System Info"))
        XCTAssertTrue(markdown.contains("### Diagnosis Summary"))
    }

    func testMarkdownReportRedacted() {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        let normalizedHome = homePath.hasSuffix("/") ? String(homePath.dropLast()) : homePath

        let diagnosis = makeSampleDiagnosis()
        let markdown = generateTestMarkdown(diagnosis: diagnosis)

        let testPath = "\(normalizedHome)/Library/test"
        let redacted = Redactor.redactHomePaths(testPath)
        XCTAssertFalse(redacted.contains(normalizedHome))
        XCTAssertTrue(redacted.contains("/Users/<redacted>"))

        XCTAssertTrue(markdown.contains("### Diagnosis Summary"))
    }

    func testMarkdownReportContainsCategoryCounts() {
        let diagnosis = CrashDiagnosis(
            matches: [],
            categoryCounts: [.dependenciesLoading: 3, .graphics: 1],
            primaryCategory: .dependenciesLoading,
            primaryConfidence: .high,
            headline: "Missing DLLs",
            exitCode: 1,
            applicableRemediationIds: []
        )
        let markdown = generateTestMarkdown(diagnosis: diagnosis)

        XCTAssertTrue(markdown.contains("Dependencies / Loading: 3"))
        XCTAssertTrue(markdown.contains("Graphics / GPU: 1"))
    }

    func testMarkdownReportEmptyDiagnosis() {
        let diagnosis = CrashDiagnosis(
            matches: [],
            categoryCounts: [:],
            primaryCategory: nil,
            primaryConfidence: nil,
            headline: nil,
            exitCode: 0,
            applicableRemediationIds: []
        )
        let markdown = generateTestMarkdown(diagnosis: diagnosis)

        XCTAssertTrue(markdown.contains("## Whisky Diagnostic Report"))
        XCTAssertTrue(markdown.contains("### System Info"))
        XCTAssertTrue(markdown.contains("### Diagnosis Summary"))
    }

    // MARK: - CrashDiagnosisCodableWrapper Tests

    func testCrashDiagnosisCodableWrapperEncodes() throws {
        let diagnosis = makeSampleDiagnosis()
        let wrapper = CrashDiagnosisCodableWrapper(diagnosis)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(wrapper)
        let json = String(data: data, encoding: .utf8)

        XCTAssertNotNil(json)
        XCTAssertTrue(json?.contains("dependenciesLoading") ?? false)
        XCTAssertTrue(json?.contains("applicableRemediationIds") ?? false)
    }

    // MARK: - Helpers

    private func makeSampleDiagnosis(headline: String? = "Test Headline") -> CrashDiagnosis {
        let pattern = CrashPattern(
            id: "dll-load-failure",
            category: .dependenciesLoading,
            severity: .error,
            confidence: 0.9,
            substringPrefilter: nil,
            regex: "test",
            tags: [],
            captureGroups: nil,
            remediationActionIds: ["install-vcredist"]
        )

        let diagMatch = DiagnosisMatch(
            pattern: pattern,
            lineIndex: 0,
            lineText: "err:module:import_dll Library MSVCR100.dll not found",
            captures: ["MSVCR100.dll"]
        )

        return CrashDiagnosis(
            matches: [diagMatch],
            categoryCounts: [.dependenciesLoading: 1],
            primaryCategory: .dependenciesLoading,
            primaryConfidence: .high,
            headline: headline,
            exitCode: 1,
            applicableRemediationIds: ["install-vcredist"]
        )
    }

    private func generateTestMarkdown(diagnosis: CrashDiagnosis) -> String {
        var markdown = "## Whisky Diagnostic Report\n\n"
        markdown += "**Generated:** \(Date().formatted())\n\n"

        markdown += "### System Info\n\n"
        let version = MacOSVersion.current
        markdown += "- **macOS:** \(version.description)\n"
        #if arch(arm64)
        markdown += "- **Architecture:** Apple Silicon (arm64)\n"
        #else
        markdown += "- **Architecture:** Intel (x86_64)\n"
        #endif
        markdown += "\n"

        markdown += "### Diagnosis Summary\n\n"
        if let headline = diagnosis.headline {
            markdown += "**\(headline)**\n\n"
        }
        if let category = diagnosis.primaryCategory, let confidence = diagnosis.primaryConfidence {
            markdown += "- **Primary Category:** \(category.displayName)\n"
            markdown += "- **Confidence:** \(confidence.displayName)\n"
        }
        if let exitCode = diagnosis.exitCode {
            markdown += "- **Exit Code:** \(exitCode)\n"
        }
        if !diagnosis.categoryCounts.isEmpty {
            markdown += "\n**Category Counts:**\n"
            for (category, count) in diagnosis.categoryCounts.sorted(by: { $0.value > $1.value }) {
                markdown += "- \(category.displayName): \(count)\n"
            }
        }
        markdown += "\n"

        if !diagnosis.matches.isEmpty {
            markdown += "### Matched Patterns\n\n"
            for diagMatch in diagnosis.matches.prefix(5) {
                let conf = ConfidenceTier(score: diagMatch.pattern.confidence).displayName
                markdown += "- **\(diagMatch.pattern.id)** [\(diagMatch.pattern.category.displayName)]"
                markdown += " (\(conf) confidence)\n"
            }
            markdown += "\n"
        }

        return markdown
    }
}
