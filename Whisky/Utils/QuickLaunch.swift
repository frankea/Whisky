//
//  QuickLaunch.swift
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

import AppKit
import os.log
import WhiskyKit

/// Launching from surfaces that live outside the main window: the Dock menu,
/// the menu-bar extra, and `whisky://` URLs.
///
/// The URL scheme is the identity layer for all of them. Every surface here
/// names a target the same way a URL does, an installed Steam app ID or a pin
/// the user made, and resolves it at launch time rather than baking a path. A
/// shortcut therefore survives its bottle being moved or renamed, and picks up
/// current settings, DLL deployment and crash classification, because it goes
/// through the same door as a launch from the window. Anything added later that
/// starts a program from outside the window belongs here, resolving the same
/// two identifiers, rather than growing its own path handling. Why a URL may
/// only ever name those two things is ``WhiskyKit/WhiskyURL``.
@MainActor
enum QuickLaunch {
    private static let logger = Logger(
        subsystem: Bundle.whiskyBundleIdentifier, category: "QuickLaunch"
    )

    /// Every pin whose file still exists, across all available bottles.
    ///
    /// Reads `settings.pins` rather than `bottle.pinnedPrograms`: the latter
    /// resolves against `bottle.programs`, which stays empty until a bottle
    /// view scans it. Pins live in settings and are always loaded.
    static func availablePins() -> [(bottle: Bottle, pin: PinnedProgram)] {
        BottleVM.shared.bottles.filter(\.isAvailable).flatMap { bottle in
            bottle.settings.pins.compactMap { pin -> (bottle: Bottle, pin: PinnedProgram)? in
                guard let path = pin.url?.path(percentEncoded: false),
                      FileManager.default.fileExists(atPath: path)
                else { return nil }
                return (bottle, pin)
            }
        }
    }

    /// Launches a pinned program without a prior bottle scan.
    ///
    /// The `Program` is built from the pin so this doesn't depend on a bottle
    /// view having scanned. Failures are reported via an `NSAlert` rather than
    /// a view toast because these surfaces can be the app's only one (the main
    /// window may be closed), so there's no toast presenter to reach.
    static func launch(pin: PinnedProgram, in bottle: Bottle) {
        guard let url = pin.url else { return }
        let program = Program(url: url, bottle: bottle)
        Task {
            let result = await program.launchWithUserMode(useTerminal: false)
            guard case let .launchFailed(_, errorDescription) = result else { return }
            logger.error(
                "Quick launch failed for \(pin.name, privacy: .public): \(errorDescription, privacy: .public)"
            )
            presentLaunchFailure(programName: pin.name, error: errorDescription)
        }
    }

    private static func presentLaunchFailure(programName: String, error: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "menubar.launchFailed \(programName)")
        alert.informativeText = error
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "button.ok"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - whisky:// URLs

    /// A target a `whisky://` URL named, already resolved against real state.
    ///
    /// Resolution happens before the confirmation, not after, so the dialog can
    /// name what will actually run rather than echoing back the app ID the page
    /// supplied.
    ///
    /// `@MainActor` for ``consentKey``: a nested type does not inherit the
    /// enclosing type's isolation.
    @MainActor
    enum Target {
        case steam(appId: Int, bottle: Bottle)
        case pin(PinnedProgram, bottle: Bottle)

        /// What the user sees in the confirmation.
        var displayName: String {
            switch self {
            case let .steam(appId, _): "Steam \(appId)"
            case let .pin(pin, _): pin.name
            }
        }

        /// Identifies the target across launches, so "always allow" outlives a
        /// restart. Scoped by bottle, since the same app ID in a different
        /// bottle is a different thing to approve.
        var consentKey: String {
            switch self {
            case let .steam(appId, bottle): "steam:\(bottle.settings.name):\(appId)"
            case let .pin(pin, bottle): "pin:\(bottle.settings.name):\(pin.name)"
            }
        }
    }

    /// Targets the user chose to stop being asked about. Written only through
    /// ``rememberApproval(of:)``.
    static let approvedURLTargetsKey = "urlLaunchApprovedTargets"

