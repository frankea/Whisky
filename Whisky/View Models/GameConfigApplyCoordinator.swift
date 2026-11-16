//
//  GameConfigApplyCoordinator.swift
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
import WhiskyKit

/// Runs game configuration applies from the game database detail view.
///
/// An apply installs winetricks components for minutes, so it belongs to the
/// app rather than to the view that started it: it keeps going when the user
/// navigates away, its result waits until the entry's detail view is shown
/// again, and a bottle never runs two applies (and two winetricks installs in
/// one prefix) at once.
@MainActor
final class GameConfigApplyCoordinator: ObservableObject {
    static let shared = GameConfigApplyCoordinator()

    /// An apply in progress in one bottle.
    struct Run {
        /// The ``GameDBEntry`` being applied.
        let entryId: String
        /// The component being installed, once installs have begun.
        var progress: GameConfigVerbProgress?
        fileprivate let task: Task<Void, Never>
    }

    /// A finished apply's message, kept until the entry's detail view shows it.
    struct Result: Identifiable {
        let id = UUID()
        /// The ``GameDBEntry`` that was applied.
        let entryId: String
        let toast: ToastData
    }

    /// Applies in progress, by bottle URL.
    @Published private(set) var runs: [URL: Run] = [:]
    /// Finished applies whose message has not been shown yet, by bottle URL.
    @Published private(set) var results: [URL: Result] = [:]

    /// The apply in progress in `bottle`, if any.
    func run(in bottle: Bottle) -> Run? {
        runs[bottle.url]
    }

    /// Applies `variant` to `bottle` and installs the components it still
    /// needs. Does nothing while another apply runs in the bottle.
    ///
    /// - Parameters:
    ///   - entry: The entry being applied.
    ///   - variant: The variant to apply.
    ///   - bottle: The bottle to apply it to.
    ///   - programURL: The program the configuration is applied from, if any.
    ///   - installComponents: Whether to install the variant's missing winetricks verbs.
    func start(
        entry: GameDBEntry,
        variant: GameConfigVariant,
        bottle: Bottle,
        programURL: URL?,
        installComponents: Bool
    ) {
        let url = bottle.url
        guard runs[url] == nil else { return }
        let task = Task {
            let toast = await self.apply(
                entry: entry,
                variant: variant,
                bottle: bottle,
                programURL: programURL,
                installComponents: installComponents
            )
            self.results[url] = Result(entryId: entry.id, toast: toast)
            self.runs[url] = nil
        }
        runs[url] = Run(entryId: entry.id, task: task)
    }

    /// Stops the component installs of the apply in progress in `bottle`.
    func cancel(in bottle: Bottle) {
        runs[bottle.url]?.task.cancel()
    }

    /// The message of a finished apply of `entryId` to `bottle`, removed so it
    /// is shown once.
    func takeResult(for entryId: String, in bottle: Bottle) -> ToastData? {
        guard let result = results[bottle.url], result.entryId == entryId else { return nil }
        results[bottle.url] = nil
        return result.toast
    }

    /// Applies the configuration, reporting install progress on the bottle's run.
    private func apply(
        entry: GameDBEntry,
        variant: GameConfigVariant,
        bottle: Bottle,
        programURL: URL?,
        installComponents: Bool
    ) async -> ToastData {
        do {
            _ = try GameConfigApplicator.apply(entry: entry, variant: variant, to: bottle, programURL: programURL)
        } catch {
            return ToastData(
                message: String(localized: "gameConfig.apply.failed \(error.localizedDescription)"),
                style: .error
            )
        }

        let installed = await Winetricks.loadInstalledVerbs(for: bottle).verbs
        let pending = GameConfigApplicator.pendingWinetricksVerbs(variant: variant, installedVerbs: installed)
        var outcome = GameConfigVerbInstallOutcome(requested: pending)
        if installComponents, !pending.isEmpty {
            outcome = await Winetricks.installGameConfigVerbs(pending, for: bottle) { progress in
                self.runs[bottle.url]?.progress = progress
            }
        }
        return Self.toast(for: outcome, title: entry.title)
    }

    /// Success only when every component the configuration needs is in the bottle.
    private static func toast(for outcome: GameConfigVerbInstallOutcome, title: String) -> ToastData {
        let missing = outcome.missing.joined(separator: ", ")
        return switch outcome.status {
        case .complete:
            ToastData(message: String(localized: "gameConfig.apply.success \(title)"), style: .success)
        case .failed:
            ToastData(
                message: String(localized: "gameConfig.apply.componentsFailed \(title) \(missing)"),
                style: .error,
                autoDismiss: false
            )
        case .incomplete:
            ToastData(
                message: String(localized: "gameConfig.apply.componentsSkipped \(title) \(missing)"),
                style: .info,
                autoDismiss: false
            )
        }
    }
}
