//
//  RegistryValueCheck.swift
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

/// Checks a Wine registry value against an expected value.
///
/// Reads a registry key via the Wine registry file at the bottle's
/// prefix path. Params: `key` (registry path), `valueName` (value name),
/// `type` (REG_SZ, REG_DWORD, etc.), and optionally `expected`.
/// Returns `.pass` if the value matches, `.fail` otherwise, or
/// `.unknown` if the key does not exist.
public struct RegistryValueCheck: TroubleshootingCheck {
    public let checkId = "registry.value_check"

    public init() {}

    public func run(params: [String: String], context: CheckContext) async -> CheckResult {
        guard let key = params["key"], let valueName = params["valueName"] else {
            return CheckResult(
                outcome: .error,
                evidence: [:],
                summary: "Missing 'key' or 'valueName' parameter",
                confidence: nil
            )
        }

        // Parse the registry file directly from the bottle prefix
        // to avoid needing a Wine process (which requires @MainActor Bottle).
        let registryValue = readRegistryFromFile(
            bottleURL: context.bottleURL,
            key: key,
            valueName: valueName
        )

        let expected = params["expected"]

        var evidence = [
            "key": key,
            "valueName": valueName
        ]

        guard let currentValue = registryValue else {
            return CheckResult(
                outcome: .unknown,
                evidence: evidence,
                summary: "Registry key not found: \(key)\\\\\\(\(valueName))",
                confidence: .low
            )
        }

        evidence["currentValue"] = currentValue

        if let expected {
            evidence["expected"] = expected
            if currentValue == expected {
                return CheckResult(
                    outcome: .pass,
                    evidence: evidence,
                    summary: "\(valueName) = \(currentValue)",
                    confidence: .high
                )
            }
            return CheckResult(
                outcome: .fail,
                evidence: evidence,
                summary: "\(valueName) is \(currentValue), expected \(expected)",
                confidence: .high
            )
        }

        return CheckResult(
            outcome: .pass,
            evidence: evidence,
            summary: "\(valueName) = \(currentValue)",
            confidence: .high
        )
    }

    // MARK: - Private

    /// Reads a registry value directly from the Wine prefix's .reg files.
    private func readRegistryFromFile(
        bottleURL: URL,
        key: String,
        valueName: String
    ) -> String? {
        // Determine which .reg file to read
        let regFileName: String
        if key.hasPrefix("HKCU") || key.hasPrefix("HKEY_CURRENT_USER") {
            regFileName = "user.reg"
        } else if key.hasPrefix("HKLM") || key.hasPrefix("HKEY_LOCAL_MACHINE") {
            regFileName = "system.reg"
        } else {
            return nil
        }

        let regFileURL = bottleURL.appending(path: regFileName)
        guard let content = try? String(contentsOf: regFileURL, encoding: .utf8) else {
            return nil
        }

        // Normalize the key path for .reg file format
        // HKCU\Software\Wine\Drivers -> [Software\\Wine\\Drivers]
        let normalizedKey = key
            .replacingOccurrences(of: "HKCU\\", with: "")
            .replacingOccurrences(of: "HKEY_CURRENT_USER\\", with: "")
            .replacingOccurrences(of: "HKLM\\", with: "")
            .replacingOccurrences(of: "HKEY_LOCAL_MACHINE\\", with: "")
            .replacingOccurrences(of: "\\", with: "\\\\")

        let sectionHeader = "[" + normalizedKey + "]"

        let lines = content.components(separatedBy: "\n")
        var inSection = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("[") {
                inSection = trimmed.lowercased().hasPrefix(sectionHeader.lowercased())
                continue
            }

            if inSection, trimmed.hasPrefix("\"\(valueName)\"") {
                // Parse value: "valueName"="value" or "valueName"=dword:00000001
                if let equalsIndex = trimmed.firstIndex(of: "=") {
                    let rawValue = String(trimmed[trimmed.index(after: equalsIndex)...])
                        .trimmingCharacters(in: .whitespaces)
                    // Strip surrounding quotes if present
                    if rawValue.hasPrefix("\""), rawValue.hasSuffix("\"") {
                        return String(rawValue.dropFirst().dropLast())
                    }
                    return rawValue
                }
            }
        }

        return nil
    }
}