    /// Handles a `whisky://` URL. Returns `false` for any other scheme so
    /// file opens keep flowing to `FileOpenView`.
    ///
    /// What a URL may say, and why there are only two forms, is
    /// ``WhiskyKit/WhiskyURL``. This handles what a well-formed one does.
    ///
    /// A URL cannot name an executable, so nothing arbitrary runs, but a page
    /// the user did not mean to visit can still start a game they own. So a URL
    /// arrival confirms once per target before launching, and the dialog offers
    /// to remember that target, which keeps a shortcut at one click after its
    /// first use. The Dock menu and the menu-bar extra do not confirm: the user
    /// is already in the app and already clicked the thing.
    static func handle(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == WhiskyURL.scheme else { return false }
        guard let request = WhiskyURL.parse(url) else {
            logger.error("Unrecognized whisky URL: \(url.absoluteString, privacy: .public)")
            return true
        }

        let resolved: Result<Target, String> = switch request {
        case let .steam(appId, bottle):
            resolveSteam(appId: appId, bottleName: bottle)
        case let .pin(name, bottle):
            resolvePin(named: name, bottleName: bottle)
        }

        switch resolved {
        case let .failure(reason):
            presentLaunchFailure(programName: url.absoluteString, error: reason)
        case let .success(target):
            guard confirmURLLaunch(of: target) else { return true }
            launch(target)
        }
        return true
    }

    /// Whether this target may run without asking, either because the user
    /// approved it before or because they approve it now.
    private static func confirmURLLaunch(of target: Target) -> Bool {
        let approved = UserDefaults.standard.stringArray(forKey: approvedURLTargetsKey) ?? []
        guard !approved.contains(target.consentKey) else { return true }

        let alert = NSAlert()
        alert.messageText = String(localized: "url.confirm.msg \(target.displayName)")
        alert.informativeText = String(localized: "url.confirm.info")
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "url.confirm.launch"))
        alert.addButton(withTitle: String(localized: "button.cancel"))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = String(localized: "url.confirm.remember")

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else {
            logger.info("URL launch declined for \(target.consentKey, privacy: .public)")
            return false
        }
        if alert.suppressionButton?.state == .on {
            rememberApproval(of: target)
        }
        return true
    }

    private static func rememberApproval(of target: Target) {
        var approved = UserDefaults.standard.stringArray(forKey: approvedURLTargetsKey) ?? []
        guard !approved.contains(target.consentKey) else { return }
        approved.append(target.consentKey)
        UserDefaults.standard.set(approved, forKey: approvedURLTargetsKey)
    }

    private static func launch(_ target: Target) {
        switch target {
        case let .steam(appId, bottle):
            do {
                _ = try SteamLauncher.launch(appId: appId, bottle: bottle)
            } catch {
                presentLaunchFailure(
                    programName: target.displayName, error: error.localizedDescription
                )
            }
        case let .pin(pin, bottle):
            launch(pin: pin, in: bottle)
        }
    }

    private static func resolveSteam(appId: Int, bottleName: String?) -> Result<Target, String> {
        let bottles = BottleVM.shared.bottles.filter(\.isAvailable)
        if let bottleName {
            guard let named = bottles.first(where: { $0.settings.name == bottleName }) else {
                return .failure(String(localized: "url.error.noBottle \(bottleName)"))
            }
            return .success(.steam(appId: appId, bottle: named))
        }
        do {
            return try .success(.steam(appId: appId, bottle: SteamLauncher.resolveBottle(
                appId: appId, in: bottles
            )))
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private static func resolvePin(named pinName: String, bottleName: String?) -> Result<Target, String> {
        let matches = availablePins().filter { entry in
            entry.pin.name.localizedCaseInsensitiveCompare(pinName) == .orderedSame
                && (bottleName == nil || entry.bottle.settings.name == bottleName)
        }
        guard let hit = matches.first else {
            return .failure(String(localized: "url.error.noPin"))
        }
        return .success(.pin(hit.pin, bottle: hit.bottle))
    }
}
