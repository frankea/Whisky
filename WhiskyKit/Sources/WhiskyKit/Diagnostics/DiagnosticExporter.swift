// swiftlint:disable file_length
//
//  DiagnosticExporter.swift
//  WhiskyKit
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

import Foundation

/// Options controlling what content is included in a diagnostic export.
public struct ExportOptions: Sendable {
    /// Whether to include sensitive details (home paths, secret env values).
    /// Defaults to `false` (redacted by default).
    public var includeSensitiveDetails: Bool

    /// Whether to include remediation history in the export.
    public var includeRemediationHistory: Bool

    /// Whether to include the full log file in the ZIP export.
    public var includeFullLog: Bool

    /// Number of lines to include in the tail log excerpt.
    public var tailLineCount: Int

    public init(
        includeSensitiveDetails: Bool = false,
        includeRemediationHistory: Bool = true,
        includeFullLog: Bool = true,
        tailLineCount: Int = 500
    ) {
        self.includeSensitiveDetails = includeSensitiveDetails
        self.includeRemediationHistory = includeRemediationHistory
        self.includeFullLog = includeFullLog
        self.tailLineCount = tailLineCount
    }
}

/// Exports diagnostic data as ZIP archives or Markdown reports.
///
/// All exported content passes through ``Redactor`` by default unless
/// ``ExportOptions/includeSensitiveDetails`` is set to `true`.
/// Follows the ``GPUDetection`` caseless-enum pattern.
///
/// ## Export Formats
///
/// - **ZIP**: Contains `report.md`, `crash.json`, `env.json`, settings files,
///   log files, and `system.json`. Created via `/usr/bin/ditto`.
/// - **Markdown**: A single paste-ready Markdown block for GitHub issues.
///   Always redacted regardless of options.
public enum DiagnosticExporter {
    // MARK: - ZIP Export

    /// Exports a complete diagnostic report as a ZIP archive.
    /// Creates a temporary directory containing all diagnostic files, then
    /// compresses it via `/usr/bin/ditto`. The temporary directory is cleaned
    /// up after compression.
    @MainActor
    public static func exportZIP(
        diagnosis: CrashDiagnosis,
        bottle: Bottle,
        program: Program,
        logFileURL: URL?,
        timeline: RemediationTimeline?,
        options: ExportOptions = ExportOptions()
    ) async -> URL {
        let context = ZIPExportContext(
            diagnosis: diagnosis,
            bottle: bottle,
            program: program,
            logFileURL: logFileURL,
            timeline: timeline,
            options: options
        )

        return await buildZIPArchive(context: context)
    }

    // MARK: - Markdown Export

    /// Generates a Markdown diagnostic report suitable for pasting into GitHub issues.
    ///
    /// The report is always redacted (no sensitive details in clipboard copy).
    /// Includes system info, bottle config, diagnosis summary, matched patterns,
    /// suggested remediations, and environment keys (keys only, no values).
    ///
    /// - Parameters:
    ///   - diagnosis: The crash diagnosis to report.
    ///   - bottle: The bottle that was analyzed.
    ///   - program: The program that was analyzed.
    ///   - options: Export options (only `includeSensitiveDetails` is relevant; defaults to always-redacted).
    /// - Returns: A Markdown string ready for pasting.
    @MainActor
    public static func generateMarkdownReport(
        diagnosis: CrashDiagnosis,
        bottle: Bottle,
        program: Program,
        options: ExportOptions = ExportOptions()
    ) async -> String {
        // Markdown copy is always redacted regardless of options
        let redactedOptions = ExportOptions(
            includeSensitiveDetails: false,
            includeRemediationHistory: options.includeRemediationHistory,
            includeFullLog: false,
            tailLineCount: options.tailLineCount
        )
        return generateReportMarkdown(
            diagnosis: diagnosis,
            bottle: bottle,
            program: program,
            options: redactedOptions
        )
    }

    // MARK: - Internal Content Generators

