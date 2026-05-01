//
//  CheckRegistry.swift
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

/// Maps stable check ID strings to ``TroubleshootingCheck`` implementations.
///
/// The registry decouples flow definition JSON (which references check IDs)
/// from the concrete check implementations. Each check wraps an existing
/// diagnostic primitive and returns a normalized ``CheckResult``.
///
/// ## Usage
///
/// ```swift
/// let registry = CheckRegistry()  // All 15 checks pre-registered
/// let result = await registry.run(
///     checkId: "graphics.backend_is",
///     params: ["expected": "dxvk"],
///     context: checkContext
/// )
/// ```
public final class CheckRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var checks: [String: any TroubleshootingCheck] = [:]

    private let logger = Logger(
        subsystem: "com.isaacmarovitz.Whisky",
        category: "CheckRegistry"
    )

    // MARK: - Init

    /// Creates a check registry with all built-in checks pre-registered.
    ///
    /// All 15 default check implementations are registered automatically.
    /// Additional checks can be registered via ``register(_:)`` after
    /// construction.
    public init() {
        registerDefaults()
    }

    // MARK: - Registration

    /// Registers a check implementation in the registry.
    ///
    /// If a check with the same ``TroubleshootingCheck/checkId`` is already
    /// registered, it is replaced silently.
    ///
    /// - Parameter check: The check implementation to register.
    public func register(_ check: any TroubleshootingCheck) {
        lock.withLock {
            checks[check.checkId] = check
        }
        logger.debug("Registered check: \(check.checkId)")
    }

    // MARK: - Execution

    /// Runs the check identified by `checkId` with the given parameters and context.
    ///
    /// If the check ID is not registered, returns an error result with a descriptive
    /// summary. This ensures the flow engine always receives a valid result for branching.
    ///
    /// - Parameters:
    ///   - checkId: The stable identifier of the check to run.
    ///   - params: Key-value parameters from the flow step node.
    ///   - context: The check context with bottle, program, and session state.
    /// - Returns: The check result for flow branching.
    public func run(
        checkId: String,
        params: [String: String],
        context: CheckContext
    ) async -> CheckResult {
        let check: (any TroubleshootingCheck)? = lock.withLock {
            checks[checkId]
        }

        guard let check else {
            logger.error("Unknown check ID: \(checkId)")
            return CheckResult(
                outcome: .error,
                evidence: ["error": "Unknown checkId: \(checkId)"],
                summary: "Check not found: \(checkId)",
                confidence: nil
            )
        }

        logger.debug("Running check: \(checkId)")
        return await check.run(params: params, context: context)
    }

    // MARK: - Default Registration

    /// Registers all 15 built-in check implementations.
    ///
    /// Each check wraps an existing diagnostic primitive and returns a
    /// normalized ``CheckResult``. Check IDs are stable and match the
    /// references in flow definition JSON files.
    public func registerDefaults() {
        // Graphics and crash diagnostics
        register(CrashLogCheck())
        register(GraphicsBackendCheck())
        register(DXVKSettingsCheck())

        // Audio diagnostics
        register(AudioDriverCheck())
        register(AudioDeviceCheck())
        register(AudioTestCheck())

        // Dependency and winetricks
        register(DependencyCheck())
        register(WinetricksVerbCheck())

        // Launcher and process
        register(LauncherTypeCheck())
        register(ProcessRunningCheck())

        // Environment and registry
        register(EnvironmentCheck())
        register(RegistryValueCheck())

        // Game config, settings, and diagnostics
        register(GameConfigAvailableCheck())
        register(SettingValueCheck())
        register(DiagnosticsEnhanceCheck())
    }
}
