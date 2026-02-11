//
//  ProgramOverrides.swift
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

/// Per-program overrides for bottle settings. Each `nil` field means "inherit from bottle."
///
/// This type is stored as an optional field on ``ProgramSettings``. When all fields
/// are `nil`, the program uses the bottle's settings for everything. Individual fields
/// can be set to override specific bottle settings.
///
/// ## Example
///
/// ```swift
/// var overrides = ProgramOverrides()
/// overrides.dxvk = false       // Disable DXVK for this program
/// overrides.enhancedSync = .esync // Force ESync for this program
/// // All other settings inherited from bottle
/// ```
public struct ProgramOverrides: Codable, Equatable, Sendable {
    // MARK: - Graphics / DXVK

    /// The graphics backend for this program. `nil` inherits from bottle.
    public var graphicsBackend: GraphicsBackend?
    /// Whether DXVK is enabled. `nil` inherits from bottle.
    public var dxvk: Bool?
    /// Whether DXVK async shader compilation is enabled. `nil` inherits from bottle.
    public var dxvkAsync: Bool?
    /// The DXVK HUD display mode. `nil` inherits from bottle.
    public var dxvkHud: DXVKHUD?

    // MARK: - Sync

    /// The synchronization mode. `nil` inherits from bottle.
    public var enhancedSync: EnhancedSync?

    // MARK: - D3D

    /// Whether to force DirectX 11 mode. `nil` inherits from bottle.
    public var forceD3D11: Bool?

    // MARK: - Performance

    /// The performance optimization preset. `nil` inherits from bottle.
    public var performancePreset: PerformancePreset?
    /// Whether shader caching is enabled. `nil` inherits from bottle.
    public var shaderCacheEnabled: Bool?

    // MARK: - Input

    /// Whether controller compatibility mode is enabled. `nil` inherits from bottle.
    public var controllerCompatibilityMode: Bool?
    /// Whether to disable HIDAPI for joystick input. `nil` inherits from bottle.
    public var disableHIDAPI: Bool?
    /// Whether to allow joystick events when app is in background. `nil` inherits from bottle.
    public var allowBackgroundEvents: Bool?
    /// Whether to disable SDL to XInput mapping conversion. `nil` inherits from bottle.
    public var disableControllerMapping: Bool?
    /// Whether to use native button labels instead of XInput layout. `nil` inherits from bottle.
    public var useButtonLabels: Bool?

    // MARK: - DLL Overrides

    /// Program-specific DLL overrides. `nil` inherits from bottle.
    public var dllOverrides: [DLLOverrideEntry]?

    // MARK: - Winetricks Verb Tagging

    /// Winetricks verbs tagged as "used by this program" for user organization.
    ///
    /// This is metadata only -- it does not change which verbs are installed in the prefix.
    /// Verbs are installed at the bottle level; this field tracks which verbs the user
    /// considers relevant to this specific program.
    public var taggedVerbs: [String]?

    /// Returns `true` when all override fields are `nil`, meaning no overrides are active.
    ///
    /// Note: `taggedVerbs` is excluded from this check since it is organizational metadata,
    /// not a settings override.
    public var isEmpty: Bool {
        graphicsBackend == nil
            && dxvk == nil
            && dxvkAsync == nil
            && dxvkHud == nil
            && enhancedSync == nil
            && forceD3D11 == nil
            && performancePreset == nil
            && shaderCacheEnabled == nil
            && controllerCompatibilityMode == nil
            && disableHIDAPI == nil
            && allowBackgroundEvents == nil
            && disableControllerMapping == nil
            && useButtonLabels == nil
            && dllOverrides == nil
    }

    /// Creates a new ProgramOverrides with all fields set to `nil` (inherit everything).
    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.graphicsBackend = try container.decodeIfPresent(
            GraphicsBackend.self,
            forKey: .graphicsBackend
        )
        self.dxvk = try container.decodeIfPresent(Bool.self, forKey: .dxvk)
        self.dxvkAsync = try container.decodeIfPresent(Bool.self, forKey: .dxvkAsync)
        self.dxvkHud = try container.decodeIfPresent(DXVKHUD.self, forKey: .dxvkHud)
        self.enhancedSync = try container.decodeIfPresent(EnhancedSync.self, forKey: .enhancedSync)
        self.forceD3D11 = try container.decodeIfPresent(Bool.self, forKey: .forceD3D11)
        self.performancePreset = try container.decodeIfPresent(
            PerformancePreset.self,
            forKey: .performancePreset
        )
        self.shaderCacheEnabled = try container.decodeIfPresent(Bool.self, forKey: .shaderCacheEnabled)
        self.controllerCompatibilityMode = try container.decodeIfPresent(
            Bool.self,
            forKey: .controllerCompatibilityMode
        )
        self.disableHIDAPI = try container.decodeIfPresent(Bool.self, forKey: .disableHIDAPI)
        self.allowBackgroundEvents = try container.decodeIfPresent(
            Bool.self,
            forKey: .allowBackgroundEvents
        )
        self.disableControllerMapping = try container.decodeIfPresent(
            Bool.self,
            forKey: .disableControllerMapping
        )
        self.useButtonLabels = try container.decodeIfPresent(
            Bool.self,
            forKey: .useButtonLabels
        )
        self.dllOverrides = try container.decodeIfPresent(
            [DLLOverrideEntry].self,
            forKey: .dllOverrides
        )
        self.taggedVerbs = try container.decodeIfPresent(
            [String].self,
            forKey: .taggedVerbs
        )
    }
}
