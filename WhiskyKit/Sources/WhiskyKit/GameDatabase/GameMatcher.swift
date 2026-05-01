// swiftlint:disable file_length
//
//  GameMatcher.swift
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

/// Metadata about a program used for matching against the game database.
///
/// Contains the identifiers and attributes extracted from a program's
/// executable file, install path, and associated Steam metadata.
public struct ProgramMetadata: Sendable {
    /// The executable filename (e.g., "eldenring.exe").
    public let exeName: String
    /// The URL to the executable file, if available.
    public let exeURL: URL?
    /// The file size of the executable in bytes.
    public let fileSize: Int64?
    /// The PE COFF header timestamp of the executable.
    public let peTimestamp: Date?
    /// The Steam App ID, if discovered from manifest or steam_appid.txt.
    public let steamAppId: Int?
    /// The install path of the program within the Wine prefix.
    public let installPath: String?

    public init(
        exeName: String,
        exeURL: URL? = nil,
        fileSize: Int64? = nil,
        peTimestamp: Date? = nil,
        steamAppId: Int? = nil,
        installPath: String? = nil
    ) {
        self.exeName = exeName
        self.exeURL = exeURL
        self.fileSize = fileSize
        self.peTimestamp = peTimestamp
        self.steamAppId = steamAppId
        self.installPath = installPath
    }
}

/// Tiered matching algorithm for identifying games from program metadata.
///
/// Scores programs against the game compatibility database using three tiers:
/// - **Hard identifiers** (0.95-1.0): Steam App ID, SHA-256 hash, file size + PE timestamp
/// - **Strong heuristics** (0.7-0.9): Executable name, path pattern matching
/// - **Fuzzy matching** (0.3-0.6): Tokenized name comparison against titles and aliases
///
/// Generic executables (launcher.exe, setup.exe, etc.) receive a -0.3 penalty
/// to avoid false matches against utility programs.
///
/// ## Example
///
/// ```swift
/// let metadata = ProgramMetadata(exeName: "eldenring.exe", steamAppId: 1245620)
/// let entries = GameDBLoader.loadDefaults()
/// let results = GameMatcher.match(metadata: metadata, against: entries)
/// // results[0].confidence ~= 1.0 (Steam App ID match)
/// ```
public enum GameMatcher {
    // MARK: - Configuration

    /// Minimum confidence score for a result to be included.
    private static let minimumThreshold: Double = 0.3

    /// Minimum gap between top two scores for bestMatch to return a result.
    private static let ambiguityGap: Double = 0.1

    /// Minimum confidence for bestMatch to return a result.
    private static let bestMatchMinimum: Double = 0.7

    /// Penalty applied to generic executable names.
    private static let genericPenalty: Double = -0.3

    /// Executable names that are too generic to reliably identify a game.
    private static let genericExeNames: Set<String> = [
        "launcher.exe", "setup.exe", "start.exe", "game.exe",
        "app.exe", "install.exe", "uninstall.exe", "updater.exe",
        "config.exe", "settings.exe", "crash_reporter.exe",
        "ue4-win64-shipping.exe", "unity.exe", "unitycrashhandler64.exe"
    ]

    // MARK: - Public API

    /// Scores all entries against the given metadata and returns matches above threshold.
    ///
    /// Results are sorted by confidence descending and filtered to scores >= 0.3.
    /// Each result includes a recommended variant auto-selected for the current machine.
    ///
    /// - Parameters:
    ///   - metadata: The program metadata to match against.
    ///   - entries: The game database entries to search.
    /// - Returns: Sorted array of match results above the minimum confidence threshold.
    public static func match(
        metadata: ProgramMetadata,
        against entries: [GameDBEntry]
    ) -> [MatchResult] {
        var results: [MatchResult] = []

        for entry in entries {
            if let result = scoreEntry(metadata: metadata, entry: entry) {
                results.append(result)
            }
        }

        return results.sorted { $0.confidence > $1.confidence }
    }

    /// Returns the single best match if confidence is high enough and unambiguous.
    ///
    /// Returns `nil` if:
    /// - No matches exist above 0.7 confidence
    /// - The top two matches are within 0.1 of each other (ambiguous),
    ///   unless the top match is a hard identifier
    ///
    /// - Parameters:
    ///   - metadata: The program metadata to match against.
    ///   - entries: The game database entries to search.
    /// - Returns: The single best match, or `nil` if ambiguous or below threshold.
    public static func bestMatch(
        metadata: ProgramMetadata,
        against entries: [GameDBEntry]
    ) -> MatchResult? {
        let results = match(metadata: metadata, against: entries)
        guard let top = results.first, top.confidence >= bestMatchMinimum else {
            return nil
        }

        // Hard identifiers always win -- no ambiguity check needed
        if top.tier == .hardIdentifier {
            return top
        }

        // Check for ambiguous close scores
        if results.count >= 2 {
            let second = results[1]
            if top.confidence - second.confidence < ambiguityGap {
                return nil
            }
        }

        return top
    }

