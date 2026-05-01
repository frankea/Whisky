//
//  BottleGraphicsConfig.swift
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

/// The graphics translation backend for a Wine bottle.
///
/// Controls which Direct3D translation layer is used at launch time.
/// `.recommended` defers the choice to ``GraphicsBackendResolver`` which
/// selects the best concrete backend based on GPU and macOS heuristics.
public enum GraphicsBackend: String, Codable, CaseIterable, Equatable, Sendable {
    /// Let Whisky choose the best backend for the current system.
    case recommended
    /// Apple's Direct3D-to-Metal translation layer (Wine's built-in D3DMetal).
    case d3dMetal
    /// DXVK: Direct3D-to-Vulkan translation via MoltenVK.
    case dxvk
    /// Wine's built-in OpenGL-based Direct3D translation.
    case wined3d

    /// A human-readable display name for this backend.
    public var displayName: String {
        switch self {
        case .recommended:
            String(localized: "config.graphics.backend.recommended")
        case .d3dMetal:
            "D3DMetal"
        case .dxvk:
            "DXVK"
        case .wined3d:
            "WineD3D"
        }
    }

    /// A one-line summary suitable for selection cards or tooltips.
    public var summary: String {
        switch self {
        case .recommended:
            String(localized: "config.graphics.backend.recommended.summary")
        case .d3dMetal:
            String(localized: "config.graphics.backend.d3dMetal.summary")
        case .dxvk:
            String(localized: "config.graphics.backend.dxvk.summary")
        case .wined3d:
            String(localized: "config.graphics.backend.wined3d.summary")
        }
    }
}

/// Stores the graphics backend choice for a bottle.
///
/// This config is serialized alongside other bottle config groups in
/// ``BottleSettings``. The defensive `init(from:)` ensures unknown or
/// corrupt values decode gracefully to `.recommended`.
public struct BottleGraphicsConfig: Codable, Equatable {
    /// The selected graphics backend. Defaults to `.recommended`.
    var backend: GraphicsBackend = .recommended

    /// Creates a new graphics config with the default `.recommended` backend.
    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.backend = try container.decodeIfPresent(GraphicsBackend.self, forKey: .backend) ?? .recommended
    }
}
