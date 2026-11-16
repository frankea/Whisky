//
//  RockstarD3DConsumers.swift
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

/// A folder that gets DXVK's `d3d11.dll` and `d3d10core.dll` beside the
/// process that loads them, while `system32` holds Wine's `d3d11`.
struct RockstarD3DCopyFolder: Equatable {
    /// The folder.
    let url: URL
    /// Its path relative to the bottle's `drive_c`.
    let key: String
    /// The folders to create first, parent first, as keys relative to
    /// `drive_c`: Social Club's before Rockstar's installer makes it.
    let create: [String]
}

/// Who in a bottle would load `system32\d3d11.dll` native first, and what the
/// swapped layout can do for each.
struct RockstarD3DConsumerScan: Equatable {
    /// Folders a DXVK copy serves, without duplicates, in the order found.
    var copyFolders: [RockstarD3DCopyFolder] = []
    /// Installed library games whose plan is DXVK, by name.
    var dxvkPlanGames: [String] = []
    /// What no copy can serve: executable names, or folders relative to `drive_c`.
    var unserved: [String] = []
}

extension Wine {
    /// The DXVK files a copy folder gets. Never `dxgi.dll`: DXVK-macOS ships
    /// none, and `system32` already holds Wine's own beside DXVK's `d3d11`.
    static let rockstarD3DCopyDLLs = ["d3d11.dll", "d3d10core.dll"]

    /// The processes of a bottle that the swapped layout would move off DXVK,
    /// and where a copy can keep them on it.
    ///
    /// Only a process that asks for `d3d11` native first is affected, and
    /// only when its own folder has no `d3d11.dll`: Wine's loader searches the
    /// application's folder before `system32`, and a process without an
    /// override loads a system-directory DLL builtin first, which is GPTK's
    /// forwarder whatever `system32` holds. So only the processes Whisky gives
    /// a native-first `d3d11` have to be found:
    ///
    /// 1. Steam's Chromium GPU process, in each `bin/cef` folder whose
    ///    `steamwebhelper.exe` is 64-bit. The 32-bit `cef.win7` loads
    ///    `syswow64`, which keeps DXVK, so its machine decides, not its name.
    /// 2. Steam's overlay, `gameoverlayui64.exe` in the Steam root, which gets
    ///    Steam's helper entry. `steam.exe` beside it loads no `d3d11`.
    /// 3. `SocialClubHelper.exe`, always, in `Program Files/Rockstar Games/Social Club`.
    ///    The launcher installs Social Club on its first start, so the folder
    ///    is created ahead of it with the copies in it: Rockstar's installer
    ///    leaves them in place, and the first sign-in is not blank.
    /// 4. Chromium front ends and hosts a launch gives DXVK: the table's and
    ///    Electron or NW.js apps that Recommended steers, and Chromium hosts in
    ///    library games whose own override is DXVK.
    ///
    /// A front end or host whose folder cannot take a copy (outside `drive_c`,
    /// a game's folder, a folder holding DXMT's copies, Rockstar's launcher
    /// folder) is unserved, and so is any folder that already holds a
    /// `d3d11.dll` or `d3d10core.dll` that is not DXVK's: a program that ships
    /// its own Direct3D is left to it. Library games on DXVK and the other
    /// launchers' processes with a native-first `AppDefaults` entry cannot be
    /// served either, and are reported for the resolver to refuse the swap.
    ///
    /// - Parameters:
    ///   - bottle: The bottle.
    ///   - recommendedBackend: What `.recommended` resolves to for its games.
    ///   - dxvkFolder: The DXVK payload, whose bytes count as DXVK's.
    ///   - record: The bottle's swap record, whose copies count as DXVK's too.
    @MainActor
    static func rockstarD3DConsumers(
        bottle: Bottle, recommendedBackend: GraphicsBackend, dxvkFolder: URL, record: RockstarD3DLayoutRecord?
    ) -> RockstarD3DConsumerScan {
        let steamRoot = SteamLibrary.detectInstall(bottleURL: bottle.url)
        let library = rockstarLibraryPass(bottle: bottle, recommendedBackend: recommendedBackend)
        var scan = RockstarD3DConsumerScan(dxvkPlanGames: library.dxvkPlanGames)

        var candidates = steamCopyFolders(steamRoot: steamRoot, bottleURL: bottle.url, unserved: &scan.unserved)
        if let socialClub = socialClubCopyFolder(bottleURL: bottle.url) {
            candidates.append(socialClub)
        } else {
            scan.unserved.append(socialClubKey)
        }
        let excluded = library.planFolderKeys.union(DXMTGameFolderRecord.load(from: bottle.url).folderKeys.map {
            $0.lowercased()
        })
        candidates += frontEndCopyFolders(
            frontEndExecutables(bottleURL: bottle.url, steamRoot: steamRoot) + library.hosts,
            bottle: bottle, recommendedBackend: recommendedBackend, excluded: excluded, unserved: &scan.unserved
        )
        scan.unserved += otherLauncherConsumers(bottleURL: bottle.url)

        let payload = rockstarPayloadHashes(dxvkFolder)
        var seen = Set<String>()
        for folder in candidates where seen.insert(folder.key.lowercased()).inserted {
            if isUnderRockstarLauncher(folder.key) {
                Logger.wineKit.warning("Never placing DXVK copies under Rockstar's launcher folder")
                scan.unserved.append(folder.key)
            } else if holdsForeignD3D(folder, payload: payload, record: record) {
                Logger.wineKit.info("A folder ships its own Direct3D, so the Rockstar swap cannot serve it")
                scan.unserved.append(folder.key)
            } else {
                scan.copyFolders.append(folder)
            }
        }
        var unique = Set<String>()
        scan.unserved = scan.unserved.filter { unique.insert($0.lowercased()).inserted }
        return scan
    }

