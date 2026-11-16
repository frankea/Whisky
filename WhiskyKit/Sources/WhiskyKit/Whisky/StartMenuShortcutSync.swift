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
/// A shortcut that disappears is dropped from the record.
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
    /// Programs already pinned, unpinned by the user or blocklisted are left
    /// alone (see ``BottleSettings/startMenuPinsToAdd(candidates:)``).
    ///
    /// A bottle without a record was last opened by a version that deleted
    /// each Start Menu shortcut once it pinned the program, and that recorded
    /// no unpins. Its first scan records the shortcuts to programs the bottle
    /// scan found without pinning them: those programs were already in the
    /// list, and one that isn't pinned may have been unpinned on purpose.
    /// Targets outside the scan are still pinned. A new bottle starts with an
    /// empty record (``HandledShortcuts/startRecord(in:)``), so its first
    /// install is pinned as usual.
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
        let firstScan = !HandledShortcuts.exists(in: bottle.url)
        let handled = HandledShortcuts.load(from: bottle.url)
        let links = WindowsShortcuts.findShortcuts(driveC: driveC, wineUsername: wineUsername)
        // Forget shortcuts that are gone: a reinstall that writes one again
        // gets its program pinned again, as after a first install.
        var updated = handled.keeping(links, driveC: driveC)
        let candidates = newCandidates(
            from: links.filter { !handled.contains($0, driveC: driveC) },
            bottle: bottle,
            record: &updated
        )
        let pinnedOutsideScan = pin(firstScan ? candidates.filter { $0.scanned == nil } : candidates, in: bottle)

        if firstScan || updated != handled {
            do {
                try updated.save(to: bottle.url)
            } catch {
                Logger.wineKit.error("Failed to save handled shortcuts: \(error.localizedDescription)")
            }
        }
        return pinnedOutsideScan
    }

    /// The programs `links` stand for, each recorded in `record` once it
    /// parses and its target exists.
    private static func newCandidates(
        from links: [URL],
        bottle: Bottle,
        record: inout HandledShortcuts
    ) -> [Candidate] {
        let driveC = bottle.url.appending(path: "drive_c")
        var seenTargets: Set<String> = []
        var candidates: [Candidate] = []

        for link in links {
            guard let target = targetURL(of: link, bottle: bottle) else { continue }
            let targetPath = target.path(percentEncoded: false)
            guard FileManager.default.fileExists(atPath: targetPath) else { continue }
            record.insert(link, driveC: driveC)

            let name = link.deletingPathExtension().lastPathComponent
            guard WindowsShortcuts.isProgramShortcut(name: name, targetPath: targetPath),
                  seenTargets.insert(targetPath.lowercased()).inserted
            else { continue }

            let scanned = bottle.programs.first {
                $0.url.path(percentEncoded: false).caseInsensitiveCompare(targetPath) == .orderedSame
            }
            candidates.append(Candidate(url: scanned?.url ?? target, name: name, scanned: scanned))
        }
        return candidates
    }

    /// Pins the `candidates` that ``BottleSettings/startMenuPinsToAdd(candidates:)``
    /// lets through.
    ///
    /// - Returns: Whether any pin is for a program the bottle scan didn't find.
    private static func pin(_ candidates: [Candidate], in bottle: Bottle) -> Bool {
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
