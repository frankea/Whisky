//
//  StartMenuShortcutSync.swift
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

/// Pins the programs that installers add shortcuts for in a bottle's Start
/// Menu and Desktop folders.
///
/// Each shortcut is handled once and recorded in ``HandledShortcuts``; the
/// `.lnk` files themselves are left alone. A shortcut is recorded only after
/// it parses and its target exists, so one an installer is still writing, or
/// one whose program isn't extracted yet, is tried again on the next scan.
@MainActor
public enum StartMenuShortcutSync {
    /// A shortcut that should pin its program.
    private struct Candidate {
        /// The URL to pin: the scanned program's own URL when the bottle scan
        /// found the target, the shortcut's target otherwise.
        let url: URL
        /// The shortcut's name, used for a pin the scan didn't find.
        let name: String
        /// The program from the bottle scan, if it found the target.
        let scanned: Program?
    }

    /// Pins the programs of every shortcut in `bottle` not handled before.
    ///
    /// A target the bottle scan found (under Program Files) is pinned in place,
    /// matching paths case-insensitively like Windows does. Anything else, such
    /// as a launcher installed under AppData or `C:\Games`, gets a new pin.
    /// Programs already pinned, or unpinned by the user, are left alone (see
    /// ``BottleSettings/startMenuPinsToAdd(candidates:)``).
    ///
    /// - Parameters:
    ///   - bottle: The bottle to scan. Its ``Bottle/programs`` should be loaded.
    ///   - wineUsername: The bottle's Wine user, whose Start Menu and Desktop
    ///     are read alongside the shared ones.
    /// - Returns: Whether pins were added for programs the bottle's program
    ///   list doesn't show yet, so the caller should rescan it.
    @discardableResult
    public static func sync(bottle: Bottle, wineUsername: String) -> Bool {
        let driveC = bottle.url.appending(path: "drive_c")
        let handled = HandledShortcuts.load(from: bottle.url)
        var updated = handled
        var seenTargets: Set<String> = []
        var candidates: [Candidate] = []

        for link in WindowsShortcuts.findShortcuts(driveC: driveC, wineUsername: wineUsername)
            where !handled.contains(link, driveC: driveC) {
            guard let target = targetURL(of: link, bottle: bottle) else { continue }
            let targetPath = target.path(percentEncoded: false)
            guard FileManager.default.fileExists(atPath: targetPath) else { continue }
            updated.insert(link, driveC: driveC)

            let name = link.deletingPathExtension().lastPathComponent
            guard WindowsShortcuts.isProgramShortcut(name: name, targetPath: targetPath),
                  seenTargets.insert(targetPath.lowercased()).inserted
            else { continue }

            let scanned = bottle.programs.first {
                $0.url.path(percentEncoded: false).caseInsensitiveCompare(targetPath) == .orderedSame
            }
            candidates.append(Candidate(url: scanned?.url ?? target, name: name, scanned: scanned))
        }

        let toPin = Set(bottle.settings.startMenuPinsToAdd(candidates: candidates.map(\.url)))
        var pinnedOutsideScan = false
        for candidate in candidates where toPin.contains(candidate.url) {
            if let scanned = candidate.scanned {
                // `pinned`'s setter writes the pin entry.
                scanned.pinned = true
            } else {
                bottle.settings.pins.append(PinnedProgram(name: candidate.name, url: candidate.url))
                pinnedOutsideScan = true
            }
        }

        if updated != handled {
            do {
                try updated.save(to: bottle.url)
            } catch {
                Logger.wineKit.error("Failed to save handled shortcuts: \(error.localizedDescription)")
            }
        }
        return pinnedOutsideScan
    }

    /// The executable a `.lnk` file points at, or `nil` if it can't be read.
    private static func targetURL(of link: URL, bottle: Bottle) -> URL? {
        do {
            let handle = try FileHandle(forReadingFrom: link)
            defer { try? handle.close() }
            return ShellLinkHeader.getProgram(url: link, handle: handle, bottle: bottle)?.url
        } catch {
            Logger.wineKit.warning("Failed to read shortcut \(link.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }
}
