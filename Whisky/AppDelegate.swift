//
//  AppDelegate.swift
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
import os
import SwiftUI
import WhiskyKit

private let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "AppDelegate")

class AppDelegate: NSObject, NSApplicationDelegate {
    @AppStorage("hasShownMoveToApplicationsAlert") private var hasShownMoveToApplicationsAlert = false

    /// This run's record: whether it quit cleanly and which bottles it launched in.
    private let sessionStore = AppSessionStore()
    /// The previous run's record, read before this run's replaces it.
    private var previousSession: AppSessionRecord?
    private var launchSessionObserver: NSObjectProtocol?

    func application(_ application: NSApplication, open urls: [URL]) {
        // Test if automatic window tabbing is enabled
        // as it is disabled when ContentView appears
        if NSWindow.allowsAutomaticWindowTabbing, let url = urls.first {
            // Reopen the file after Whisky has been opened
            // so that the `onOpenURL` handler is actually called
            NSWorkspace.shared.open(url)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !hasShownMoveToApplicationsAlert, !AppDelegate.insideAppsFolder {
            DispatchQueue.main.asyncAfter(deadline: .now()) {
                NSApp.activate(ignoringOtherApps: true)
                self.showAlertOnFirstLaunch()
                self.hasShownMoveToApplicationsAlert = true
            }
        }

        // Background cleanup of orphaned temp files from previous sessions
        Task.detached {
            await TempFileTracker.shared.cleanupOldFiles(olderThan: 24 * 60 * 60)
        }

        previousSession = sessionStore.begin()
        let sessionStore = sessionStore
        launchSessionObserver = NotificationCenter.default.addObserver(
            forName: ProcessRegistry.didChangeNotification, object: nil, queue: .main
        ) { note in
            guard let bottleURL = note.userInfo?[ProcessRegistry.bottleURLKey] as? URL else { return }
            sessionStore.setLaunchSession(ProcessRegistry.shared.lastLaunch(for: bottleURL) != nil, for: bottleURL)
        }

        // Stop what a crashed or force-quit previous run left running
        Task {
            await self.sweepOrphanProcesses()
        }
    }

    /// The "Terminate Wine processes when Whisky closes" setting.
    ///
    /// Read as an optional: the Settings toggle is an `@AppStorage` that
    /// defaults to on without ever writing the key, and `bool(forKey:)`
    /// reports an absent key as off, which silently disabled kill-on-quit
    /// for anyone who never touched the toggle.
    static var killOnTerminate: Bool {
        UserDefaults.standard.object(forKey: "killOnTerminate") as? Bool ?? true
    }

    func applicationWillTerminate(_ notification: Notification) {
        let globalKill = Self.killOnTerminate

        // Per-bottle kill-on-quit with policy overrides
        for bottle in BottleVM.shared.bottles {
            let bottlePolicy = bottle.settings.killOnQuit
            if bottlePolicy.stopsOnQuit(globalKill: globalKill) {
                // Synchronous: the app exits when this delegate returns.
                Wine.killBottleAndWait(bottle: bottle)
                ProcessRegistry.shared.clearRegistry(for: bottle.url)
                logger.info(
                    "Killing bottle '\(bottle.settings.name)' on quit (policy: \(String(describing: bottlePolicy)))"
                )
            }
        }

        // Synchronous best-effort temp file cleanup (cannot await in applicationWillTerminate)
        let trackedFiles = TempFileTracker.shared.getAllTrackedFiles()
        for (fileURL, _) in trackedFiles {
            try? FileManager.default.removeItem(at: fileURL)
        }

        // Last: a run that dies before this point counts as not ended cleanly.
        sessionStore.endCleanly()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // When the user opts into the menu-bar extra, keep Whisky running after
        // the window closes so it stays reachable from the menu bar (and Wine
        // processes keep running). Otherwise quit on last window close, as usual.
        !UserDefaults.standard.bool(forKey: "showMenuBarExtra")
    }

    // MARK: - Dock Menu

    /// The pin behind a Dock menu item.
    private final class DockPin: NSObject {
        let bottleURL: URL
        let pinURL: URL

        init(bottleURL: URL, pinURL: URL) {
            self.bottleURL = bottleURL
            self.pinURL = pinURL
        }
    }

    /// Right-clicking Whisky in the Dock lists the pinned games, launchable
    /// without the main window.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let entries = QuickLaunch.availablePins()
        guard !entries.isEmpty else { return nil }

        let menu = NSMenu()
        let bottleCount = Set(entries.map(\.bottle.url)).count
        for entry in entries.prefix(10) {
            guard let pinURL = entry.pin.url else { continue }
            let title = bottleCount > 1
                ? "\(entry.pin.name) (\(entry.bottle.settings.name))"
                : entry.pin.name
            let item = NSMenuItem(
                title: title, action: #selector(launchDockPin(_:)), keyEquivalent: ""
            )
            item.target = self
            item.representedObject = DockPin(bottleURL: entry.bottle.url, pinURL: pinURL)
            menu.addItem(item)
        }
        return menu
    }

