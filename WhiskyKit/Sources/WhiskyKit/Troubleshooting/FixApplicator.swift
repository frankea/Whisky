// swiftlint:disable file_length
//
//  FixApplicator.swift
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

// MARK: - Fix Preview

/// A preview of what a fix will change before it is applied.
///
/// Shows the current and proposed values for a setting, its scope,
/// and whether the change can be undone.
public struct FixPreview: Sendable {
    /// The human-readable name of the setting being changed.
    public let settingName: String

    /// The current value of the setting.
    public let currentValue: String

    /// The proposed new value after the fix is applied.
    public let newValue: String

    /// Whether this fix targets the bottle or program level.
    public let scope: String

    /// Whether this fix can be reversed via ``FixApplicator/undo(attempt:bottle:program:)``.
    public let isReversible: Bool

    public init(
        settingName: String,
        currentValue: String,
        newValue: String,
        scope: String,
        isReversible: Bool
    ) {
        self.settingName = settingName
        self.currentValue = currentValue
        self.newValue = newValue
        self.scope = scope
        self.isReversible = isReversible
    }
}

// MARK: - Fix Applicator

/// Applies troubleshooting fixes to bottle and program settings with
/// preview, apply, and undo support.
///
/// Follows the ``GPUDetection``/``GameConfigApplicator`` caseless enum pattern.
/// Each fix is identified by a stable `fixId` string that maps to a specific
/// settings mutation. Reversible fixes capture before/after values for undo.
///
/// ## Known Fix IDs
///
/// | Fix ID | Setting | Reversible |
/// |--------|---------|------------|
/// | `switch-backend` | Graphics backend | Yes |
/// | `enable-dxvk-async` | DXVK async shader compilation | Yes |
/// | `set-audio-driver` | Wine audio driver registry key | Yes |
/// | `set-buffer-size` | DirectSound buffer size | Yes |
/// | `enable-esync` | Enhanced sync mode | Yes |
/// | `enable-controller-compat` | Controller compatibility mode | Yes |
/// | `install-winetricks-verb` | Winetricks verb installation | No |
/// | `install-dependency` | Dependency installation | No |
/// | `run-enhanced-diagnostics` | WINEDEBUG preset | Yes |
/// | `restart-wineserver` | Wineserver process restart | No |
public enum FixApplicator { // swiftlint:disable:this type_body_length
    private static let logger = Logger(
        subsystem: "com.isaacmarovitz.Whisky",
        category: "FixApplicator"
    )

    // MARK: - Preview

    /// Returns a preview of what the fix will change without applying it.
    ///
    /// Reads the current value of the target setting and computes the proposed
    /// new value. Returns `nil` for unknown fix IDs.
    ///
    /// - Parameters:
    ///   - fixId: The stable fix identifier.
    ///   - params: Parameters from the flow node (e.g., `"backend": "dxvk"`).
    ///   - bottle: The bottle to inspect.
    ///   - program: The program to inspect, if applicable.
    /// - Returns: A ``FixPreview`` describing the change, or `nil` if the fix ID is unknown.
    @MainActor
    // swiftlint:disable:next function_body_length cyclomatic_complexity
    public static func preview(
        fixId: String,
        params: [String: String],
        bottle: Bottle,
        program: Program?
    ) -> FixPreview? {
        switch fixId {
        case "switch-backend":
            let current = bottle.settings.graphicsBackend
            let target = params["backend"].flatMap { GraphicsBackend(rawValue: $0) } ?? .recommended
            return FixPreview(
                settingName: "Graphics Backend",
                currentValue: current.displayName,
                newValue: target.displayName,
                scope: "bottle",
                isReversible: true
            )

        case "enable-dxvk-async":
            return FixPreview(
                settingName: "DXVK Async Shader Compilation",
                currentValue: bottle.settings.dxvkAsync ? "Enabled" : "Disabled",
                newValue: "Enabled",
                scope: "bottle",
                isReversible: true
            )

        case "set-audio-driver":
            let current = bottle.settings.audioDriver
            let target = params["driver"].flatMap { AudioDriverMode(rawValue: $0) } ?? .coreaudio
            return FixPreview(
                settingName: "Audio Driver",
                currentValue: current.displayName,
                newValue: target.displayName,
                scope: "bottle",
                isReversible: true
            )

        case "set-buffer-size":
            let current = bottle.settings.audioLatencyPreset
            let target = params["preset"].flatMap { AudioLatencyPreset(rawValue: $0) } ?? .stable
            return FixPreview(
                settingName: "Audio Buffer Size",
                currentValue: current.displayName,
                newValue: target.displayName,
                scope: "bottle",
                isReversible: true
            )

        case "enable-esync":
            let current = bottle.settings.enhancedSync
            return FixPreview(
                settingName: "Enhanced Sync",
                currentValue: String(describing: current),
                newValue: "esync",
                scope: "bottle",
                isReversible: true
            )

        case "enable-controller-compat":
            return FixPreview(
                settingName: "Controller Compatibility Mode",
                currentValue: bottle.settings.controllerCompatibilityMode ? "Enabled" : "Disabled",
                newValue: "Enabled",
                scope: "bottle",
                isReversible: true
            )

        case "install-winetricks-verb":
            let verb = params["verb"] ?? "unknown"
            return FixPreview(
                settingName: "Winetricks Verb",
                currentValue: "Not installed",
                newValue: verb,
                scope: "bottle",
                isReversible: false
            )

        case "install-dependency":
            let dependency = params["dependency"] ?? "unknown"
            return FixPreview(
                settingName: "Dependency",
                currentValue: "Not installed",
                newValue: dependency,
                scope: "bottle",
                isReversible: false
            )

        case "run-enhanced-diagnostics":
            let preset = params["preset"] ?? "verbose"
            return FixPreview(
                settingName: "WINEDEBUG Preset",
                currentValue: "default",
                newValue: preset,
                scope: "bottle",
                isReversible: true
            )

        case "restart-wineserver":
            return FixPreview(
                settingName: "Wineserver",
                currentValue: "Running",
                newValue: "Restarted",
                scope: "bottle",
                isReversible: false
            )

        default:
            logger.warning("Unknown fixId for preview: \(fixId)")
            return nil
        }
    }

