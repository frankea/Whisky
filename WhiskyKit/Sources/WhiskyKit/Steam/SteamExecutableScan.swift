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

/// What a scan of a game's install folder found.
struct SteamExecutableScan: Equatable {
    /// Every executable found, shallowest first.
    var executables: [URL] = []

    /// The executables below the first folder level that ship a Chromium UI
    /// (`libcef.dll` or Qt WebEngine beside them), such as 3DMark's front end.
    /// They are in ``executables`` too.
    var chromiumHosts: [URL] = []

    /// The executables from the ``ChromiumFrontEnd`` table, at any depth.
    var frontEnds: [URL] {
        executables.filter { ChromiumFrontEnd.match(url: $0) != nil }
    }

    /// The Electron and NW.js apps among the executables, found by their files
    /// (``ChromiumRuntimeDetector``). Reads each one's folder the first time.
    var chromiumRuntimes: [URL] {
        executables.filter { ChromiumRuntimeDetector.detect(executable: $0) != nil }
    }

    /// The executables the game's plan goes to: all of them but the Chromium
    /// hosts and the table's front ends. A host keeps its own settings: the
    /// plan is the game's, and the workloads beside it run on a backend
    /// Chromium cannot draw on (#372).
    ///
    /// An Electron or NW.js app stays among them: it is often the game itself
    /// (an RPG Maker `Game.exe`), so its settings still shape the plan.
    var planExecutables: [URL] {
        let hosts = Set(chromiumHosts + frontEnds)
        return executables.filter { !hosts.contains($0) }
    }

    /// The executables a launch leaves on their own settings: the Chromium
    /// hosts, then the table's front ends the scan did not count as hosts,
    /// then the Electron and NW.js apps. Under Recommended a front end or an
    /// app among them gets DXVK's set instead
    /// (``Wine/addFrontEndScopes(_:to:bottle:recommendedBackend:launcherSet:)``),
    /// as it does when the Programs tab starts it.
    var ownSettingsExecutables: [URL] {
        var seen = Set<URL>()
        return (chromiumHosts + frontEnds + chromiumRuntimes).filter { seen.insert($0).inserted }
    }
}

/// How much of a game's install folder the scan reads below the first folder level.
struct SteamExecutableScanLimits: Equatable {
    /// Directory entries the scan reads in all before it stops.
    var entryBudget: Int
    /// Entries past which a folder counts as data and is left unread.
    var folderEntryLimit: Int
    /// Executables the scan returns.
    var resultLimit: Int

