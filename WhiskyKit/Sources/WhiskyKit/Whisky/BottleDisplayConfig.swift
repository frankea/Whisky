//
//  BottleDisplayConfig.swift
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

/// A display resolution preset for Wine's virtual desktop.
///
/// Each case represents a common resolution or a dynamic option (match display, custom).
/// The raw values are strings for stable Codable serialization.
public enum ResolutionPreset: String, Codable, CaseIterable, Equatable, Sendable {
    /// 1280 x 720 (HD)
    case r1280x720
    /// 1600 x 900 (HD+)
    case r1600x900
    /// 1920 x 1080 (Full HD) -- default
    case r1920x1080
    /// 2560 x 1440 (QHD)
    case r2560x1440
    /// 3840 x 2160 (4K UHD)
    case r3840x2160
    /// Match the Mac's current display resolution
    case matchDisplay
    /// User-specified custom resolution
    case custom

    /// A human-readable label for this preset.
    public var label: String {
        switch self {
        case .r1280x720:
            "1280 x 720"
        case .r1600x900:
            "1600 x 900"
        case .r1920x1080:
            "1920 x 1080 (Default)"
        case .r2560x1440:
            "2560 x 1440"
        case .r3840x2160:
            "3840 x 2160"
        case .matchDisplay:
            "Match Mac Display"
        case .custom:
            "Custom"
        }
    }

    /// The pixel dimensions for this preset, or `nil` for dynamic presets.
    ///
    /// Returns `nil` for `.matchDisplay` (resolved at runtime from the screen)
    /// and `.custom` (uses user-provided width/height).
    public var dimensions: (width: Int, height: Int)? {
        switch self {
        case .r1280x720:
            (width: 1_280, height: 720)
        case .r1600x900:
            (width: 1_600, height: 900)
        case .r1920x1080:
            (width: 1_920, height: 1_080)
        case .r2560x1440:
            (width: 2_560, height: 1_440)
        case .r3840x2160:
            (width: 3_840, height: 2_160)
        case .matchDisplay, .custom:
            nil
        }
    }
}

/// Stores the display/virtual desktop configuration for a bottle.
///
/// This config is serialized alongside other bottle config groups in
/// ``BottleSettings``. The defensive `init(from:)` ensures unknown or
/// corrupt values decode gracefully to defaults.
public struct BottleDisplayConfig: Codable, Equatable {
    /// Whether Wine's virtual desktop mode is enabled.
    var virtualDesktopEnabled: Bool = false

    /// The selected resolution preset. Defaults to `.r1920x1080`.
    var resolutionPreset: ResolutionPreset = .r1920x1080

    /// The custom resolution width in pixels.
    var customWidth: Int = 1_920

    /// The custom resolution height in pixels.
    var customHeight: Int = 1_080

    /// Creates a new display config with default values.
    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.virtualDesktopEnabled = try container.decodeIfPresent(
            Bool.self, forKey: .virtualDesktopEnabled
        ) ?? false
        self.resolutionPreset = try container.decodeIfPresent(
            ResolutionPreset.self, forKey: .resolutionPreset
        ) ?? .r1920x1080
        self.customWidth = try container.decodeIfPresent(
            Int.self, forKey: .customWidth
        ) ?? 1_920
        self.customHeight = try container.decodeIfPresent(
            Int.self, forKey: .customHeight
        ) ?? 1_080
    }

    /// The resolved pixel dimensions based on the current preset and custom values.
    ///
    /// For named presets, returns the preset's fixed dimensions.
    /// For `.matchDisplay`, returns (1920, 1080) as a fallback; the actual
    /// screen resolution query happens in the app layer.
    /// For `.custom`, returns the user-provided width and height.
    public var effectiveResolution: (width: Int, height: Int) {
        switch resolutionPreset {
        case .matchDisplay:
            (width: 1_920, height: 1_080)
        case .custom:
            (width: customWidth, height: customHeight)
        default:
            resolutionPreset.dimensions ?? (width: 1_920, height: 1_080)
        }
    }
}