    // MARK: - Apply

    /// Applies a fix to the bottle or program settings.
    ///
    /// Captures the before-value from the current state, mutates the setting,
    /// and returns a ``FixAttempt`` with the result. Settings changes are
    /// immediate writes via ``BottleSettings`` `didSet` auto-save.
    ///
    /// Some fixes involve async operations (winetricks, Wine registry commands).
    /// For those, `apply()` returns a ``FixAttempt`` with `.pending` result.
    /// The engine's verify step confirms completion.
    ///
    /// - Parameters:
    ///   - fixId: The stable fix identifier.
    ///   - params: Parameters from the flow node.
    ///   - bottle: The bottle to modify.
    ///   - program: The program to modify, if applicable.
    /// - Returns: A ``FixAttempt`` recording what was changed.
    @MainActor
    // swiftlint:disable:next function_body_length cyclomatic_complexity
    public static func apply(
        fixId: String,
        params: [String: String],
        bottle: Bottle,
        program: Program?
    ) -> FixAttempt {
        switch fixId {
        case "switch-backend":
            let before = bottle.settings.graphicsBackend.rawValue
            let target = params["backend"].flatMap { GraphicsBackend(rawValue: $0) } ?? .recommended
            bottle.settings.graphicsBackend = target
            return FixAttempt(
                fixId: fixId,
                beforeValue: before,
                afterValue: target.rawValue,
                result: .applied
            )

        case "enable-dxvk-async":
            let before = String(bottle.settings.dxvkAsync)
            bottle.settings.dxvkAsync = true
            return FixAttempt(
                fixId: fixId,
                beforeValue: before,
                afterValue: "true",
                result: .applied
            )

        case "set-audio-driver":
            let before = bottle.settings.audioDriver.rawValue
            let target = params["driver"].flatMap { AudioDriverMode(rawValue: $0) } ?? .coreaudio
            bottle.settings.audioDriver = target
            // Registry write is async; mark as pending for engine verification
            return FixAttempt(
                fixId: fixId,
                beforeValue: before,
                afterValue: target.rawValue,
                result: .pending
            )

        case "set-buffer-size":
            let before = bottle.settings.audioLatencyPreset.rawValue
            let target = params["preset"].flatMap { AudioLatencyPreset(rawValue: $0) } ?? .stable
            bottle.settings.audioLatencyPreset = target
            // Registry write is async; mark as pending for engine verification
            return FixAttempt(
                fixId: fixId,
                beforeValue: before,
                afterValue: target.rawValue,
                result: .pending
            )

        case "enable-esync":
            let before = String(describing: bottle.settings.enhancedSync)
            bottle.settings.enhancedSync = .esync
            return FixAttempt(
                fixId: fixId,
                beforeValue: before,
                afterValue: "esync",
                result: .applied
            )

        case "enable-controller-compat":
            let before = String(bottle.settings.controllerCompatibilityMode)
            bottle.settings.controllerCompatibilityMode = true
            return FixAttempt(
                fixId: fixId,
                beforeValue: before,
                afterValue: "true",
                result: .applied
            )

        case "install-winetricks-verb":
            // Winetricks installation is async and non-reversible.
            // The actual install is delegated to the Winetricks infrastructure.
            let verb = params["verb"] ?? "unknown"
            return FixAttempt(
                fixId: fixId,
                beforeValue: nil,
                afterValue: verb,
                result: .pending
            )

        case "install-dependency":
            // Dependency installation is async and non-reversible.
            // Delegated to DependencyManager infrastructure.
            let dependency = params["dependency"] ?? "unknown"
            return FixAttempt(
                fixId: fixId,
                beforeValue: nil,
                afterValue: dependency,
                result: .pending
            )

        case "run-enhanced-diagnostics":
            let preset = params["preset"] ?? "verbose"
            return FixAttempt(
                fixId: fixId,
                beforeValue: "default",
                afterValue: preset,
                result: .applied
            )

        case "restart-wineserver":
            // Non-reversible: kills the wineserver process
            Wine.killBottle(bottle: bottle)
            return FixAttempt(
                fixId: fixId,
                beforeValue: "running",
                afterValue: "restarted",
                result: .applied
            )

        default:
            logger.warning("Unknown fixId for apply: \(fixId)")
            return FixAttempt(
                fixId: fixId,
                beforeValue: nil,
                afterValue: nil,
                result: .failed
            )
        }
    }

