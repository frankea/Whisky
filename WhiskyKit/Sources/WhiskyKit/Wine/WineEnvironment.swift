//
//  WineEnvironment.swift
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
import os.log

private let envLogger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "WineEnvironment")

extension Wine {
    /// Construct an environment merging the bottle values with the given values.
    ///
    /// Invalid environment variable keys (those not matching `[A-Za-z_][A-Za-z0-9_]*`)
    /// are filtered out with a debug log message, as macOS silently ignores them.
    @MainActor
    static func constructWineEnvironment(
        for bottle: Bottle, environment: [String: String] = [:]
    ) -> [String: String] {
        var result: [String: String] = [
            "WINEPREFIX": bottle.url.path,
            "WINEDEBUG": "fixme-all",
            "GST_DEBUG": "1"
        ]

        // Apply macOS 15.x compatibility fixes
        applyMacOSCompatibilityFixes(to: &result)

        bottle.settings.environmentVariables(wineEnv: &result)

        guard !environment.isEmpty else { return result }

        // Filter and merge user-provided environment, logging invalid keys
        for (key, value) in environment {
            if isValidEnvKey(key) {
                result[key] = value
            } else {
                envLogger.debug("Skipping invalid environment key '\(key)' in constructWineEnvironment")
            }
        }
        return result
    }

    /// Construct an environment merging the bottle values with the given values.
    ///
    /// Invalid environment variable keys (those not matching `[A-Za-z_][A-Za-z0-9_]*`)
    /// are filtered out with a debug log message, as macOS silently ignores them.
    @MainActor
    static func constructWineServerEnvironment(
        for bottle: Bottle, environment: [String: String] = [:]
    ) -> [String: String] {
        var result: [String: String] = [
            "WINEPREFIX": bottle.url.path,
            "WINEDEBUG": "fixme-all",
            "GST_DEBUG": "1"
        ]

        // Apply macOS 15.x compatibility fixes
        applyMacOSCompatibilityFixes(to: &result)

        guard !environment.isEmpty else { return result }

        // Filter and merge user-provided environment, logging invalid keys
        for (key, value) in environment {
            if isValidEnvKey(key) {
                result[key] = value
            } else {
                envLogger.debug("Skipping invalid environment key '\(key)' in constructWineServerEnvironment")
            }
        }
        return result
    }
}