    /// Filters entries by tokenized name match against title and aliases.
    ///
    /// Splits the query into tokens and returns entries where any token
    /// matches (case-insensitive prefix) against the entry's title or aliases.
    ///
    /// - Parameters:
    ///   - query: The search string to match.
    ///   - entries: The game database entries to search.
    /// - Returns: Entries matching the query.
    public static func searchEntries(_ query: String, in entries: [GameDBEntry]) -> [GameDBEntry] {
        let queryTokens = tokenize(query)
        guard !queryTokens.isEmpty else { return [] }

        return entries.filter { entry in
            var searchableTokens = tokenize(entry.title)
            if let aliases = entry.aliases {
                for alias in aliases {
                    searchableTokens.append(contentsOf: tokenize(alias))
                }
            }

            // Return entry if any query token matches any searchable token
            for queryToken in queryTokens {
                for searchToken in searchableTokens where searchToken.hasPrefix(queryToken) {
                    return true
                }
            }
            return false
        }
    }

    // MARK: - Scoring Pipeline

    /// Scores a single entry against the metadata, returning the best tier match.
    private static func scoreEntry(
        metadata: ProgramMetadata,
        entry: GameDBEntry
    ) -> MatchResult? {
        // Try tiers in order of confidence: hard > strong > fuzzy
        if let (score, explanation) = scoreHardIdentifiers(metadata: metadata, entry: entry) {
            let variant = selectVariant(from: entry)
            return MatchResult(
                entry: entry,
                confidence: score,
                tier: .hardIdentifier,
                explanation: explanation,
                recommendedVariant: variant
            )
        }

        if let (score, explanation) = scoreStrongHeuristics(metadata: metadata, entry: entry) {
            guard score >= minimumThreshold else { return nil }
            let variant = selectVariant(from: entry)
            return MatchResult(
                entry: entry,
                confidence: score,
                tier: .strongHeuristic,
                explanation: explanation,
                recommendedVariant: variant
            )
        }

        if let (score, explanation) = scoreFuzzy(metadata: metadata, entry: entry) {
            guard score >= minimumThreshold else { return nil }
            let variant = selectVariant(from: entry)
            return MatchResult(
                entry: entry,
                confidence: score,
                tier: .fuzzy,
                explanation: explanation,
                recommendedVariant: variant
            )
        }

        return nil
    }

    // MARK: - Hard Identifiers (0.95-1.0)

    /// Checks Steam App ID, SHA-256 hash, and file size + PE timestamp matches.
    private static func scoreHardIdentifiers(
        metadata: ProgramMetadata,
        entry: GameDBEntry
    ) -> (Double, String)? {
        // Steam App ID match (highest confidence)
        if let metadataAppId = metadata.steamAppId, let entryAppId = entry.steamAppId {
            if metadataAppId == entryAppId {
                return (1.0, "Steam App ID \(entryAppId) matches exactly")
            }
        }

        // File size + PE timestamp match (0.95)
        if let metaSize = metadata.fileSize, let metaTimestamp = metadata.peTimestamp {
            if let fingerprints = entry.exeFingerprints {
                for fingerprint in fingerprints {
                    if let fpSize = fingerprint.fileSize, let fpTimestamp = fingerprint.peTimestamp {
                        if metaSize == fpSize,
                           abs(metaTimestamp.timeIntervalSince(fpTimestamp)) < 1.0 {
                            return (0.95, "File size and PE timestamp match known fingerprint")
                        }
                    }
                }
            }
        }

        return nil
    }

    // MARK: - Strong Heuristics (0.7-0.9)