    /// Generates the main report.md content.
    @MainActor
    static func generateReportMarkdown(
        diagnosis: CrashDiagnosis,
        bottle: Bottle,
        program: Program,
        options: ExportOptions
    ) -> String {
        var markdown = "## Whisky Diagnostic Report\n\n"
        markdown += "**Generated:** \(Date().formatted())\n\n"

        markdown += generateSystemInfoSection()
        markdown += generateBottleConfigSection(bottle: bottle)
        markdown += generateDiagnosisSummarySection(diagnosis: diagnosis)
        markdown += generateMatchedPatternsSection(diagnosis: diagnosis)
        markdown += generateSuggestedRemediationsSection(diagnosis: diagnosis)
        markdown += generateEnvironmentKeysSection(bottle: bottle)

        return markdown
    }

    @MainActor
    private static func generateSystemInfoSection() -> String {
        var section = "### System Info\n\n"
        let version = MacOSVersion.current
        section += "- **macOS:** \(version.description)\n"
        #if arch(arm64)
        section += "- **Architecture:** Apple Silicon (arm64)\n"
        #else
        section += "- **Architecture:** Intel (x86_64)\n"
        #endif
        if let whiskyWineVersion = WhiskyWineInstaller.whiskyWineVersion() {
            section += "- **WhiskyWine:** \(whiskyWineVersion.major).\(whiskyWineVersion.minor)"
            section += ".\(whiskyWineVersion.patch)\n"
        }
        section += "\n"
        return section
    }

    @MainActor
    private static func generateBottleConfigSection(bottle: Bottle) -> String {
        var section = "### Bottle Config\n\n"
        section += "- **Bottle:** \(bottle.settings.name)\n"
        section += "- **Windows Version:** \(bottle.settings.windowsVersion)\n"
        section += "- **Graphics Backend:** \(bottle.settings.graphicsBackend)\n"
        section += "- **DXVK Async:** \(bottle.settings.dxvkAsync ? "Enabled" : "Disabled")\n"
        section += "- **Enhanced Sync:** \(bottle.settings.enhancedSync)\n"
        section += "- **Performance Preset:** \(bottle.settings.performancePreset)\n"
        section += "\n"
        return section
    }

    @MainActor
    private static func generateDiagnosisSummarySection(diagnosis: CrashDiagnosis) -> String {
        var section = "### Diagnosis Summary\n\n"
        if let headline = diagnosis.headline {
            section += "**\(headline)**\n\n"
        }
        if let category = diagnosis.primaryCategory, let confidence = diagnosis.primaryConfidence {
            section += "- **Primary Category:** \(category.displayName)\n"
            section += "- **Confidence:** \(confidence.displayName)\n"
        }
        if let exitCode = diagnosis.exitCode {
            section += "- **Exit Code:** \(exitCode)\n"
        }
        if !diagnosis.categoryCounts.isEmpty {
            section += "\n**Category Counts:**\n"
            for (category, count) in diagnosis.categoryCounts.sorted(by: { $0.value > $1.value }) {
                section += "- \(category.displayName): \(count)\n"
            }
        }
        section += "\n"
        return section
    }

    @MainActor
    private static func generateMatchedPatternsSection(diagnosis: CrashDiagnosis) -> String {
        guard !diagnosis.matches.isEmpty else { return "" }
        var section = "### Matched Patterns\n\n"
        for diagMatch in diagnosis.matches.prefix(5) {
            let conf = ConfidenceTier(score: diagMatch.pattern.confidence).displayName
            section += "- **\(diagMatch.pattern.id)** [\(diagMatch.pattern.category.displayName)]"
            section += " (\(conf) confidence)\n"
            if !diagMatch.captures.isEmpty {
                section += "  - Captures: \(diagMatch.captures.joined(separator: ", "))\n"
            }
        }
        section += "\n"
        return section
    }

    @MainActor
    private static func generateSuggestedRemediationsSection(diagnosis: CrashDiagnosis) -> String {
        guard !diagnosis.applicableRemediationIds.isEmpty else { return "" }
        let (_, remediations) = PatternLoader.loadDefaults()
        let resolved = diagnosis.remediations(from: remediations)
        guard !resolved.isEmpty else { return "" }

        var section = "### Suggested Remediations\n\n"
        for action in resolved {
            section += "- **\(action.title)** [\(action.risk) risk]: \(action.whatWillChange)\n"
        }
        section += "\n"
        return section
    }

