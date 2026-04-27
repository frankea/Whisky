//
//  DXVKSettingsCheck.swift
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

/// Checks a specific DXVK setting value against an expected state.
///
/// Reads the DXVK setting specified by `params["setting"]` (e.g., "async",
/// "hud") from the bottle settings file and compares it to the expected value.
/// Uses the bottle URL from context to load settings from disk.
public struct DXVKSettingsCheck: TroubleshootingCheck {
    public let checkId = "dxvk.settings_check"

    public init() {}

    // swiftlint:disable:next function_body_length
    public func run(params: [String: String], context: CheckContext) async -> CheckResult {
        guard let setting = params["setting"] else {
            return CheckResult(
                outcome: .error,
                evidence: [:],
                summary: "Missing 'setting' parameter",
                confidence: nil
            )
        }

        let expected = params["expected"] ?? "true"

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

        let currentValue: String
        switch setting {
        case "async":
            currentValue = settings.dxvkAsync ? "true" : "false"
        case "hud":
            currentValue = String(describing: settings.dxvkHud)
        case "backend":
            currentValue = settings.graphicsBackend.rawValue
        default:
            return CheckResult(
                outcome: .error,
                evidence: ["setting": setting],
                summary: "Unknown DXVK setting: \(setting)",
                confidence: nil
            )
        }

        let evidence = [
            "setting": setting,
            "current": currentValue,
            "expected": expected
        ]

        if currentValue == expected {
            return CheckResult(
                outcome: .alreadyConfigured,
                evidence: evidence,
                summary: "DXVK \(setting) is already \(expected)",
                confidence: .high
            )
        }

        return CheckResult(
            outcome: .fail,
            evidence: evidence,
            summary: "DXVK \(setting) is \(currentValue), expected \(expected)",
            confidence: .high
        )
    }
}
