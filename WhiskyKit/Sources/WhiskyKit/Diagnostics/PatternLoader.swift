//
//  PatternLoader.swift
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

/// Loads and validates crash pattern and remediation action definitions from JSON resources.
///
/// Pattern and remediation definitions are stored as versioned JSON files in the
/// SPM resource bundle. The loader validates structure at load time and fails
/// fast in debug builds.
public enum PatternLoader {
    // MARK: - JSON Schema Types

    private struct PatternFile: Codable {
        let version: Int
        let patterns: [CrashPattern]
    }

    private struct RemediationFile: Codable {
        let version: Int
        let actions: [RemediationAction]
    }

    // MARK: - Public API

    /// Loads crash patterns from a JSON file URL.
    ///
    /// - Parameter url: URL to a `patterns.json` file.
    /// - Returns: Array of crash patterns.
    /// - Throws: If the file cannot be read or decoded.
    public static func loadPatterns(from url: URL) throws -> [CrashPattern] {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let file = try decoder.decode(PatternFile.self, from: data)
        return file.patterns
    }

    /// Loads remediation actions from a JSON file URL.
    ///
    /// - Parameter url: URL to a `remediations.json` file.
    /// - Returns: Dictionary of remediation actions keyed by ID.
    /// - Throws: If the file cannot be read or decoded.
    public static func loadRemediations(from url: URL) throws -> [String: RemediationAction] {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let file = try decoder.decode(RemediationFile.self, from: data)
        return Dictionary(uniqueKeysWithValues: file.actions.map { ($0.id, $0) })
    }

    /// Loads default patterns and remediations from the SPM resource bundle.
    ///
    /// In debug builds, invalid JSON triggers `fatalError` to surface issues early.
    /// In release builds, returns empty collections on failure.
    ///
    /// - Returns: Tuple of patterns array and remediations dictionary.
    public static func loadDefaults() -> ([CrashPattern], [String: RemediationAction]) {
        guard let patternsURL = Bundle.module.url(
            forResource: "patterns",
            withExtension: "json"
        )
        else {
            return handleMissingResource("patterns.json")
        }

        guard let remediationsURL = Bundle.module.url(
            forResource: "remediations",
            withExtension: "json"
        )
        else {
            return handleMissingResource("remediations.json")
        }

        do {
            let patterns = try loadPatterns(from: patternsURL)
            let remediations = try loadRemediations(from: remediationsURL)
            return (patterns, remediations)
        } catch {
            #if DEBUG
            fatalError("Failed to load default crash patterns: \(error)")
            #else
            return ([], [:])
            #endif
        }
    }

    // MARK: - Private

    private static func handleMissingResource(_ name: String) -> ([CrashPattern], [String: RemediationAction]) {
        #if DEBUG
        fatalError("Missing resource: \(name) in Bundle.module")
        #else
        return ([], [:])
        #endif
    }
}
