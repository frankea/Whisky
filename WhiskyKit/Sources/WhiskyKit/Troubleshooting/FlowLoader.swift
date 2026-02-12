//
//  FlowLoader.swift
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
import os.log

/// Loads troubleshooting flow definitions from bundled JSON resources.
///
/// Follows the ``PatternLoader`` and ``GameDBLoader`` pattern: a caseless enum
/// with static methods for loading from URLs or from the default SPM resource bundle.
/// Flow definitions are split into an index, per-category flow files, and shared fragments.
///
/// In debug builds, missing or invalid resources trigger assertions to surface issues
/// early. In release builds, failures return nil or empty collections gracefully.
public enum FlowLoader {
    private static let logger = Logger(
        subsystem: "com.isaacmarovitz.Whisky",
        category: "FlowLoader"
    )

    // MARK: - Index Loading

    /// Loads the flow index from the SPM resource bundle.
    ///
    /// The index maps symptom categories to their flow definition files
    /// and provides metadata for the symptom picker UI.
    ///
    /// - Returns: The decoded flow index, or `nil` if loading fails.
    public static func loadIndex() -> FlowIndex? {
        guard let url = Bundle.module.url(forResource: "index", withExtension: "json") else {
            logger.error("Missing resource: index.json in Bundle.module")
            #if DEBUG
            assertionFailure("Missing resource: index.json in Bundle.module")
            #endif
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode(FlowIndex.self, from: data)
        } catch {
            logger.error("Failed to decode index.json: \(error.localizedDescription)")
            #if DEBUG
            assertionFailure("Failed to decode index.json: \(error)")
            #endif
            return nil
        }
    }

    // MARK: - Flow Loading

    /// Loads a single flow definition from the SPM resource bundle.
    ///
    /// Since SPM `.process()` flattens resource directories, the file name
    /// is used directly as the resource name (e.g., "launch-crash" for
    /// "launch-crash.json").
    ///
    /// - Parameter fileName: The JSON file name including extension (e.g., "launch-crash.json").
    /// - Returns: The decoded flow definition, or `nil` if loading fails.
    public static func loadFlow(fileName: String) -> FlowDefinition? {
        let resourceName = (fileName as NSString).deletingPathExtension
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "json") else {
            logger.error("Missing flow resource: \(fileName)")
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode(FlowDefinition.self, from: data)
        } catch {
            logger.error("Failed to decode flow \(fileName): \(error.localizedDescription)")
            #if DEBUG
            assertionFailure("Failed to decode flow \(fileName): \(error)")
            #endif
            return nil
        }
    }

    // MARK: - Bulk Loading

    /// Loads all flow definitions referenced in the index, keyed by category ID.
    ///
    /// Iterates through the index categories and loads each flow file.
    /// Flows that fail to load are skipped with a warning.
    ///
    /// - Returns: A dictionary of flow definitions keyed by category ID.
    public static func loadAllFlows() -> [String: FlowDefinition] {
        guard let index = loadIndex() else {
            return [:]
        }

        var flows: [String: FlowDefinition] = [:]
        for category in index.categories {
            if let flow = loadFlow(fileName: category.flowFile) {
                flows[category.id] = flow
            } else {
                logger.warning("Skipped flow for category \(category.id): failed to load \(category.flowFile)")
            }
        }

        logger.debug("Loaded \(flows.count) of \(index.categories.count) flow definitions")
        return flows
    }

    /// Loads all shared fragment flow definitions from the SPM resource bundle.
    ///
    /// Since SPM `.process()` flattens directories, fragment files are loaded
    /// by their resource names (e.g., "dependency-install", "export-escalation").
    ///
    /// - Returns: A dictionary of fragment definitions keyed by resource name.
    public static func loadFragments() -> [String: FlowDefinition] {
        let fragmentNames = ["dependency-install", "export-escalation"]
        var fragments: [String: FlowDefinition] = [:]

        for name in fragmentNames {
            guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
                logger.warning("Missing fragment resource: \(name).json")
                continue
            }

            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                let fragment = try decoder.decode(FlowDefinition.self, from: data)
                fragments[name] = fragment
            } catch {
                logger.error("Failed to decode fragment \(name): \(error.localizedDescription)")
                #if DEBUG
                assertionFailure("Failed to decode fragment \(name): \(error)")
                #endif
            }
        }

        logger.debug("Loaded \(fragments.count) fragment definitions")
        return fragments
    }
}