    /// The SHA-256 of each of ``rockstarD3DCopyDLLs`` in the DXVK payload's
    /// `x64` folder, by name; a file that cannot be read is left out.
    static func rockstarPayloadHashes(_ dxvkFolder: URL) -> [String: String] {
        var hashes: [String: String] = [:]
        for dll in rockstarD3DCopyDLLs {
            hashes[dll] = RockstarD3DLayoutRecord.sha256(of: dxvkFolder.appending(path: "x64").appending(path: dll))
        }
        return hashes
    }

    // MARK: - Library games

    /// What one pass over the bottle's Steam library finds, each game scanned once.
    private struct RockstarLibraryPass {
        var dxvkPlanGames: [String] = []
        /// The folders of the games' plan executables, lowercased keys.
        var planFolderKeys: Set<String> = []
        /// The executables the games leave on their own settings.
        var hosts: [URL] = []
    }

    /// Scans each installed library game once: its plan executables' folders,
    /// which never get copies, its Chromium hosts and front ends, and whether
    /// its plan, the one `-applaunch` would resolve, loads `d3d11` native
    /// first: DXVK, or overrides that ask for it
    /// (``rockstarProgramUsesNativeD3D11(_:bottle:recommendedBackend:dxmtIsServed:)``).
    @MainActor
    private static func rockstarLibraryPass(
        bottle: Bottle,
        recommendedBackend: GraphicsBackend
    ) -> RockstarLibraryPass {
        var pass = RockstarLibraryPass()
        for game in SteamLibrary.enumerate(bottleURL: bottle.url) {
            let scan = SteamLibrary.scanExecutables(under: game.installURL)
            for executable in scan.planExecutables {
                if let key = dxmtGameFolderKey(executable.deletingLastPathComponent(), bottleURL: bottle.url) {
                    pass.planFolderKeys.insert(key.lowercased())
                }
            }
            pass.hosts += scan.ownSettingsExecutables
            let plan = SteamLauncher.launchPlan(appId: game.appId, scan: scan, bottle: bottle)
            if rockstarProgramUsesNativeD3D11(
                plan.overrides, bottle: bottle, recommendedBackend: recommendedBackend, dxmtIsServed: true
            ) {
                pass.dxvkPlanGames.append(game.name)
            }
        }
        return pass
    }

    // MARK: - Copy folders

