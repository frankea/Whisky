//
//  BottleInputConfig.swift
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

/// Configuration settings for game controller and input device compatibility.
///
/// This configuration section addresses frankea/Whisky#42 (tracking issue) and
/// ~30 related upstream issues with controller detection, mapping, and functionality.
///
/// ## Overview
///
/// Game controllers often have issues on macOS with Wine due to:
/// - HIDAPI vs evdev backend differences
/// - SDL to XInput mapping conversion
/// - Third-party controller compatibility
///
/// ## Key Settings
///
/// - **Controller Compatibility Mode**: Enables workarounds for detection issues
/// - **Disable HIDAPI**: Forces SDL to use alternative input backend
/// - **Allow Background Events**: Lets controllers work when app loses focus
///
/// ## Example
///
/// ```swift
/// var config = BottleInputConfig()
/// config.controllerCompatibilityMode = true
/// config.disableHIDAPI = true
/// ```
public struct BottleInputConfig: Codable, Equatable {
    /// Whether controller compatibility mode is enabled.
    ///
    /// When enabled, applies workarounds for common controller detection
    /// and mapping issues on macOS.
    var controllerCompatibilityMode: Bool = false

    /// Whether to disable HIDAPI for joystick input.
    ///
    /// Setting `SDL_JOYSTICK_HIDAPI=0` forces SDL to use alternative backends
    /// which may improve detection for some controllers.
    /// See: https://wiki.libsdl.org/SDL2/CategoryHints (applies to both SDL2 and SDL3)
    var disableHIDAPI: Bool = false

    /// Whether to allow joystick events when the app is in background.
    ///
    /// Setting `SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1` enables controller
    /// input even when Wine/game window doesn't have focus.
    var allowBackgroundEvents: Bool = false

    /// Whether to disable SDL to XInput mapping conversion.
    ///
    /// Some controllers (PlayStation, Switch) show wrong button mappings
    /// because SDL converts them to XInput format. Disabling this may
    /// preserve native button layouts.
    var disableControllerMapping: Bool = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.controllerCompatibilityMode = try container.decodeIfPresent(
            Bool.self,
            forKey: .controllerCompatibilityMode
        ) ?? false
        self.disableHIDAPI = try container.decodeIfPresent(Bool.self, forKey: .disableHIDAPI) ?? false
        self.allowBackgroundEvents = try container.decodeIfPresent(
            Bool.self,
            forKey: .allowBackgroundEvents
        ) ?? false
        self.disableControllerMapping = try container.decodeIfPresent(
            Bool.self,
            forKey: .disableControllerMapping
        ) ?? false
    }
}
