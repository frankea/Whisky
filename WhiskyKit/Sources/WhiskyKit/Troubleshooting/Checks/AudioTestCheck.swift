//
//  AudioTestCheck.swift
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

/// Wraps the Wine audio test probe for in-bottle audio playback verification.
///
/// Since the MinGW-compiled audio test executable is not available,
/// this check returns `.unknown` with evidence noting the test is
/// unavailable. When the test executable becomes available in a
/// future release, it will delegate to ``WineAudioTestProbe``.
public struct AudioTestCheck: TroubleshootingCheck {
    public let checkId = "audio.test_play"

    public init() {}

    public func run(params: [String: String], context: CheckContext) async -> CheckResult {
        // MinGW is not available; WhiskyAudioTest.exe is not compiled.
        // The probe would return .skipped gracefully.
        CheckResult(
            outcome: .unknown,
            evidence: ["reason": String(localized: "troubleshooting.check.audioTest.unavailableReason")],
            summary: "Audio playback test is not available (MinGW not compiled)",
            confidence: .low
        )
    }

    /// The summary of a result from this check in the user's language.
    ///
    /// ``CheckResult/summary`` stays in English because it is written to
    /// history and escalation exports; this rebuilds the on-screen text from
    /// the result's outcome.
    ///
    /// - Parameter result: A result produced by ``run(params:context:)``.
    /// - Returns: The localized summary, or `nil` if the result was not
    ///   produced by this check.
    public static func localizedSummary(for result: CheckResult) -> String? {
        guard result.outcome == .unknown else { return nil }
        return String(localized: "troubleshooting.check.audioTest.unavailable")
    }
}
