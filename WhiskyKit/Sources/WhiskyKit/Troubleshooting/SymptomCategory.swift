//
//  SymptomCategory.swift
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

/// The top-level symptom categories a user can select when starting troubleshooting.
///
/// Each category maps to a JSON flow definition file that drives the troubleshooting
/// engine. The 8 named categories cover all common Wine issue types. An ``other``
/// fallback is available for issues that do not fit neatly into a specific category.
public enum SymptomCategory: String, CaseIterable, Codable, Sendable {
    /// Program fails to start or crashes within seconds of launching.
    case launchCrash

    /// Problems with Steam, EA App, Epic Games, or Rockstar launchers.
    case launcherIssues

    /// Black screen, flickering, visual artifacts, or low frame rate.
    case graphics

    /// No sound, crackling, popping, or wrong output device.
    case audio

    /// Controller not detected or buttons mapped incorrectly.
    case controllerInput

    /// Missing .NET, VC++, DirectX, or Winetricks components.
    case installDependencies

    /// Download timeouts, Steam stalls, or connection failures.
    case networkDownload

    /// Stuttering, frame drops, or hangs after playing for a while.
    case performanceStability

    /// Issues that do not fit into a specific category.
    case other

    /// The JSON flow definition file name for this category.
    public var flowFileName: String {
        switch self {
        case .launchCrash: "launch-crash.json"
        case .launcherIssues: "launcher-issues.json"
        case .graphics: "graphics.json"
        case .audio: "audio.json"
        case .controllerInput: "controller-input.json"
        case .installDependencies: "install-dependencies.json"
        case .networkDownload: "network-download.json"
        case .performanceStability: "performance-stability.json"
        case .other: "other.json"
        }
    }

    /// User-facing display title for the symptom picker.
    public var displayTitle: String {
        switch self {
        case .launchCrash: "Won't launch / crashes immediately"
        case .launcherIssues: "Launcher issues"
        case .graphics: "Graphics problems"
        case .audio: "Audio problems"
        case .controllerInput: "Controller / input problems"
        case .installDependencies: "Install / dependency problems"
        case .networkDownload: "Network / download problems"
        case .performanceStability: "Performance / stability over time"
        case .other: "Other"
        }
    }

    /// SF Symbol name for the category icon.
    public var sfSymbol: String {
        switch self {
        case .launchCrash: "xmark.app"
        case .launcherIssues: "app.badge.checkmark"
        case .graphics: "display.trianglebadge.exclamationmark"
        case .audio: "speaker.slash"
        case .controllerInput: "gamecontroller"
        case .installDependencies: "shippingbox"
        case .networkDownload: "wifi.exclamationmark"
        case .performanceStability: "chart.line.downtrend.xyaxis"
        case .other: "questionmark.circle"
        }
    }
}
