//
//  AudioDriverCheck.swift
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

/// Checks the Wine audio driver setting against an expected value.
///
/// Reads the audio driver mode from the bottle settings and compares it
/// to `params["expected"]`, a driver id or a comma-separated list of the
/// ids that are fine (`"auto,coreaudio"`). Returns `.alreadyConfigured` if
/// the driver is one of them and `.fail` if it is not.
public struct AudioDriverCheck: TroubleshootingCheck {
    public let checkId = "audio.driver_check"

    public init() {}

    public let signature: CheckSignature? = CheckSignature(
        acceptedParams: ["expected"], outcomes: [.alreadyConfigured, .fail, .error]
    )

    public func run(params: [String: String], context: CheckContext) async -> CheckResult {
        let expected = params["expected"] ?? "auto"

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

        let currentDriver = settings.audioDriver.rawValue

        let evidence = [
            "currentDriver": currentDriver,
            "expectedDriver": expected
        ]

        if expected.flowParamList.contains(currentDriver) {
            return CheckResult(
                outcome: .alreadyConfigured,
                evidence: evidence,
                summary: "Audio driver is already set to \(currentDriver)",
                confidence: .high
            )
        }

        return CheckResult(
            outcome: .fail,
            evidence: evidence,
            summary: "Audio driver is \(currentDriver), expected \(expected)",
            confidence: .high
        )
    }

    /// The summary of a result from this check in the user's language.
    ///
    /// ``CheckResult/summary`` stays in English because it is written to
    /// history and escalation exports; this rebuilds the on-screen text from
    /// the result's outcome and evidence.
    ///
    /// - Parameter result: A result produced by ``run(params:context:)``.
    /// - Returns: The localized summary, or `nil` to show ``CheckResult/summary``.
    public static func localizedSummary(for result: CheckResult) -> String? {
        switch result.outcome {
        case .error:
            return String(localized: "troubleshooting.check.settingsUnreadable")
        case .alreadyConfigured:
            // The driver in use: with several accepted, the expected list
            // would not say which one it is.
            guard let current = (result.evidence["currentDriver"] ?? result.evidence["expectedDriver"])
                .map(driverName)
            else {
                return nil
            }
            return String(localized: "troubleshooting.check.audioDriver.matches \(current)")
        case .fail:
            guard let current = result.evidence["currentDriver"].map(driverName),
                  let expected = result.evidence["expectedDriver"].map(driverName)
            else {
                return nil
            }
            return String(localized: "troubleshooting.check.audioDriver.mismatch \(current) \(expected)")
        case .pass, .unknown:
            return nil
        }
    }

    /// The on-screen name for a driver id, or for each of a comma-separated
    /// list of them; ids the app doesn't know stay raw.
    private static func driverName(_ rawValue: String) -> String {
        let ids = rawValue.flowParamList
        guard ids.count > 1 else {
            return AudioDriverMode(rawValue: rawValue)?.displayName ?? rawValue
        }
        return ids.map { AudioDriverMode(rawValue: $0)?.displayName ?? $0 }.joined(separator: ", ")
    }
}
