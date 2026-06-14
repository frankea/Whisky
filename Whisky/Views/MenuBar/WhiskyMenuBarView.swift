//
//  WhiskyMenuBarView.swift
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

import os.log
import SwiftUI
import WhiskyKit

/// Content for the optional menu-bar extra (whisky-app/whisky#571).
///
/// Lets the user reopen Whisky, launch a bottle's pinned programs, and quit
/// without the main window focused — and, paired with the "stay running"
/// lifecycle, after the window has been closed entirely.
struct WhiskyMenuBarView: View {
    @EnvironmentObject private var bottleVM: BottleVM
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("menubar.open") {
            openMainWindow()
        }
        SettingsLink()

        let bottles = bottleVM.bottles.filter(\.isAvailable)
        Divider()
        if bottles.isEmpty {
            Text("menubar.empty")
        } else {
            ForEach(bottles) { bottle in
                bottleMenu(bottle)
            }
        }

        Divider()
        Button("kill.bottles") {
            WhiskyApp.killBottles()
        }
        Button("menubar.quit") {
            NSApplication.shared.terminate(nil)
        }
    }

    /// Submenu of a bottle's pinned programs, each launchable directly.
    ///
    /// Reads `settings.pins` directly rather than `bottle.pinnedPrograms`: the
    /// latter resolves pins against `bottle.programs`, which stays empty until a
    /// bottle view scans it. On a fresh launch (no bottle ever opened) that would
    /// make every bottle wrongly report "no pinned programs". Pins live in
    /// settings and are always loaded, so they're the right source here.
    private func bottleMenu(_ bottle: Bottle) -> some View {
        Menu(bottle.settings.name) {
            let pins = bottle.settings.pins.filter { pin in
                guard let path = pin.url?.path(percentEncoded: false) else { return false }
                return FileManager.default.fileExists(atPath: path)
            }
            if pins.isEmpty {
                Text("menubar.bottle.noPins")
            } else {
                ForEach(pins, id: \.url) { pin in
                    Button(pin.name) { launch(pin, in: bottle) }
                }
            }
        }
    }

    /// Launches a pinned program, surfacing failures the user would otherwise
    /// never see.
    ///
    /// The `Program` is built from the pin so this doesn't depend on a prior
    /// bottle scan. Failures are reported via an `NSAlert` rather than a view
    /// toast because the menu-bar extra can be the app's only surface (the main
    /// window may be closed), so there's no toast presenter to reach.
    @MainActor
    private func launch(_ pin: PinnedProgram, in bottle: Bottle) {
        guard let url = pin.url else { return }
        let program = Program(url: url, bottle: bottle)
        Task {
            let result = await program.launchWithUserMode(useTerminal: false)
            guard case let .launchFailed(_, errorDescription) = result else { return }
            Logger.wineKit.error(
                "Menu-bar launch failed for \(pin.name, privacy: .public): \(errorDescription, privacy: .public)"
            )
            presentLaunchFailure(programName: pin.name, error: errorDescription)
        }
    }

    @MainActor
    private func presentLaunchFailure(programName: String, error: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "menubar.launchFailed \(programName)")
        alert.informativeText = error
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "button.ok"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    /// Brings an existing Whisky window forward, or opens a fresh one when the
    /// window was closed while the app stayed running in the menu bar.
    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        // Match only windows from the main WindowGroup (identifier
        // "main-AppWindow-N"). The Settings window also `canBecomeMain`, so the
        // old predicate could bring *it* forward — or, when Settings was the only
        // open window, leave the main window unopened — on "Open Whisky".
        if let window = NSApp.windows.first(where: {
            $0.identifier?.rawValue.hasPrefix(WhiskyApp.mainWindowID) == true && $0.canBecomeMain
        }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: WhiskyApp.mainWindowID)
        }
    }
}
