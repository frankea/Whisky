//
//  RemediationExecutor.swift
//  Whisky
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
import WhiskyKit

/// Executes a remediation card's action against a bottle.
///
/// Every diagnosis screen shows the same cards, so the doing lives here once:
/// setting changes apply immediately, backend switches hand the decision back
/// to the resolver, and winetricks installs run headlessly with their outcome
/// reported through the same callback.
@MainActor
enum RemediationExecutor {
    private static let logger = Logger(
        subsystem: Bundle.whiskyBundleIdentifier, category: "RemediationExecutor"
    )

    /// Applies `action` to `bottle`, reporting user-facing progress through
    /// `onUpdate`. Called once for synchronous actions; installs report a
    /// start and later a completion.
    ///
    /// Each applied action is added to the remediation history of the
    /// program at `programURL`, which a diagnostic export can include. Pass
    /// `nil` when the diagnosis is not tied to one program.
    static func apply(
        _ action: RemediationAction,
        to bottle: Bottle,
        programURL: URL?,
        onUpdate: @escaping @MainActor (String) -> Void
    ) {
        switch action.actionType {
        case .changeSetting:
            guard let change = applySetting(action, to: bottle) else {
                onUpdate(String(localized: "remediation.unsupported"))
                return
            }
            record(action, before: change.before, after: change.after, bottle: bottle, programURL: programURL)
            onUpdate(String(format: String(localized: "remediation.applied"), action.title))

        case .switchBackend:
            // The bundled card resets to Recommended rather than to a named
            // backend: it fires because the current one is implicated in a
            // crash, and the resolver is the thing that knows what this
            // runtime can actually deliver. DiagnosticsView hides it on a
            // bottle that is already there.
            let before = bottle.settings.graphicsBackend.rawValue
            let target = action.targetBackend ?? .recommended
            bottle.settings.graphicsBackend = target
            record(action, before: before, after: target.rawValue, bottle: bottle, programURL: programURL)
            onUpdate(String(format: String(localized: "remediation.applied"), action.title))

        case .installVerb:
            guard let verb = action.winetricksVerb else {
                logger.error("installVerb action \(action.id, privacy: .public) carries no verb")
                onUpdate(String(localized: "remediation.unsupported"))
                return
            }
            onUpdate(String(format: String(localized: "remediation.installing"), verb))
            Task {
                await installVerb(action, verb: verb, bottle: bottle, programURL: programURL, onUpdate: onUpdate)
            }

        case .informational:
            break
        }
    }

    /// Runs a winetricks install headlessly and reports its outcome.
    private static func installVerb(
        _ action: RemediationAction,
        verb: String,
        bottle: Bottle,
        programURL: URL?,
        onUpdate: @escaping @MainActor (String) -> Void
    ) async {
        var exitCode: Int32?
        var failure: String?
        for await progress in Winetricks.installVerb(verb, for: bottle) {
            switch progress {
            case let .completed(code): exitCode = code
            case let .failed(message): failure = message
            case .preparing, .output: break
            }
        }
        if failure == nil, exitCode == 0 {
            record(action, before: nil, after: "installed", bottle: bottle, programURL: programURL)
            onUpdate(String(format: String(localized: "remediation.installed"), verb))
        } else {
            let detail = failure ?? "exit \(exitCode ?? -1)"
            logger.error(
                "winetricks \(verb, privacy: .public) failed: \(detail, privacy: .public)"
            )
            // The message can carry paths; the history ends up in shared reports.
            let outcome = failure.map { "failed: \(Redactor.redactHomePaths($0))" }
                ?? "failed (exit \(exitCode ?? -1))"
            record(action, before: nil, after: outcome, bottle: bottle, programURL: programURL)
            onUpdate(String(format: String(localized: "remediation.installFailed"), verb))
        }
    }

    /// Adds an applied action to the program's remediation history.
    private static func record(
        _ action: RemediationAction,
        before: String?,
        after: String?,
        bottle: Bottle,
        programURL: URL?
    ) {
        guard let programURL else { return }
        RemediationTimeline.record(
            RemediationTimelineEntry(
                timestamp: Date(),
                actionId: action.id,
                actionTitle: action.title,
                beforeValue: before,
                afterValue: after
            ),
            forProgramAt: programURL,
            inBottleAt: bottle.url
        )
    }

    /// Applies a `changeSetting` action and returns the setting's value
    /// before and after, or `nil` when the action cannot be applied.
    ///
    /// The key paths are the vocabulary of `remediations.json`; a key path
    /// this build does not know reports honestly instead of claiming success.
    private static func applySetting(
        _ action: RemediationAction,
        to bottle: Bottle
    ) -> (before: String, after: String)? {
        switch action.settingKeyPath {
        case "metalConfig.dxrEnabled":
            let before = String(bottle.settings.dxrEnabled)
            bottle.settings.dxrEnabled = action.settingValue == "true"
            return (before, String(bottle.settings.dxrEnabled))
        case "networkTimeout":
            guard let value = action.settingValue.flatMap(Int.init) else { return nil }
            let before = String(bottle.settings.networkTimeout)
            bottle.settings.networkTimeout = value
            return (before, String(bottle.settings.networkTimeout))
        default:
            let keyPath = action.settingKeyPath ?? "nil"
            logger.error(
                "Unknown settingKeyPath \(keyPath, privacy: .public) for \(action.id, privacy: .public)"
            )
            return nil
        }
    }
}
