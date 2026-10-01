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
    static func apply(
        _ action: RemediationAction,
        to bottle: Bottle,
        onUpdate: @escaping @MainActor (String) -> Void
    ) {
        switch action.actionType {
        case .changeSetting:
            onUpdate(applySetting(action, to: bottle))

        case .switchBackend:
            // Back to the resolver's choice rather than to a named backend:
            // the card fires because the current one is implicated in a
            // crash, and the resolver is the thing that knows what this
            // runtime can actually deliver.
            bottle.settings.graphicsBackend = .recommended
            onUpdate(String(format: String(localized: "remediation.applied"), action.title))

        case .installVerb:
            guard let verb = action.winetricksVerb else {
                logger.error("installVerb action \(action.id, privacy: .public) carries no verb")
                onUpdate(String(localized: "remediation.unsupported"))
                return
            }
            onUpdate(String(format: String(localized: "remediation.installing"), verb))
            Task {
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
                    onUpdate(String(format: String(localized: "remediation.installed"), verb))
                } else {
                    let detail = failure ?? "exit \(exitCode ?? -1)"
                    logger.error(
                        "winetricks \(verb, privacy: .public) failed: \(detail, privacy: .public)"
                    )
                    onUpdate(String(format: String(localized: "remediation.installFailed"), verb))
                }
            }

        case .informational:
            break
        }
    }

    /// The key paths are the vocabulary of `remediations.json`; a key path
    /// this build does not know reports honestly instead of claiming success.
    private static func applySetting(_ action: RemediationAction, to bottle: Bottle) -> String {
        switch action.settingKeyPath {
        case "metalConfig.dxrEnabled":
            bottle.settings.dxrEnabled = action.settingValue == "true"
        case "networkTimeout":
            guard let value = action.settingValue.flatMap(Int.init) else {
                return String(localized: "remediation.unsupported")
            }
            bottle.settings.networkTimeout = value
        default:
            let keyPath = action.settingKeyPath ?? "nil"
            logger.error(
                "Unknown settingKeyPath \(keyPath, privacy: .public) for \(action.id, privacy: .public)"
            )
            return String(localized: "remediation.unsupported")
        }
        return String(format: String(localized: "remediation.applied"), action.title)
    }
}
