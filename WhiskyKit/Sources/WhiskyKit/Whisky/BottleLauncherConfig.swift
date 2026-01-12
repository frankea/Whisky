//
//  BottleLauncherConfig.swift
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

/// Configuration settings for game launcher compatibility.
///
/// This configuration section addresses Issue #41 and related upstream issues
/// with Steam, Rockstar Games Launcher, EA App, Epic Games, and other platforms.
///
/// ## Overview
///
/// Game launchers have specific requirements for locale settings, GPU detection,
/// and network configuration. This system provides both automatic detection and
/// manual override capabilities.
///
/// ## Dual-Mode System
///
/// 1. **Auto-Detection Mode** (`launcherMode == .auto`):
///    - Automatically detects launcher type when programs run
///    - Applies optimized settings based on executable name/path
///
/// 2. **Manual Override Mode** (`launcherMode == .manual`):
///    - User explicitly selects launcher type
///    - Forces specific configuration regardless of program
///
/// ## Example
///
/// ```swift
/// var config = BottleLauncherConfig()
/// config.compatibilityMode = true
/// config.launcherMode = .manual
/// config.detectedLauncher = .steam
/// ```
public struct BottleLauncherConfig: Codable, Equatable {
    /// Whether launcher compatibility mode is enabled.
    ///
    /// When enabled, the system applies launcher-specific optimizations
    /// based on either auto-detection or manual selection.
    var compatibilityMode: Bool = false

    /// The launcher detection mode (auto or manual).
    var launcherMode: LauncherMode = .auto

    /// Manually selected launcher type (used when `launcherMode` is `.manual`).
    var detectedLauncher: LauncherType?

    /// Locale override for launcher compatibility.
    ///
    /// Most launchers (Steam, EA App, Epic) work best with `en_US.UTF-8`
    /// to avoid steamwebhelper crashes and date/time parsing issues.
    var launcherLocale: Locales = .auto

    /// Whether to enable GPU spoofing for launcher compatibility checks.
    ///
    /// Helps launchers pass "GPU not supported" checks by reporting
    /// high-end NVIDIA GPU capabilities.
    var gpuSpoofing: Bool = true

    /// GPU vendor to spoof when `gpuSpoofing` is enabled.
    var gpuVendor: GPUVendor = .nvidia

    /// Network timeout in milliseconds for launcher downloads.
    ///
    /// Addresses Steam download stalls at 99% and connection timeouts.
    /// Default: 60000ms (60 seconds)
    var networkTimeout: Int = 60000

    /// Whether to automatically apply DXVK when launcher requires it.
    ///
    /// Some launchers (Rockstar) will not render UI without DXVK.
    var autoEnableDXVK: Bool = true

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.compatibilityMode = try container.decodeIfPresent(Bool.self, forKey: .compatibilityMode) ?? false
        self.launcherMode = try container.decodeIfPresent(LauncherMode.self, forKey: .launcherMode) ?? .auto
        self.detectedLauncher = try container.decodeIfPresent(LauncherType.self, forKey: .detectedLauncher)
        self.launcherLocale = try container.decodeIfPresent(Locales.self, forKey: .launcherLocale) ?? .auto
        self.gpuSpoofing = try container.decodeIfPresent(Bool.self, forKey: .gpuSpoofing) ?? true
        self.gpuVendor = try container.decodeIfPresent(GPUVendor.self, forKey: .gpuVendor) ?? .nvidia
        self.networkTimeout = try container.decodeIfPresent(Int.self, forKey: .networkTimeout) ?? 60000
        self.autoEnableDXVK = try container.decodeIfPresent(Bool.self, forKey: .autoEnableDXVK) ?? true
    }
}

/// Launcher detection mode for dual-mode configuration system.
public enum LauncherMode: String, Codable, CaseIterable, Sendable {
    /// Automatically detect launcher type from executable path/name
    case auto = "auto"
    /// Use manually specified launcher type
    case manual = "manual"
}