    /// Steam's 64-bit Chromium folders, then its root when the overlay there
    /// is 64-bit. A folder that cannot take a copy is unserved.
    private static func steamCopyFolders(
        steamRoot: URL?, bottleURL: URL, unserved: inout [String]
    ) -> [RockstarD3DCopyFolder] {
        guard let steamRoot else { return [] }
        let cef = steamRoot.appending(path: "bin").appending(path: "cef")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: cef.path(percentEncoded: false))) ?? []
        var folders: [URL] = names.sorted().map { cef.appending(path: $0) }
            .filter { isX64(at: $0.appending(path: "steamwebhelper.exe")) }
        if isX64(at: steamRoot.appending(path: "gameoverlayui64.exe")) {
            folders.append(steamRoot)
        }
        return folders.compactMap { folder in
            guard let key = dxmtGameFolderKey(folder, bottleURL: bottleURL) else {
                unserved.append(folder.lastPathComponent)
                return nil
            }
            return RockstarD3DCopyFolder(url: rockstarDriveC(bottleURL).appending(path: key), key: key, create: [])
        }
    }

    /// Social Club's folder relative to `drive_c`, as Rockstar's installer creates it.
    static let socialClubKey = "Program Files/Rockstar Games/Social Club"

    /// Social Club's folder, with the folders to create when it is not there
    /// yet, or `nil` when it cannot take a copy: something other than a
    /// folder holds its place, or a parent leads out of `drive_c`.
    private static func socialClubCopyFolder(bottleURL: URL) -> RockstarD3DCopyFolder? {
        let programFiles = rockstarDriveC(bottleURL).appending(path: "Program Files")
        let rockstarGames = programFiles.appending(path: "Rockstar Games")
        let socialClub = rockstarGames.appending(path: "Social Club")
        if let key = dxmtGameFolderKey(socialClub, bottleURL: bottleURL) {
            return RockstarD3DCopyFolder(url: rockstarDriveC(bottleURL).appending(path: key), key: key, create: [])
        }
        guard !rockstarEntryExists(socialClub) else { return nil }
        var create: [String] = []
        let parentKey: String
        if let key = dxmtGameFolderKey(rockstarGames, bottleURL: bottleURL) {
            parentKey = key
        } else {
            guard !rockstarEntryExists(rockstarGames) else { return nil }
            let base = dxmtGameFolderKey(programFiles, bottleURL: bottleURL)
            guard base != nil || !rockstarEntryExists(programFiles) else { return nil }
            parentKey = "\(base ?? "Program Files")/Rockstar Games"
            create.append(parentKey)
        }
        let key = "\(parentKey)/Social Club"
        create.append(key)
        return RockstarD3DCopyFolder(url: rockstarDriveC(bottleURL).appending(path: key), key: key, create: create)
    }

    /// The folders of the front ends and Chromium hosts among `executables`
    /// that get a native-first `d3d11`. One whose folder cannot take a copy
    /// is unserved by its executable's name.
    @MainActor
    private static func frontEndCopyFolders(
        _ executables: [URL], bottle: Bottle, recommendedBackend: GraphicsBackend, excluded: Set<String>,
        unserved: inout [String]
    ) -> [RockstarD3DCopyFolder] {
        var seen = Set<String>()
        var folders: [RockstarD3DCopyFolder] = []
        for url in executables where seen.insert(url.path(percentEncoded: false).lowercased()).inserted {
            guard rockstarGetsNativeD3D11(url, bottle: bottle, recommendedBackend: recommendedBackend) else {
                continue
            }
            guard let key = dxmtGameFolderKey(url.deletingLastPathComponent(), bottleURL: bottle.url),
                  !excluded.contains(key.lowercased()), !isUnderRockstarLauncher(key)
            else {
                unserved.append(url.lastPathComponent)
                continue
            }
            folders.append(RockstarD3DCopyFolder(
                url: rockstarDriveC(bottle.url).appending(path: key),
                key: key,
                create: []
            ))
        }
        return folders
    }

    /// Whether a launch gives `url` a native-first `d3d11`: a front end that
    /// Recommended steers to DXVK, under the same condition
    /// ``addFrontEndScopes(_:to:bottle:recommendedBackend:launcherSet:)``
    /// writes it the launcher set, or a Chromium host whose own settings, as
    /// a Steam launch writes them for it, ask for `d3d11` native first. No
    /// DXMT copies go beside a host, so a DXMT override counts as well: in a
    /// Steam session it reads `system32`'s `d3d11`, DXVK's until the swap.
    @MainActor
    static func rockstarGetsNativeD3D11(_ url: URL, bottle: Bottle, recommendedBackend: GraphicsBackend) -> Bool {
        let persisted = Program.persistedOverrides(for: url, bottleURL: bottle.url)
        if frontEndSteering(for: url) != nil {
            return frontEndWantsDXVK(choice: persisted?.graphicsBackend ?? bottle.settings.graphicsBackend)
        }
        guard let persisted else { return false }
        return rockstarProgramUsesNativeD3D11(
            persisted, bottle: bottle, recommendedBackend: recommendedBackend, dxmtIsServed: false
        )
    }

    /// Whether `folder` already holds a `d3d11.dll` or `d3d10core.dll` that is
    /// not DXVK's: another spelling of the name, a symbolic link, or a file
    /// that is neither the payload's bytes nor Whisky's recorded copy.
    private static func holdsForeignD3D(
        _ folder: RockstarD3DCopyFolder, payload: [String: String], record: RockstarD3DLayoutRecord?
    ) -> Bool {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: folder.url.path(percentEncoded: false)))
            ?? []
        return rockstarD3DCopyDLLs.contains { dll in
            // On a case-sensitive volume `D3D11.dll` is a file of its own, and still the program's.
            if entries.contains(where: { $0.lowercased() == dll && $0 != dll }) {
                return true
            }
            let url = folder.url.appending(path: dll)
            if rockstarIsSymbolicLink(url) {
                return true
            }
            guard rockstarEntryExists(url) else { return false }
            guard let hash = RockstarD3DLayoutRecord.sha256(of: url) else { return true }
            return hash != payload[dll] && hash != record?.copies[RockstarD3DLayoutRecord.key(folder.key, dll)]
        }
    }

    /// Whether `key` lies in Rockstar's launcher folder: `Launcher.exe` there
    /// is what the swap is for, and a DXVK copy beside it would take Wine's
    /// `d3d11` away from it again.
    static func isUnderRockstarLauncher(_ key: String) -> Bool {
        let components = key.split(separator: "/").map { $0.lowercased() }
        return zip(components, components.dropFirst()).contains { $0 == "rockstar games" && $1 == "launcher" }
    }

    // MARK: - Other launchers

    /// The other launchers' processes with a native-first `d3d11` in their
    /// `AppDefaults` entry, by name.
    ///
    /// A launch of the EA app, Ubisoft Connect, Battle.net and the rest writes
    /// their processes DXVK's set, and once written, something other than
    /// Whisky can start them: a game bought on Steam starts its publisher's
    /// launcher inside the Steam session. With no copy beside them they would
    /// get Wine's `d3d11`. A launcher never started from Whisky has no such
    /// entry, so it runs on the bottle's backend now and keeps doing so.
    ///
    /// Only launchers and their helpers count: `AppDefaults` keeps the entries
    /// of games long uninstalled, and a generic name among them would refuse
    /// the swap forever.
    static func otherLauncherConsumers(bottleURL: URL) -> [String] {
        guard let file = WineRegistryFile.contents(for: #"HKCU\Software\Wine\AppDefaults"#, bottleURL: bottleURL)
        else { return [] }
        let others = LauncherType.allCases.filter { $0 != .steam && $0 != .rockstar }
        let helpers = Set(others.flatMap(\.helperExecutables).map { $0.lowercased() })
        return appDefaultsDLLOverrideExecutables(in: file.text).filter { executable in
            let detected = LauncherType.detect(from: URL(filePath: "/").appending(path: executable))
            guard detected.map(others.contains) == true || helpers.contains(executable.lowercased()),
                  let d3d11 = WineRegistryFile.readValue(
                      bottleURL: bottleURL, key: DLLOverrideScope.program(executable).registryKey, valueName: "d3d11"
                  )
            else { return false }
            return d3d11.lowercased().hasPrefix("n")
        }
    }

    /// The executables with a `DllOverrides` key under `AppDefaults` in the
    /// text of `user.reg`, as its section headers spell them.
    static func appDefaultsDLLOverrideExecutables(in text: String) -> [String] {
        let prefix = #"[software\\wine\\appdefaults\\"#
        let suffix = #"\\dlloverrides]"#
        var executables: [String] = []
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let close = trimmed.firstIndex(of: "]") else { continue }
            let header = String(trimmed[...close])
            let lowercased = header.lowercased()
            guard lowercased.hasPrefix(prefix), lowercased.hasSuffix(suffix),
                  header.count > prefix.count + suffix.count
            else { continue }
            let name = String(header.dropFirst(prefix.count).dropLast(suffix.count))
            if !name.contains("\\") {
                executables.append(name)
            }
        }
        return executables
    }

    // MARK: - Files

    /// The bottle's `drive_c`, with its symbolic links resolved, which the
    /// keys from ``dxmtGameFolderKey(_:bottleURL:)`` are relative to.
    static func rockstarDriveC(_ bottleURL: URL) -> URL {
        bottleURL.appending(path: "drive_c").standardizedFileURL.resolvingSymlinksInPath()
    }

    /// Whether anything is at `url`, a dangling symbolic link included.
    static func rockstarEntryExists(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))) != nil
    }

    static func rockstarIsSymbolicLink(_ url: URL) -> Bool {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        return (attributes?[.type] as? FileAttributeType) == .typeSymbolicLink
    }

    /// Whether `url` is a 64-bit PE.
    private static func isX64(at url: URL) -> Bool {
        (try? PEFile(url: url).architecture) == .x64
    }
}
