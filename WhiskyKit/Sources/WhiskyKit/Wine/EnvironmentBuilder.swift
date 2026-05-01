//
//  EnvironmentBuilder.swift
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

/// A layer in the environment variable cascade.
///
/// Layers are ordered by priority: later layers (higher raw value) override
/// earlier layers when they set the same key. This provides a deterministic
/// resolution order for environment variables from multiple sources.
///
/// ## Layer Order
///
/// 1. ``base`` -- WINEPREFIX, default WINEDEBUG, PATH-related defaults
/// 2. ``platform`` -- macOS compatibility fixes
/// 3. ``bottleManaged`` -- Toggles/presets Whisky owns (DXVK, Metal, sync, performance)
/// 4. ``launcherManaged`` -- Launcher compatibility mode and detected overrides
/// 5. ``bottleUser`` -- User-defined bottle-level environment variables
/// 6. ``programUser`` -- Program settings environment variables and locale
/// 7. ``featureRuntime`` -- Launch-time feature injectors (ClickOnce, one-off modes)
/// 8. ``callsiteOverride`` -- Explicit overrides passed to `Wine.runProgram(environment:)`
public enum EnvironmentLayer: Int, CaseIterable, Comparable, Sendable, Hashable {
    case base = 0
    case platform
    case bottleManaged
    case launcherManaged
    case bottleUser
    case programUser
    case featureRuntime
    case callsiteOverride

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Tracks which layer set each environment variable in the resolved environment.
///
/// Provenance data enables the Environment Inspector (Phase 5) to show users
/// where each setting came from and what it overrode.
public struct EnvironmentProvenance: Sendable {
    /// A single provenance entry for one environment variable key.
    public struct Entry: Sendable {
        /// The environment variable key.
        public let key: String
        /// The resolved value.
        public let value: String
        /// The layer that provided the winning value.
        public let layer: EnvironmentLayer
        /// If this entry was overridden by a higher layer, that layer.
        /// `nil` for the winning entry.
        public let overriddenBy: EnvironmentLayer?
        /// Human-readable reason for this entry, if provided.
        ///
        /// Populated by callers using ``EnvironmentBuilder/set(_:_:layer:reason:)``
        /// to explain why a particular value was set. For example,
        /// "Fixes steamwebhelper CEF locale crashes" or "macOS >= 15.4".
        public let reason: String?
    }

    /// The winning provenance entry for each environment variable key.
    public let entries: [String: Entry]
    /// All layers that contributed at least one winning entry to the final environment.
    public let activeLayers: Set<EnvironmentLayer>
}

/// Builds the Wine environment by collecting entries from ordered layers.
///
/// `EnvironmentBuilder` accumulates environment variable entries across multiple
/// layers. When resolved, later layers win per-key, producing both the final
/// environment dictionary and provenance metadata for debugging.
///
/// ## Example
///
/// ```swift
/// var builder = EnvironmentBuilder()
/// builder.set("WINEPREFIX", bottlePath, layer: .base)
/// builder.set("DXVK_ASYNC", "1", layer: .bottleManaged)
/// builder.set("DXVK_ASYNC", "0", layer: .programUser)
/// let result = builder.resolve()
/// // result.environment["DXVK_ASYNC"] == "0" (programUser wins)
/// ```
public struct EnvironmentBuilder: Sendable {
    /// Per-layer storage of key-value entries.
    private var layers: [EnvironmentLayer: [String: String?]] = [:]

    /// Per-layer storage of reason strings, keyed by (layer, key).
    /// Only populated when callers provide a reason via ``set(_:_:layer:reason:)``.
    private var reasons: [EnvironmentLayer: [String: String]] = [:]

    /// Creates a new empty environment builder.
    public init() {}

    /// Sets an environment variable in the specified layer.
    ///
    /// - Parameters:
    ///   - key: The environment variable name.
    ///   - value: The value to set.
    ///   - layer: The layer that owns this entry.
    public mutating func set(_ key: String, _ value: String, layer: EnvironmentLayer) {
        layers[layer, default: [:]][key] = value
    }

    /// Sets an environment variable in the specified layer with a reason.
    ///
    /// The reason is carried through to the resolved provenance entry, enabling
    /// UI display of "Applied because: {reason}" for any environment variable.
    ///
    /// - Parameters:
    ///   - key: The environment variable name.
    ///   - value: The value to set.
    ///   - layer: The layer that owns this entry.
    ///   - reason: Human-readable explanation for why this value is set.
    public mutating func set(_ key: String, _ value: String, layer: EnvironmentLayer, reason: String?) {
        layers[layer, default: [:]][key] = value
        if let reason {
            reasons[layer, default: [:]][key] = reason
        }
    }

    /// Sets multiple environment variables in the specified layer.
    ///
    /// - Parameters:
    ///   - entries: A dictionary of key-value pairs to set.
    ///   - layer: The layer that owns these entries.
    public mutating func setAll(_ entries: [String: String], layer: EnvironmentLayer) {
        for (key, value) in entries {
            layers[layer, default: [:]][key] = value
        }
    }

    /// Marks an environment variable for removal in the specified layer.
    ///
    /// When resolved, this removal takes effect at the layer's priority.
    /// A higher layer can still set the key after removal.
    ///
    /// - Parameters:
    ///   - key: The environment variable name to remove.
    ///   - layer: The layer that requests removal.
    public mutating func remove(_ key: String, layer: EnvironmentLayer) {
        layers[layer, default: [:]][key] = nil as String?
    }

    /// Resolves all layers into a final environment dictionary and provenance.
    ///
    /// Layers are processed in order of their raw value (ascending). For each key,
    /// the last layer to set a value wins. Removals are treated as deletions that
    /// override earlier sets.
    ///
    /// - Returns: A tuple of the resolved environment and provenance metadata.
    public func resolve() -> (environment: [String: String], provenance: EnvironmentProvenance) {
        var finalEnv: [String: String] = [:]
        var winningLayer: [String: EnvironmentLayer] = [:]

        // Process layers in priority order (ascending rawValue)
        let sortedLayers = layers.keys.sorted()
        for layer in sortedLayers {
            guard let entries = layers[layer] else { continue }
            for (key, value) in entries {
                if let value {
                    finalEnv[key] = value
                    winningLayer[key] = layer
                } else {
                    // nil value means removal
                    finalEnv.removeValue(forKey: key)
                    winningLayer.removeValue(forKey: key)
                }
            }
        }

        // Build provenance entries
        var provenanceEntries: [String: EnvironmentProvenance.Entry] = [:]
        var activeLayers = Set<EnvironmentLayer>()

        for (key, value) in finalEnv {
            guard let layer = winningLayer[key] else { continue }
            let reason = reasons[layer]?[key]
            provenanceEntries[key] = EnvironmentProvenance.Entry(
                key: key,
                value: value,
                layer: layer,
                overriddenBy: nil,
                reason: reason
            )
            activeLayers.insert(layer)
        }

        let provenance = EnvironmentProvenance(
            entries: provenanceEntries,
            activeLayers: activeLayers
        )

        return (environment: finalEnv, provenance: provenance)
    }
}
