//
//  DiagnosticsEnhanceCheck.swift
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

/// Checks whether enhanced diagnostics (WINEDEBUG preset) can provide additional info.
///
/// Reads the current WINEDEBUG environment setting from the bottle. Returns
/// `.pass` if enhanced diagnostics would add value (default/normal preset),
/// `.alreadyConfigured` if a debug preset is already active, or `.fail`
/// if not applicable.
public struct DiagnosticsEnhanceCheck: TroubleshootingCheck {
    public let checkId = "diagnostics.can_enhance"

    public init() {}

    public func run(params: [String: String], context: CheckContext) async -> CheckResult {
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

        // Build the environment to check for WINEDEBUG
        var builder = EnvironmentBuilder()
        _ = settings.populateBottleManagedLayer(builder: &builder)
        let (environment, _) = builder.resolve()

        let currentDebug = environment["WINEDEBUG"]

        // Check if a non-default WINEDEBUG preset is active
        let nonDefaultPresets = [
            WineDebugPreset.crash.winedebugValue,
            WineDebugPreset.dllLoad.winedebugValue,
            WineDebugPreset.verbose.winedebugValue
        ]

        if let currentDebug, nonDefaultPresets.contains(currentDebug) {
            // Determine which preset is active
            let presetName: String
            if currentDebug == WineDebugPreset.crash.winedebugValue {
                presetName = WineDebugPreset.crash.displayName
            } else if currentDebug == WineDebugPreset.dllLoad.winedebugValue {
                presetName = WineDebugPreset.dllLoad.displayName
            } else {
                presetName = WineDebugPreset.verbose.displayName
            }

            return CheckResult(
                outcome: .alreadyConfigured,
                evidence: [
                    "currentPreset": presetName,
                    "winedebug": currentDebug
                ],
                summary: "Enhanced diagnostics already active: \(presetName)",
                confidence: .high
            )
        }

        // Default or normal preset -- enhanced diagnostics can help
        let suggestedPreset = params["preset"] ?? "crash"
        return CheckResult(
            outcome: .pass,
            evidence: [
                "currentPreset": "normal",
                "suggestedPreset": suggestedPreset
            ],
            summary: "Enhanced diagnostics available for more detailed logging",
            confidence: .medium
        )
    }
}