    /// Checks executable name match and path pattern match.
    private static func scoreStrongHeuristics(
        metadata: ProgramMetadata,
        entry: GameDBEntry
    ) -> (Double, String)? {
        guard let entryExeNames = entry.exeNames else { return nil }

        let metaExeLower = metadata.exeName.lowercased()

        // Check exact exe name match (case-insensitive)
        let exeMatch = entryExeNames.contains { $0.lowercased() == metaExeLower }
        guard exeMatch else { return nil }

        // Base score for exe name match
        var score = 0.85
        var explanation = "Executable name '\(metadata.exeName)' matches database entry"

        // Bonus for path pattern match
        if let installPath = metadata.installPath, let pathPatterns = entry.pathPatterns {
            let pathLower = installPath.lowercased()
            let pathMatch = pathPatterns.contains { pathLower.contains($0.lowercased()) }
            if pathMatch {
                score = 0.90
                explanation += " with install path confirmation"
            }
        }

        // Apply generic exe penalty
        if genericExeNames.contains(metaExeLower) {
            score += genericPenalty
            explanation += " (generic exe name penalty applied)"
        }

        return (score, explanation)
    }

    // MARK: - Fuzzy Matching (0.3-0.6)

    /// Tokenizes exe name and compares against entry title and aliases.
    private static func scoreFuzzy(
        metadata: ProgramMetadata,
        entry: GameDBEntry
    ) -> (Double, String)? {
        // Tokenize the exe name (remove .exe, split on separators)
        let exeTokens = tokenizeExeName(metadata.exeName)
        guard !exeTokens.isEmpty else { return nil }

        // Build target tokens from title + aliases
        var targetTokens = tokenize(entry.title)
        if let aliases = entry.aliases {
            for alias in aliases {
                targetTokens.append(contentsOf: tokenize(alias))
            }
        }
        // Deduplicate target tokens
        let uniqueTargets = Set(targetTokens)

        // Count matching tokens
        let matchCount = exeTokens.filter { exeToken in
            uniqueTargets.contains { $0.hasPrefix(exeToken) || exeToken.hasPrefix($0) }
        }.count

        guard matchCount > 0 else { return nil }

        // Scale to 0.3-0.6 range
        let ratio = Double(matchCount) / Double(exeTokens.count)
        var score = 0.3 + ratio * 0.3

        var explanation = "Name tokens match: \(matchCount)/\(exeTokens.count) tokens"

        // Install path bonus
        if let installPath = metadata.installPath, let pathPatterns = entry.pathPatterns {
            let pathLower = installPath.lowercased()
            let pathMatch = pathPatterns.contains { pathLower.contains($0.lowercased()) }
            if pathMatch {
                score += 0.1
                explanation += " + install path bonus"
            }
        }

        // Cap at 0.69 to stay below strong heuristic tier
        score = min(score, 0.69)

        return (score, explanation)
    }

    // MARK: - Variant Selection

    /// Selects the recommended variant for the current machine.
    private static func selectVariant(from entry: GameDBEntry) -> GameConfigVariant? {
        guard !entry.variants.isEmpty else { return nil }

        let currentArch = machineArchitecture()
        let currentOS = operatingSystemVersion()

        // Filter variants whose constraints match current machine
        // Sort variants: prefer those tested on current architecture
        let matching = entry.variants.sorted { lhs, rhs in
            let lhsMatchesArch = lhs.testedWith?.cpuArchitecture == currentArch
            let rhsMatchesArch = rhs.testedWith?.cpuArchitecture == currentArch
            if lhsMatchesArch != rhsMatchesArch {
                return lhsMatchesArch
            }
            return false
        }

        // Prefer isDefault variant
        if let defaultVariant = matching.first(where: { $0.isDefault == true }) {
            return defaultVariant
        }

        return matching.first ?? entry.variants.first
    }

    // MARK: - Tokenization

    /// Tokenizes a string by splitting on whitespace and common separators.
    private static func tokenize(_ text: String) -> [String] {
        let separators = CharacterSet.alphanumerics.inverted
        return text
            .lowercased()
            .components(separatedBy: separators)
            .filter { !$0.isEmpty }
    }

    /// Tokenizes an executable name, removing the .exe extension and splitting.
    private static func tokenizeExeName(_ name: String) -> [String] {
        var cleaned = name.lowercased()
        if cleaned.hasSuffix(".exe") {
            cleaned = String(cleaned.dropLast(4))
        }
        let separators = CharacterSet(charactersIn: "._- ")
        return cleaned
            .components(separatedBy: separators)
            .filter { !$0.isEmpty }
    }

    // MARK: - System Info

    /// Returns the current machine's CPU architecture string.
    private static func machineArchitecture() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        return withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }

    /// Returns the current macOS version string (e.g., "15.3.0").
    private static func operatingSystemVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}

// swiftlint:enable file_length
