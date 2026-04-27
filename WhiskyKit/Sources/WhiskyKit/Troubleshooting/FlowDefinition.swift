//
//  FlowDefinition.swift
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

/// A complete troubleshooting flow loaded from a JSON resource file.
///
/// Each flow file corresponds to a single symptom category and contains
/// a graph of step nodes the engine traverses. The ``entryNodeId`` identifies
/// the first node to evaluate when the flow begins.
public struct FlowDefinition: Codable, Sendable {
    /// Schema version for forward-compatible decoding.
    public let version: Int

    /// Identifier of the symptom category this flow covers.
    public let categoryId: String

    /// Graph of step nodes keyed by node ID.
    public let nodes: [String: FlowStepNode]

    /// The node ID where execution begins.
    public let entryNodeId: String

    public init(version: Int, categoryId: String, nodes: [String: FlowStepNode], entryNodeId: String) {
        self.version = version
        self.categoryId = categoryId
        self.nodes = nodes
        self.entryNodeId = entryNodeId
    }
}

/// A single step in a troubleshooting flow graph.
///
/// Nodes represent checks, fixes, informational steps, verification gates,
/// or branch points. The ``on`` dictionary maps normalized outcomes to the
/// next node ID, enabling data-driven branching without hardcoded logic.
public struct FlowStepNode: Codable, Sendable, Identifiable {
    /// Unique identifier within the flow.
    public let id: String

    /// What kind of step this node represents.
    public let type: NodeType

    /// Which wizard phase this step belongs to.
    public let phase: FlowPhase

    /// Short title displayed in the step card header.
    public let title: String?

    /// Longer explanation displayed in the step card body.
    public let description: String?

    /// Stable check identifier for ``TroubleshootingCheck`` lookup.
    public let checkId: String?

    /// Parameters passed to the check implementation.
    public let params: [String: String]?

    /// Outcome-to-next-node-ID branching map.
    public let on: [String: String]? // swiftlint:disable:this identifier_name

    /// Maps evidence keys to user-facing labels for UI display.
    public let evidenceMap: [String: String]?

    /// Stable fix identifier for fix application.
    public let fixId: String?

    /// Diff-style preview data for fix steps.
    public let fixPreview: FixPreviewData?

    /// Whether this fix can be undone after application.
    public let isReversible: Bool?

    /// Whether an extra confirmation dialog is shown before applying.
    public let requiresConfirmation: Bool?

    /// Reference to a shared fragment flow for delegation.
    public let fragmentRef: String?

    public init(
        id: String,
        type: NodeType,
        phase: FlowPhase,
        title: String? = nil,
        description: String? = nil,
        checkId: String? = nil,
        params: [String: String]? = nil,
        on: [String: String]? = nil, // swiftlint:disable:this identifier_name
        evidenceMap: [String: String]? = nil,
        fixId: String? = nil,
        fixPreview: FixPreviewData? = nil,
        isReversible: Bool? = nil,
        requiresConfirmation: Bool? = nil,
        fragmentRef: String? = nil
    ) {
        self.id = id
        self.type = type
        self.phase = phase
        self.title = title
        self.description = description
        self.checkId = checkId
        self.params = params
        self.on = on
        self.evidenceMap = evidenceMap
        self.fixId = fixId
        self.fixPreview = fixPreview
        self.isReversible = isReversible
        self.requiresConfirmation = requiresConfirmation
        self.fragmentRef = fragmentRef
    }

    // MARK: - Defensive Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(NodeType.self, forKey: .type)
        phase = try container.decode(FlowPhase.self, forKey: .phase)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        checkId = try container.decodeIfPresent(String.self, forKey: .checkId)
        params = try container.decodeIfPresent([String: String].self, forKey: .params)
        on = try container.decodeIfPresent([String: String].self, forKey: .on)
        evidenceMap = try container.decodeIfPresent([String: String].self, forKey: .evidenceMap)
        fixId = try container.decodeIfPresent(String.self, forKey: .fixId)
        fixPreview = try container.decodeIfPresent(FixPreviewData.self, forKey: .fixPreview)
        isReversible = try container.decodeIfPresent(Bool.self, forKey: .isReversible)
        requiresConfirmation = try container.decodeIfPresent(Bool.self, forKey: .requiresConfirmation)
        fragmentRef = try container.decodeIfPresent(String.self, forKey: .fragmentRef)
    }
}

/// The kind of action a flow step node represents.
public enum NodeType: String, Codable, Sendable {
    /// Runs an automated check via the check registry.
    case check
    /// Applies a fix with preview and confirmation.
    case fix
    /// Displays informational content to the user.
    case info
    /// Asks the user whether the problem is resolved.
    case verify
    /// A decision point that branches based on user input.
    case branch
}

/// The wizard phase a flow step belongs to.
public enum FlowPhase: String, Codable, Sendable {
    /// Symptom selection phase.
    case symptom
    /// Automated checks phase.
    case checks
    /// Fix application phase.
    case fix
    /// Post-fix verification phase.
    case verify
    /// Export and escalation phase.
    case export
}

/// Preview data for a fix step showing what will change.
///
/// Displayed in a diff-style card so users can see the exact
/// setting modification before confirming the fix.
public struct FixPreviewData: Codable, Sendable {
    /// The human-readable name of the setting being changed.
    public let settingName: String

    /// Evidence key whose value shows the current setting value.
    public let currentValueKey: String?

    /// The new value that will be applied.
    public let newValue: String

    /// Whether the change applies at bottle or program scope.
    public let scope: String

    public init(settingName: String, currentValueKey: String? = nil, newValue: String, scope: String) {
        self.settingName = settingName
        self.currentValueKey = currentValueKey
        self.newValue = newValue
        self.scope = scope
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        settingName = try container.decode(String.self, forKey: .settingName)
        currentValueKey = try container.decodeIfPresent(String.self, forKey: .currentValueKey)
        newValue = try container.decode(String.self, forKey: .newValue)
        scope = try container.decode(String.self, forKey: .scope)
    }
}