    static let standard = SteamExecutableScanLimits(
        entryBudget: SteamLibrary.deepScanEntryBudget,
        folderEntryLimit: SteamLibrary.deepScanFolderEntryLimit,
        resultLimit: SteamLibrary.deepScanResultLimit
    )
}

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
    /// in all. A typical Unreal install needs a few hundred, and a game
    /// shipping loose files cannot turn a Play press on the main actor into a
    /// walk of its whole tree.
    static let deepScanEntryBudget = 5_000

    /// How many entries a folder below the first level can hold and still be
    /// read. A binaries folder holds tens; one with thousands is data, and the
    /// scan stops reading it there instead of listing it in full.
    static let deepScanFolderEntryLimit = 2_000

    /// How many executables the scan returns from below the first folder
    /// level, shallowest first.
    static let deepScanResultLimit = 64

    /// Folders the scan never descends into below the install folder:
    /// redistributables and installers, anti-cheat installers, third-party
    /// runtimes (bundled Java among them, whose generic `java.exe` would tie
    /// every game shipping one to every other), and the big data trees no
    /// game executable lives in. Compared lowercased.
    static let skippedFolderNames: Set<String> = [
        "_commonredist", "commonredist", "redist", "redists", "redistributable", "redistributables",
        "directx", "dxsetup", "vcredist", "vc_redist", "dotnet", "dotnetfx", "netfx",
        "installer", "installers", "__installer", "install", "setup", "uninstall",
        "support", "prerequisites", "prereqs", "prereq",
        "thirdparty", "third_party", "extras", "physx",
        "jre", "jre32", "jre64", "jdk", "java", "jvm",
        "easyanticheat", "battleye",
        "crashreporter", "crashreportclient",
        "content", "paks", "movies", "saved", "logs", "localization", "shadercache"
    ]

    /// Folders read first at each level, so a big tree that sorts ahead of
    /// them cannot spend the entry budget before the game's binaries are
    /// reached. Compared lowercased.
    static let binaryFolderNames: Set<String> = [
        "binaries", "bin", "bin32", "bin64", "win32", "win64", "x64", "x86", "x86_64"
    ]

    /// Name fragments of executables below the first folder level that are
    /// never the game: crash reporters, Chromium helpers, installers and
    /// launchers. Compared lowercased.
    static let auxiliaryExecutableMarkers = [
        "crashreport", "crashhandler", "crashpad", "crashsender", "bugsplat",
        "cefsubprocess", "browsersubprocess", "webhelper", "qtwebengineprocess", "msedgewebview",
        "redist", "prereq", "setup", "dotnetfx", "bootstrappackagedgame",
        "launcher"
    ]

    /// Runtime executables below the first folder level whose names are the
    /// same in every game that bundles them. Compared lowercased.
    static let auxiliaryExecutableNames: Set<String> = ["java.exe", "javaw.exe", "javaws.exe"]

    /// Libraries whose presence in a folder marks it as shipping a Chromium UI.
    /// Compared lowercased.
    static let chromiumLibraryNames: Set<String> = ["libcef.dll", "qt5webenginecore.dll", "qt6webenginecore.dll"]

    /// Further name fragments that mark a Chromium helper in a folder that
    /// ships Chromium. The executable hosting the browser keeps its place:
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
    /// on D3DMetal), redistributables and installers, bundled runtimes,
    /// Unreal's engine tree except its `Binaries`, and anything behind a
    /// symbolic link. It reads no further than ``executableScanDepth``, and
    /// within ``deepScanEntryBudget`` and ``deepScanFolderEntryLimit``.
    ///
    /// The root and the first folder level are listed as they always were,
    /// whatever they hold, so nothing an existing install relied on changes.
    ///
    /// The order is fixed: shallowest first; within a level, the folders
    /// named like binary folders (``binaryFolderNames``) first, then the rest,
    /// each folder's entries by name.
    public static func executableURLs(under installURL: URL) -> [URL] {
        scanExecutables(under: installURL).executables
    }

    /// ``executableURLs(under:)``, with the Chromium hosts among them told apart.
    static func scanExecutables(
        under installURL: URL, limits: SteamExecutableScanLimits = .standard
    ) -> SteamExecutableScan {
        var scan = SteamExecutableScan()
        let root = listing(of: installURL)
        scan.executables = root.executables

        var frontier: [URL] = []
        for folder in root.folders {
            let firstLevel = listing(of: folder)
            scan.executables.append(contentsOf: firstLevel.executables)
            guard !skipsDescent(into: folder.lastPathComponent, parentName: nil) else { continue }
            frontier.append(contentsOf: firstLevel.folders.filter { !isSymbolicLink($0) })
        }

        collectDeepExecutables(startingAt: frontier, limits: limits, into: &scan)
        return scan
    }

    /// The game executables from the second folder level down to
    /// ``executableScanDepth``, breadth first.
    private static func collectDeepExecutables(
        startingAt secondLevel: [URL], limits: SteamExecutableScanLimits, into scan: inout SteamExecutableScan
    ) {
        var budget = limits.entryBudget
        var found = 0
        var frontier = binaryFoldersFirst(secondLevel.filter { !skipsDescent(into: $0) })
        var depth = 2

        while !frontier.isEmpty, depth <= executableScanDepth {
            var next: [URL] = []
            for folder in frontier {
                guard budget > 0 else { return }
                let (listing, read) = deepListing(of: folder, limit: min(limits.folderEntryLimit, budget))
                budget -= read
                // Too big to be a binaries folder, or past what is left of the budget.
                guard let listing else { continue }

                for item in listing.executables
                    where isGameExecutable(item.lastPathComponent, besideChromium: listing.shipsChromium) {
                    scan.executables.append(item)
                    if listing.shipsChromium {
                        scan.chromiumHosts.append(item)
                    }
                    found += 1
                    if found == limits.resultLimit { return }
                }
                if depth < executableScanDepth {
                    next.append(contentsOf: listing.folders.filter { !skipsDescent(into: $0) })
                }
            }
            frontier = binaryFoldersFirst(next)
            depth += 1
        }
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
        if lowercased.hasPrefix("unins") || auxiliaryExecutableNames.contains(lowercased)
            || auxiliaryExecutableMarkers.contains(where: { lowercased.contains($0) }) {
            return false
        }
        return !besideChromium || !chromiumHelperMarkers.contains { lowercased.contains($0) }
    }

    /// The folders named like binary folders first, each group in its own order.
    private static func binaryFoldersFirst(_ folders: [URL]) -> [URL] {
        let isBinary = { (folder: URL) in binaryFolderNames.contains(folder.lastPathComponent.lowercased()) }
        return folders.filter(isBinary) + folders.filter { !isBinary($0) }
    }

    /// What one folder holds that the scan uses: its executables and its
    /// folders, each by name. Nothing else is sorted or kept, so a folder of
    /// loose files costs its listing and no more.
    private struct Listing {
        var executables: [URL] = []
        var folders: [URL] = []
        var shipsChromium = false
    }

    private static let listingKeys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey]

    /// The root or a first-level folder, listed in full the way the scan always
    /// listed them: an executable by its extension alone.
    private static func listing(of folder: URL) -> Listing {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: listingKeys
        )) ?? []
        var listing = Listing()
        for item in items {
            if isExecutable(item) {
                listing.executables.append(item)
            } else if isDirectory(item) {
                listing.folders.append(item)
            }
        }
        listing.executables = sortedByName(listing.executables)
        listing.folders = sortedByName(listing.folders)
        return listing
    }

    /// A folder below the first level, read up to `limit` entries: no symbolic
    /// links, and `nil` when it holds more, along with how many were read.
    private static func deepListing(of folder: URL, limit: Int) -> (listing: Listing?, read: Int) {
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: listingKeys, options: [.skipsSubdirectoryDescendants]
        )
        else { return (nil, 0) }

        var listing = Listing()
        var read = 0
        for case let item as URL in enumerator {
            read += 1
            if read > limit { return (nil, read) }
            let name = item.lastPathComponent.lowercased()
            if chromiumLibraryNames.contains(name) {
                listing.shipsChromium = true
            }
            if isExecutable(item) {
                if isRegularFile(item), !isSymbolicLink(item) {
                    listing.executables.append(item)
                }
            } else if isDirectory(item), !isSymbolicLink(item) {
                listing.folders.append(item)
            }
        }
        listing.executables = sortedByName(listing.executables)
        listing.folders = sortedByName(listing.folders)
        return (listing, read)
    }

    /// URLs by file name, each name computed once.
    private static func sortedByName(_ urls: [URL]) -> [URL] {
        urls.map { ($0.lastPathComponent, $0) }.sorted { $0.0 < $1.0 }.map(\.1)
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
