//
//  DependencyCheck.swift
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

/// Checks for the presence of specific DLL files in the Wine prefix.
///
/// Inspects both `system32` and `syswow64` directories under the bottle's
/// `drive_c/windows` for each DLL listed in `params["dlls"]` (comma-separated).
/// Returns `.pass` if all DLLs are found, `.fail` with evidence listing
/// the missing DLLs.
public struct DependencyCheck: TroubleshootingCheck {
    public let checkId = "dependency.check_missing"

    public init() {}

    public func run(params: [String: String], context: CheckContext) async -> CheckResult {
        guard let dllsParam = params["dlls"], !dllsParam.isEmpty else {
            return CheckResult(
                outcome: .error,
                evidence: [:],
                summary: "Missing 'dlls' parameter",
                confidence: nil
            )
        }

        let dlls = dllsParam.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let windowsDir = context.bottleURL
            .appending(path: "drive_c")
            .appending(path: "windows")
        let system32 = windowsDir.appending(path: "system32")
        let syswow64 = windowsDir.appending(path: "syswow64")

        var missingDLLs: [String] = []
        var foundDLLs: [String] = []

        for dll in dlls {
            let sys32Path = system32.appending(path: dll).path(percentEncoded: false)
            let wow64Path = syswow64.appending(path: dll).path(percentEncoded: false)

            if FileManager.default.fileExists(atPath: sys32Path)
                || FileManager.default.fileExists(atPath: wow64Path)
            {
                foundDLLs.append(dll)
            } else {
                missingDLLs.append(dll)
            }
        }

        var evidence = [
            "checked": dlls.joined(separator: ", "),
            "found": foundDLLs.joined(separator: ", ")
        ]

        if missingDLLs.isEmpty {
            return CheckResult(
                outcome: .pass,
                evidence: evidence,
                summary: "All \(dlls.count) DLL(s) found in prefix",
                confidence: .high
            )
        }

        evidence["missing"] = missingDLLs.joined(separator: ", ")
        return CheckResult(
            outcome: .fail,
            evidence: evidence,
            summary: "\(missingDLLs.count) missing DLL(s): \(missingDLLs.joined(separator: ", "))",
            confidence: .high
        )
    }
}