    @MainActor @objc private func launchDockPin(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? DockPin,
              let bottle = BottleVM.shared.bottles.first(where: { $0.url == ref.bottleURL }),
              let pin = bottle.settings.pins.first(where: { $0.url == ref.pinURL })
        else { return }
        QuickLaunch.launch(pin: pin, in: bottle)
    }

    private static var appUrl: URL? {
        Bundle.main.resourceURL?.deletingLastPathComponent().deletingLastPathComponent()
    }

    private static let expectedUrl = URL(fileURLWithPath: "/Applications/Whisky.app")

    private static var insideAppsFolder: Bool {
        if let url = appUrl {
            return url.path.contains("Xcode") || url.path.contains(expectedUrl.path)
        }
        return false
    }

    /// Stops what the previous run left running when it crashed or was force-quit.
    ///
    /// A clean quit stops the bottles its kill-on-quit policy covers; this does
    /// the same for a run that never got to quit, and only in bottles that run
    /// had launched something in. A wineserver nobody here started, such as a
    /// game started from the `whisky` command, a shortcut or a Terminal while
    /// Whisky was closed, keeps running; the sidebar offers to stop it.
    @MainActor
    private func sweepOrphanProcesses() async {
        guard let previousSession, !previousSession.endedCleanly else { return }
        await waitForBottles()

        var stoppedCount = 0
        for bottle in BottleVM.shared.bottles where previousSession.contains(bottle.url) {
            let wineserverRunning = await Wine.isWineserverRunning(for: bottle)
            let action = StartupOrphanSweep.action(
                for: bottle.url,
                wineserverRunning: wineserverRunning,
                stopsOnQuit: bottle.settings.killOnQuit.stopsOnQuit(globalKill: Self.killOnTerminate),
                previousSession: previousSession,
                launchedThisSession: ProcessRegistry.shared.lastLaunch(for: bottle.url) != nil
            )
            guard action == .stop else { continue }
            await Wine.terminateBottle(bottle)
            ProcessRegistry.shared.clearRegistry(for: bottle.url)
            stoppedCount += 1
            logger.info("Stopped bottle '\(bottle.settings.name)' left running by Whisky's last run")
        }

        if stoppedCount > 0 {
            NotificationCenter.default.post(name: .zombieProcessesCleaned, object: nil)
        }
    }

    /// Waits until the bottle list has loaded, at most ten seconds.
    @MainActor
    private func waitForBottles() async {
        var waits = 0
        while !BottleVM.shared.hasLoadedBottles, waits < 40 {
            try? await Task.sleep(for: .milliseconds(250))
            waits += 1
        }
    }

    @MainActor
    private func showAlertOnFirstLaunch() {
        let alert = NSAlert()
        alert.messageText = String(localized: "showAlertOnFirstLaunch.messageText")
        alert.informativeText = String(localized: "showAlertOnFirstLaunch.informativeText")
        alert.addButton(withTitle: String(localized: "showAlertOnFirstLaunch.button.moveToApplications"))
        alert.addButton(withTitle: String(localized: "showAlertOnFirstLaunch.button.dontMove"))

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            let appURL = Bundle.main.bundleURL

            do {
                _ = try FileManager.default.replaceItemAt(AppDelegate.expectedUrl, withItemAt: appURL)
                NSWorkspace.shared.open(AppDelegate.expectedUrl)
            } catch {
                logger.error("Failed to move the app: \(error.localizedDescription)")
            }
        }
    }
}

extension Notification.Name {
    /// Posted when bottles the previous run left running have been stopped at
    /// launch. The sidebar re-checks its bottles on it.
    static let zombieProcessesCleaned = Notification.Name("zombieProcessesCleaned")
}
