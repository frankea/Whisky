//
//  BottleCleanupConfig.swift
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

/// Per-bottle policy for killing Wine processes on quit.
///
/// This allows individual bottles to override the global `killOnTerminate` behavior,
/// so users can set "always kill" for unstable bottles or "never kill" for bottles
/// running long-lived server processes.
public enum KillOnQuitPolicy: String, Codable, CaseIterable, Sendable {
    /// Use the global killOnTerminate setting (default)
    case inherit = "inherit"
    /// Always kill Wine processes when the bottle/app quits
    case alwaysKill = "always"
    /// Never kill Wine processes on quit
    case neverKill = "never"
}

/// Configuration settings for per-bottle cleanup and clipboard behavior.
///
/// This configuration section controls how clipboard content is handled before
/// launching Wine programs and how Wine processes are managed on quit.
///
/// ## Overview
///
/// Each bottle can independently configure:
/// - Clipboard checking policy (auto, always warn, always clear, never)
/// - Clipboard size threshold for "large" content detection
/// - Kill-on-quit behavior for Wine processes
///
/// ## Example
///
/// ```swift
/// var config = BottleCleanupConfig()
/// config.clipboardPolicy = .alwaysClear
/// config.killOnQuit = .alwaysKill
/// ```
public struct BottleCleanupConfig: Codable, Equatable {
    /// The clipboard handling policy for this bottle.
    var clipboardPolicy: ClipboardPolicy = .auto

    /// The size threshold in bytes for considering clipboard content "large".
    ///
    /// Content above this threshold triggers the configured clipboard policy.
    /// Defaults to ``ClipboardManager/largeContentThreshold`` (10 KB).
    var clipboardThreshold: Int = ClipboardManager.largeContentThreshold

    /// The kill-on-quit policy for Wine processes in this bottle.
    var killOnQuit: KillOnQuitPolicy = .inherit

    /// Creates a new BottleCleanupConfig with default values.
    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.clipboardPolicy = try container.decodeIfPresent(
            ClipboardPolicy.self,
            forKey: .clipboardPolicy
        ) ?? .auto
        self.clipboardThreshold = try container.decodeIfPresent(
            Int.self,
            forKey: .clipboardThreshold
        ) ?? ClipboardManager.largeContentThreshold
        self.killOnQuit = try container.decodeIfPresent(
            KillOnQuitPolicy.self,
            forKey: .killOnQuit
        ) ?? .inherit
    }
}
