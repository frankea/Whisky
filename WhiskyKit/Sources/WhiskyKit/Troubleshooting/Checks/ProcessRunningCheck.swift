//
//  ProcessRunningCheck.swift
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

/// Checks whether Wine processes are running for the current bottle.
///
/// Delegates to ``ProcessRegistry`` for the tracked process count.
/// Returns `.pass` if processes are running (with count in evidence),
/// `.fail` if none are running. Uses `params["process"]` as an optional
/// filter name for reporting purposes.
public struct ProcessRunningCheck: TroubleshootingCheck {
    public let checkId = "process.running_check"

    public init() {}

    public func run(params: [String: String], context: CheckContext) async -> CheckResult {
        let processName = params["process"] ?? "wineserver"
        let count = ProcessRegistry.shared.getProcessCount(for: context.bottleURL)

        let evidence = [
            "process": processName,
            "count": "\(count)"
        ]

        if count > 0 {
            return CheckResult(
                outcome: .pass,
                evidence: evidence,
                summary: "\(count) Wine process(es) running",
                confidence: .high
            )
        }

        return CheckResult(
            outcome: .fail,
            evidence: evidence,
            summary: "No Wine processes running for this bottle",
            confidence: .high
        )
    }
}