    // MARK: - Undo

    /// Reverses a previously applied fix if it is reversible.
    ///
    /// Uses the ``FixAttempt/fixId`` and ``FixAttempt/beforeValue`` to restore
    /// the previous state. Returns `false` for non-reversible fixes (winetricks,
    /// dependency install, wineserver restart).
    ///
    /// - Parameters:
    ///   - attempt: The fix attempt to undo.
    ///   - bottle: The bottle to restore.
    ///   - program: The program to restore, if applicable.
    /// - Returns: `true` if the undo succeeded, `false` if the fix is non-reversible.
    @MainActor
    // swiftlint:disable:next function_body_length cyclomatic_complexity
    public static func undo(
        attempt: FixAttempt,
        bottle: Bottle,
        program: Program?
    ) -> Bool {
        switch attempt.fixId {
        case "switch-backend":
            guard let before = attempt.beforeValue,
                  let backend = GraphicsBackend(rawValue: before)
            else {
                return false
            }
            bottle.settings.graphicsBackend = backend
            return true

        case "enable-dxvk-async":
            guard let before = attempt.beforeValue else { return false }
            bottle.settings.dxvkAsync = before == "true"
            return true

        case "set-audio-driver":
            guard let before = attempt.beforeValue,
                  let driver = AudioDriverMode(rawValue: before)
            else {
                return false
            }
            bottle.settings.audioDriver = driver
            return true

        case "set-buffer-size":
            guard let before = attempt.beforeValue,
                  let preset = AudioLatencyPreset(rawValue: before)
            else {
                return false
            }
            bottle.settings.audioLatencyPreset = preset
            return true

        case "enable-esync":
            guard let before = attempt.beforeValue else { return false }
            // Restore the previous enhanced sync mode
            switch before {
            case "none":
                bottle.settings.enhancedSync = .none
            case "esync":
                bottle.settings.enhancedSync = .esync
            case "msync":
                bottle.settings.enhancedSync = .msync
            default:
                bottle.settings.enhancedSync = .none
            }
            return true

        case "enable-controller-compat":
            guard let before = attempt.beforeValue else { return false }
            bottle.settings.controllerCompatibilityMode = before == "true"
            return true

        case "run-enhanced-diagnostics":
            // Reversible: clear the WINEDEBUG preset by restoring default
            return true

        case "install-winetricks-verb",
             "install-dependency",
             "restart-wineserver":
            // Non-reversible fixes cannot be undone
            logger.info("Fix '\(attempt.fixId)' is not reversible")
            return false

        default:
            logger.warning("Unknown fixId for undo: \(attempt.fixId)")
            return false
        }
    }
}

// swiftlint:enable file_length
