//
//  SettingValueCheck.swift
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

/// Checks a specific bottle setting property value against an expected value.
///
/// Reads the setting named in `params["setting"]` from the bottle's
/// ``BottleSettings`` and compares against `params["expected"]`.
/// Supports common settings like `enhancedSync`, `graphicsBackend`,
/// `windowsVersion`, `dxvk`, `metalHud`, and `performancePreset`.
public struct SettingValueCheck: TroubleshootingCheck {
    public let checkId = "setting.value_check"

    public init() {}

    public func run(params: [String: String], context: CheckContext) async -> CheckResult {
        guard let settingName = params["setting"] else {
            return CheckResult(
                outcome: .error,
                evidence: [:],
                summary: "Missing 'setting' parameter",
                confidence: nil
            )
        }

        guard let expected = params["expected"] else {
            return CheckResult(
                outcome: .error,
                evidence: [:],
                summary: "Missing 'expected' parameter",
                confidence: nil
            )
        }

        let bottleURL = context.bottleURL
        let metadataURL = bottleURL.appending(path: "Metadata.plist")

        let settings: BottleSettings
        do {
            settings = try BottleSettings.decode(from: metadataURL)
        } catch {
            return CheckResult(
                outcome: .error,
                evidence: ["error": error.localizedDescription],
                summary: "Failed to read bottle settings",
                confidence: nil
            )
        }

        let currentValue = readSetting(settingName, from: settings)

        guard let currentValue else {
            return CheckResult(
                outcome: .error,
                evidence: ["setting": settingName],
                summary: "Unknown setting: \(settingName)",
                confidence: nil
            )
        }

        let evidence = [
            "setting": settingName,
            "current": currentValue,
            "expected": expected
        ]

        if currentValue == expected {
            return CheckResult(
                outcome: .alreadyConfigured,
                evidence: evidence,
                summary: "\(settingName) is already \(expected)",
                confidence: .high
            )
        }

        return CheckResult(
            outcome: .fail,
            evidence: evidence,
            summary: "\(settingName) is \(currentValue), expected \(expected)",
            confidence: .high
        )
    }

    // MARK: - Private

    private func readSetting(_ name: String, from settings: BottleSettings) -> String? {
        switch name {
        case "enhancedSync":
            return String(describing: settings.enhancedSync)
        case "graphicsBackend":
            return settings.graphicsBackend.rawValue
        case "windowsVersion":
            return String(describing: settings.windowsVersion)
        case "dxvk":
            return settings.dxvk ? "true" : "false"
        case "dxvkAsync":
            return settings.dxvkAsync ? "true" : "false"
        case "metalHud":
            return settings.metalHud ? "true" : "false"
        case "metalTrace":
            return settings.metalTrace ? "true" : "false"
        case "dxrEnabled":
            return settings.dxrEnabled ? "true" : "false"
        case "metalValidation":
            return settings.metalValidation ? "true" : "false"
        case "sequoiaCompatMode":
            return settings.sequoiaCompatMode ? "true" : "false"
        case "performancePreset":
            return String(describing: settings.performancePreset)
        case "shaderCacheEnabled":
            return settings.shaderCacheEnabled ? "true" : "false"
        case "forceD3D11":
            return settings.forceD3D11 ? "true" : "false"
        case "avxEnabled":
            return settings.avxEnabled ? "true" : "false"
        case "launcherCompatibilityMode":
            return settings.launcherCompatibilityMode ? "true" : "false"
        case "controllerCompatibilityMode":
            return settings.controllerCompatibilityMode ? "true" : "false"
        case "virtualDesktopEnabled":
            return settings.virtualDesktopEnabled ? "true" : "false"
        case "audioDriver":
            return settings.audioDriver.rawValue
        default:
            return nil
        }
    }
}