    @MainActor
    private static func generateEnvironmentKeysSection(bottle: Bottle) -> String {
        var section = "### Environment Keys\n\n"
        let env = Wine.constructWineEnvironment(for: bottle, environment: [:])
        let sortedKeys = env.keys.sorted()
        section += sortedKeys.joined(separator: ", ")
        section += "\n"
        return section
    }

    /// Generates a JSON string with bottle settings summary.
    @MainActor
    static func bottleSettingsSummary(bottle: Bottle) -> String {
        var info: [String: String] = [:]
        info["name"] = bottle.settings.name
        info["windowsVersion"] = "\(bottle.settings.windowsVersion)"
        info["graphicsBackend"] = "\(bottle.settings.graphicsBackend)"
        info["dxvkAsync"] = "\(bottle.settings.dxvkAsync)"
        info["enhancedSync"] = "\(bottle.settings.enhancedSync)"
        info["performancePreset"] = "\(bottle.settings.performancePreset)"
        info["metalHud"] = "\(bottle.settings.metalHud)"
        info["metalValidation"] = "\(bottle.settings.metalValidation)"
        info["dxrEnabled"] = "\(bottle.settings.dxrEnabled)"
        info["forceD3D11"] = "\(bottle.settings.forceD3D11)"
        info["shaderCacheEnabled"] = "\(bottle.settings.shaderCacheEnabled)"
        info["avxEnabled"] = "\(bottle.settings.avxEnabled)"
        info["sequoiaCompatMode"] = "\(bottle.settings.sequoiaCompatMode)"
        info["launcherCompatibilityMode"] = "\(bottle.settings.launcherCompatibilityMode)"

        return dictionaryToJSON(info)
    }

    /// Generates a JSON string with program settings summary.
    @MainActor
    static func programSettingsSummary(program: Program) -> String {
        var info: [String: String] = [:]
        info["name"] = program.name
        info["path"] = Redactor.redactHomePaths(program.url.path(percentEncoded: false))
        info["locale"] = "\(program.settings.locale)"
        info["arguments"] = program.settings.arguments
        info["hasOverrides"] = "\(program.settings.overrides != nil)"

        return dictionaryToJSON(info)
    }

    /// Generates a JSON string with environment variables, redacted as configured.
    @MainActor
    static func generateEnvironmentJSON(bottle: Bottle, options: ExportOptions) -> String {
        let env = Wine.constructWineEnvironment(for: bottle, environment: [:])
        let redacted = Redactor.redactEnvironment(env, includeSensitive: options.includeSensitiveDetails)
        return dictionaryToJSON(redacted)
    }

    /// Generates a JSON string with system information.
    static func generateSystemInfoJSON() async -> String {
        var info: [String: String] = [:]
        let version = MacOSVersion.current
        info["macOS"] = version.description

        #if arch(arm64)
        info["architecture"] = "arm64"
        #else
        info["architecture"] = "x86_64"
        #endif

        if let whiskyWineVersion = WhiskyWineInstaller.whiskyWineVersion() {
            info["whiskyWineVersion"] =
                "\(whiskyWineVersion.major).\(whiskyWineVersion.minor).\(whiskyWineVersion.patch)"
        }

        return dictionaryToJSON(info)
    }
}

// MARK: - DiagnosticExporter ZIP Building

extension DiagnosticExporter {
    @MainActor
    fileprivate static func buildZIPArchive(context: ZIPExportContext) async -> URL {
        let bottleName = sanitizeName(context.bottle.settings.name)
        let programName = sanitizeName(context.program.name)
        let dateString = formatDateForFilename(Date())
        let zipFilename = "Whisky-Diagnostics-\(bottleName)-\(programName)-\(dateString).zip"

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let contentDir = tempDir.appendingPathComponent(
            "Whisky-Diagnostics-\(bottleName)-\(programName)",
            isDirectory: true
        )
        let zipURL = tempDir.appendingPathComponent(zipFilename)

        let content = await prepareZIPContent(context: context)

        await Task.detached(priority: .utility) {
            writeZIPContent(content: content, contentDir: contentDir, context: context)
            compressZIP(from: contentDir, to: zipURL)
            try? FileManager.default.removeItem(at: contentDir)
        }.value

        return zipURL
    }

