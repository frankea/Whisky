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
        return CheckResult(
            outcome: .unknown,
            evidence: ["reason": "Audio test executable not available"],
            summary: "Audio playback test is not available (MinGW not compiled)",
            confidence: .low
        )
    }
}
