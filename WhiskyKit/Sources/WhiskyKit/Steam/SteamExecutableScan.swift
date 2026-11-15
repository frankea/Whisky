//
//  SteamExecutableScan.swift
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

extension SteamLibrary {
    /// The deepest folder, counted from the install folder (0), whose
    /// executables the scan collects.
    ///
    /// Unreal Engine games keep the real executable at
    /// `<Project>\Binaries\Win64\<Project>-Win64-Shipping.exe`, which is three
    /// folders down, with only a bootstrap stub at the root. Source and
    /// 3DMark-style layouts (`bin\x64`) are two down. One more level covers a
    /// publisher wrapping either layout in a folder of its own, and stops
    /// short of plugin trees (`<Project>\Plugins\<Name>\Binaries\Win64`), whose
    /// executables are tools, not the game.
    static let executableScanDepth = 4

    /// How many directory entries the scan reads below the first folder level
    /// before it stops descending. A typical Unreal install needs a few
    /// hundred, and a game shipping loose files cannot turn a Play press on
    /// the main actor into a walk of its whole tree.
    static let deepScanEntryBudget = 5_000

    /// How many executables the scan returns from below the first folder
    /// level, shallowest first.
    static let deepScanResultLimit = 64

    /// Folders the scan never descends into below the install folder:
    /// redistributables and installers, anti-cheat installers, third-party
    /// runtimes, and the big data trees no game executable lives in.
    /// Compared lowercased.
    static let skippedFolderNames: Set<String> = [
        "_commonredist", "commonredist", "redist", "redists", "redistributable", "redistributables",
        "directx", "dxsetup", "vcredist", "vc_redist", "dotnet", "dotnetfx", "netfx",
        "installer", "installers", "__installer", "install", "setup", "uninstall",
        "support", "prerequisites", "prereqs", "prereq",
        "thirdparty", "third_party", "extras", "physx",
        "easyanticheat", "battleye",
        "crashreporter", "crashreportclient",
        "content", "paks", "movies", "saved", "logs", "localization", "shadercache"
    ]

    /// Name fragments of executables below the first folder level that are
    /// never the game: crash reporters, Chromium helpers, installers and
    /// launchers. Compared lowercased.
    static let auxiliaryExecutableMarkers = [
        "crashreport", "crashhandler", "crashpad", "crashsender", "bugsplat",
        "cefsubprocess", "browsersubprocess", "webhelper",
        "redist", "prereq", "setup", "dotnetfx", "bootstrappackagedgame",
        "launcher"
    ]

    /// Further name fragments that mark a Chromium helper in a folder that
    /// ships `libcef.dll`. The executable hosting the browser keeps its place:
    /// it can be the program itself, whose settings must still reach it.
    static let chromiumHelperMarkers = ["helper", "subprocess", "renderer", "browser", "cef", "webview"]

    /// The executables of a game: every one at the install root and in each
    /// folder directly below it, then the game executables further down.
    ///
    /// Everything a Steam launch writes for the game is keyed on this list: the
    /// game's DLL overrides go into these executables' `AppDefaults` entries,
    /// the user's per-program settings are read from them, and the library
    /// watches for them in the process list. So below the first folder level
    /// the scan leaves out what must not get the game's overrides or pass for
    /// the game running: crash reporters, Chromium helpers (CEF draws nothing
    /// on D3DMetal), redistributables and installers, Unreal's engine tree
    /// except its `Binaries`, and anything behind a symbolic link. It reads no
    /// further than ``executableScanDepth`` and ``deepScanEntryBudget``.
    ///
    /// The root and the first folder level are listed as they always were,
    /// whatever they hold, so nothing an existing install relied on changes.
    ///
    /// The order is fixed: shallowest first, each folder's entries by name.
    public static func executableURLs(under installURL: URL) -> [URL] {
        var executables: [URL] = []
        var firstLevel: [URL] = []

        for item in sortedContents(of: installURL) {
            if isExecutable(item) {
                executables.append(item)
            } else if isDirectory(item) {
                firstLevel.append(item)
            }
        }

        var frontier: [URL] = []
        for folder in firstLevel {
            let items = sortedContents(of: folder)
            executables.append(contentsOf: items.filter(isExecutable))
            guard !skipsDescent(into: folder.lastPathComponent, parentName: nil) else { continue }
            frontier.append(contentsOf: items.filter { isDirectory($0) && !isSymbolicLink($0) })
        }

        executables.append(contentsOf: deepExecutables(startingAt: frontier))
        return executables
    }

    /// The game executables from the second folder level down to
    /// ``executableScanDepth``, breadth first.
    private static func deepExecutables(startingAt secondLevel: [URL]) -> [URL] {
        var found: [URL] = []
        var budget = deepScanEntryBudget
        var frontier = secondLevel.filter { !skipsDescent(into: $0) }
        var depth = 2

        while !frontier.isEmpty, depth <= executableScanDepth {
            var next: [URL] = []
            for folder in frontier {
                guard budget > 0 else { return found }
                let items = sortedContents(of: folder)
                budget -= items.count
                let shipsChromium = items.contains { $0.lastPathComponent.lowercased() == "libcef.dll" }

                for item in items where !isSymbolicLink(item) {
                    if isDirectory(item) {
                        if depth < executableScanDepth, !skipsDescent(into: item) {
                            next.append(item)
                        }
                    } else if isExecutable(item), isRegularFile(item),
                              isGameExecutable(item.lastPathComponent, besideChromium: shipsChromium) {
                        found.append(item)
                        if found.count == deepScanResultLimit { return found }
                    }
                }
            }
            frontier = next
            depth += 1
        }
        return found
    }

    /// Whether the scan leaves a folder below the first level unread.
    private static func skipsDescent(into folder: URL) -> Bool {
        skipsDescent(
            into: folder.lastPathComponent,
            parentName: folder.deletingLastPathComponent().lastPathComponent
        )
    }

    /// Whether the scan leaves a folder's subfolders unread, by its name and
    /// its parent's.
    ///
    /// Unity's `<Game>_Data` holds assets only. In Unreal's `Engine` folder
    /// only `Binaries` can hold executables a game ships, and those are the
    /// engine's helpers, which ``isGameExecutable(_:besideChromium:)`` sets
    /// aside; the rest of it is content, plugins and third-party runtimes.
    static func skipsDescent(into name: String, parentName: String?) -> Bool {
        let lowercased = name.lowercased()
        if skippedFolderNames.contains(lowercased) || lowercased.hasSuffix("_data") {
            return true
        }
        return parentName?.lowercased() == "engine" && lowercased != "binaries"
    }

    /// Whether an executable below the first folder level can be the game.
    static func isGameExecutable(_ name: String, besideChromium: Bool) -> Bool {
        let lowercased = name.lowercased()
        if lowercased.hasPrefix("unins") || auxiliaryExecutableMarkers.contains(where: { lowercased.contains($0) }) {
            return false
        }
        return !besideChromium || !chromiumHelperMarkers.contains { lowercased.contains($0) }
    }

    /// A folder's entries sorted by name, so every scan sees them in the same order.
    private static func sortedContents(of folder: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey]
        )) ?? []
        return items.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func isExecutable(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "exe"
    }

    /// A real folder: a symbolic link to one reads as not a directory.
    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private static func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }
}