    @MainActor
    fileprivate static func prepareZIPContent(context: ZIPExportContext) async -> ZIPContent {
        await ZIPContent(
            reportMarkdown: generateReportMarkdown(
                diagnosis: context.diagnosis,
                bottle: context.bottle,
                program: context.program,
                options: context.options
            ),
            bottleSummary: bottleSettingsSummary(bottle: context.bottle),
            programSummary: programSettingsSummary(program: context.program),
            systemInfo: generateSystemInfoJSON(),
            environmentJSON: generateEnvironmentJSON(bottle: context.bottle, options: context.options)
        )
    }

    fileprivate static func writeZIPContent(content: ZIPContent, contentDir: URL, context: ZIPExportContext) {
        do {
            try FileManager.default.createDirectory(at: contentDir, withIntermediateDirectories: true)
            try content.reportMarkdown.write(
                to: contentDir.appendingPathComponent("report.md"),
                atomically: true,
                encoding: .utf8
            )

            let crashEncoder = JSONEncoder()
            crashEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            crashEncoder.dateEncodingStrategy = .iso8601
            let crashData = try crashEncoder.encode(CrashDiagnosisCodableWrapper(context.diagnosis))
            try crashData.write(to: contentDir.appendingPathComponent("crash.json"))

            try content.environmentJSON.write(
                to: contentDir.appendingPathComponent("env.json"),
                atomically: true,
                encoding: .utf8
            )
            try content.bottleSummary.write(
                to: contentDir.appendingPathComponent("bottle-settings.json"),
                atomically: true,
                encoding: .utf8
            )
            try content.programSummary.write(
                to: contentDir.appendingPathComponent("program-settings.json"),
                atomically: true,
                encoding: .utf8
            )

            writeLogFiles(contentDir: contentDir, context: context)

            try content.systemInfo.write(
                to: contentDir.appendingPathComponent("system.json"),
                atomically: true,
                encoding: .utf8
            )

            if context.options.includeRemediationHistory, let timeline = context.timeline {
                let timelineEncoder = JSONEncoder()
                timelineEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                timelineEncoder.dateEncodingStrategy = .iso8601
                let timelineData = try timelineEncoder.encode(timeline)
                try timelineData.write(to: contentDir.appendingPathComponent("remediation-history.json"))
            }
        } catch {
            // Best effort
        }
    }

    fileprivate static func writeLogFiles(contentDir: URL, context: ZIPExportContext) {
        guard let logURL = context.logFileURL else { return }

        if context.options.includeFullLog,
           FileManager.default.fileExists(atPath: logURL.path(percentEncoded: false)) {
            if let logContent = try? String(contentsOf: logURL, encoding: .utf8) {
                let redacted = context.options.includeSensitiveDetails ? logContent
                    : Redactor.redactLogText(logContent)
                try? redacted.write(
                    to: contentDir.appendingPathComponent("wine.log"),
                    atomically: true,
                    encoding: .utf8
                )
            }
        }

        let tailText = tailOfLogFile(logURL, lineCount: context.options.tailLineCount)
        let redactedTail = context.options.includeSensitiveDetails ? tailText
            : Redactor.redactLogText(tailText)
        try? redactedTail.write(
            to: contentDir.appendingPathComponent("wine.tail.log"),
            atomically: true,
            encoding: .utf8
        )
    }

    fileprivate static func compressZIP(from contentDir: URL, to zipURL: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [
            "-c",
            "-k",
            "--sequesterRsrc",
            contentDir.path(percentEncoded: false),
            zipURL.path(percentEncoded: false)
        ]
        try? process.run()
        process.waitUntilExit()
    }

    fileprivate struct ZIPExportContext {
        let diagnosis: CrashDiagnosis
        let bottle: Bottle
        let program: Program
        let logFileURL: URL?
        let timeline: RemediationTimeline?
        let options: ExportOptions
    }

