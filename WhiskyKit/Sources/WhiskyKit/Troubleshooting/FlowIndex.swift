//
//  FlowIndex.swift
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

/// The top-level index of all available troubleshooting flow categories.
///
/// Decoded from `index.json` in the troubleshooting resources bundle.
/// Each entry maps to a separate flow definition JSON file.
public struct FlowIndex: Codable, Sendable {
    /// Schema version for forward-compatible decoding.
    public let version: Int

    /// Available troubleshooting categories in display order.
    public let categories: [FlowCategoryEntry]

    public init(version: Int, categories: [FlowCategoryEntry]) {
        self.version = version
        self.categories = categories
    }
}

/// Metadata for a single troubleshooting flow category.
///
/// Used by the symptom picker to display available categories
/// and by the flow loader to locate the corresponding JSON file.
public struct FlowCategoryEntry: Codable, Sendable, Identifiable {
    /// Stable identifier matching the flow file's ``FlowDefinition/categoryId``.
    public let id: String

    /// User-facing title for the symptom picker.
    public let title: String

    /// SF Symbol name for the category icon.
    public let sfSymbol: String

    /// File name of the flow definition JSON (e.g., "launch-crash.json").
    public let flowFile: String

    /// Whether this category has a deep or shallow flow.
    public let depth: FlowDepth

    /// Short description of what this category covers.
    public let description: String

    public init(
        id: String,
        title: String,
        sfSymbol: String,
        flowFile: String,
        depth: FlowDepth,
        description: String
    ) {
        self.id = id
        self.title = title
        self.sfSymbol = sfSymbol
        self.flowFile = flowFile
        self.depth = depth
        self.description = description
    }
}

/// Indicates the depth of a troubleshooting flow.
///
/// Deep flows have extensive branching with many automated checks and fixes.
/// Shallow flows perform basic triage before escalating to diagnostics.
public enum FlowDepth: String, Codable, Sendable {
    /// Extensive flow with multiple automated checks and fix branches.
    case deep
    /// Basic triage flow that escalates earlier to diagnostics or export.
    case shallow
}