    fileprivate struct ZIPContent {
        let reportMarkdown: String
        let bottleSummary: String
        let programSummary: String
        let systemInfo: String
        let environmentJSON: String
    }
}

// MARK: - DiagnosticExporter Helpers

extension DiagnosticExporter {
    /// Sanitizes a name for use in filenames by replacing non-alphanumeric characters with hyphens.
    static func sanitizeName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics
        return name.unicodeScalars
            .map { allowed.contains($0) ? String($0) : "-" }
            .joined()
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// Formats a date for use in filenames: YYYYMMDD-HHmmss.
    static func formatDateForFilename(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    /// Reads the tail of a log file with a configurable line count.
    static func tailOfLogFile(_ url: URL, lineCount: Int) -> String {
        let maxBytesToRead = 256 * 1_024
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }

            let end = try handle.seekToEnd()
            let start = end > UInt64(maxBytesToRead) ? end - UInt64(maxBytesToRead) : 0
            try handle.seek(toOffset: start)

            let data = try handle.readToEnd() ?? Data()
            guard var text = String(data: data, encoding: .utf8) else {
                return "(Log tail unavailable: not UTF-8)"
            }

            guard !text.isEmpty else {
                return "(Log tail unavailable: empty)"
            }

            // If we started from the middle, drop the first partial line
            if start != 0, let firstNewline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: firstNewline)...])
            }

            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            if lines.count <= lineCount {
                return lines.joined(separator: "\n")
            }
            return lines.suffix(lineCount).joined(separator: "\n")
        } catch {
            return "(Failed to read log tail: \(error.localizedDescription))"
        }
    }

    /// Converts a [String: String] dictionary to a pretty-printed JSON string.
    fileprivate static func dictionaryToJSON(_ dict: [String: String]) -> String {
        let sorted = dict.sorted { $0.key < $1.key }
        var json = "{\n"
        for (index, pair) in sorted.enumerated() {
            let escapedValue = pair.value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            json += "  \"\(pair.key)\": \"\(escapedValue)\""
            if index < sorted.count - 1 {
                json += ","
            }
            json += "\n"
        }
        json += "}"
        return json
    }
}

// MARK: - Codable Wrapper for CrashDiagnosis

/// Lightweight Codable wrapper for ``CrashDiagnosis`` to encode as JSON.
///
/// ``CrashDiagnosis`` itself contains non-Codable ``DiagnosisMatch`` entries,
/// so this wrapper encodes only the serializable portions.
struct CrashDiagnosisCodableWrapper: Codable, Sendable {
    let primaryCategory: String?
    let primaryConfidence: String?
    let headline: String?
    let exitCode: Int32?
    let categoryCounts: [String: Int]
    let matchCount: Int
    let applicableRemediationIds: [String]
    let topMatches: [MatchSummary]

    struct MatchSummary: Codable, Sendable {
        let patternId: String
        let category: String
        let confidence: Double
        let severity: String
        let lineIndex: Int
        let captures: [String]
    }

    init(_ diagnosis: CrashDiagnosis) {
        self.primaryCategory = diagnosis.primaryCategory?.rawValue
        self.primaryConfidence = diagnosis.primaryConfidence?.rawValue
        self.headline = diagnosis.headline
        self.exitCode = diagnosis.exitCode
        self.categoryCounts = Dictionary(
            uniqueKeysWithValues: diagnosis.categoryCounts.map { ($0.key.rawValue, $0.value) }
        )
        self.matchCount = diagnosis.matches.count
        self.applicableRemediationIds = diagnosis.applicableRemediationIds
        self.topMatches = diagnosis.matches.prefix(20).map { diagMatch in
            MatchSummary(
                patternId: diagMatch.pattern.id,
                category: diagMatch.pattern.category.rawValue,
                confidence: diagMatch.pattern.confidence,
                severity: diagMatch.pattern.severity.rawValue,
                lineIndex: diagMatch.lineIndex,
                captures: diagMatch.captures
            )
        }
    }
}

// swiftlint:enable file_length
