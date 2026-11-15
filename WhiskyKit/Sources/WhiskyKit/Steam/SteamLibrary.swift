//
//  SteamLibrary.swift
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

/// A fully installed Steam game discovered inside a Wine bottle.
public struct SteamGame: Identifiable, Equatable, Sendable {
    public var id: Int { appId }
    /// The Steam App ID.
    public let appId: Int
    /// The display name from the manifest.
    public let name: String
    /// The resolved absolute URL of the game's install directory.
    public let installURL: URL
    /// The full parsed manifest.
    public let manifest: SteamAppManifest
}

/// Discovers a Windows Steam installation inside a Wine bottle and
/// enumerates its installed games across all configured library folders.
public enum SteamLibrary {
    /// Candidate Steam install locations under `drive_c`.
    private static let installCandidates = [
        "Program Files (x86)/Steam",
        "Program Files/Steam"
    ]

    /// App IDs Steam installs as shared runtime payloads rather than games.
    /// They appear as ordinary manifests but have nothing to launch.
    static let nonGameAppIds: Set<Int> = [
        228_980, // Steamworks Common Redistributables
        1_070_560, // Steam Linux Runtime 1.0 (soldier)
        1_391_110, // Steam Linux Runtime 2.0 (soldier)
        1_628_350 // Steam Linux Runtime 3.0 (sniper)
    ]

    /// Locates the Steam installation inside a bottle.
    ///
    /// - Parameter bottleURL: The root URL of the Wine bottle.
    /// - Returns: The Steam root directory (the one containing `steam.exe`),
    ///   or `nil` if no install is found.
    public static func detectInstall(bottleURL: URL) -> URL? {
        for candidate in installCandidates {
            let root = bottleURL.appending(path: "drive_c").appending(path: candidate)
            let steamExe = root.appending(path: "steam.exe")
            if FileManager.default.fileExists(atPath: steamExe.path(percentEncoded: false)) {
                return root
            }
        }
        return nil
    }

    /// Enumerates fully installed games across every Steam library in the bottle.
    ///
    /// Reads `libraryfolders.vdf` for configured library locations (mapping
    /// Windows paths through the prefix), scans each library's
    /// `steamapps/appmanifest_*.acf`, keeps fully installed games whose
    /// install directory actually exists, and de-duplicates by App ID.
    ///
    /// - Parameter bottleURL: The root URL of the Wine bottle.
    /// - Returns: Installed games sorted by name, empty if Steam isn't installed.
    public static func enumerate(bottleURL: URL) -> [SteamGame] {
        guard let steamRoot = detectInstall(bottleURL: bottleURL) else { return [] }

        let roots = libraryRoots(steamRoot: steamRoot, bottleURL: bottleURL)
        let revision = revision(of: roots)
        if let cached = cache.games(forBottleAt: bottleURL, revision: revision) {
            return cached
        }

        var byAppId: [Int: SteamGame] = [:]
        for library in roots {
            for game in games(inLibrary: library) where byAppId[game.appId] == nil {
                byAppId[game.appId] = game
            }
        }

        let sorted = byAppId.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        cache.store(sorted, forBottleAt: bottleURL, revision: revision)
        return sorted
    }

    /// A stamp that changes whenever a library's contents could have.
    ///
    /// The modification date of each `steamapps` directory, which moves when a
    /// manifest is added or removed, so installing, uninstalling or moving a
    /// game invalidates it. Merely playing one does not, which is the point: a
    /// refresh that changed nothing costs a handful of `stat` calls instead of
    /// parsing every manifest in every library.
    private static func revision(of libraries: [URL]) -> [String] {
        libraries.map { library in
            let steamapps = library.appending(path: "steamapps")
            let modified = try? steamapps.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            return "\(steamapps.path(percentEncoded: false))@\(modified?.timeIntervalSince1970 ?? 0)"
        }
    }

    private static let cache = EnumerationCache()

    /// Remembers the last enumeration per bottle, valid while its libraries
    /// have not been written to.
    private final class EnumerationCache: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [URL: (revision: [String], games: [SteamGame])] = [:]

        func games(forBottleAt url: URL, revision: [String]) -> [SteamGame]? {
            lock.lock()
            defer { lock.unlock() }
            guard let entry = entries[url], entry.revision == revision else { return nil }
            return entry.games
        }

        func store(_ games: [SteamGame], forBottleAt url: URL, revision: [String]) {
            lock.lock()
            defer { lock.unlock() }
            entries[url] = (revision, games)
        }
    }

    /// The Steam root plus every existing library folder referenced by
    /// `libraryfolders.vdf` (checked in its current `config/` home and its
    /// legacy `steamapps/` location).
    static func libraryRoots(steamRoot: URL, bottleURL: URL) -> [URL] {
        var roots = [steamRoot]
        var seen: Set<String> = [steamRoot.standardizedFileURL.path]

        let vdfCandidates = [
            steamRoot.appending(path: "config").appending(path: "libraryfolders.vdf"),
            steamRoot.appending(path: "steamapps").appending(path: "libraryfolders.vdf")
        ]

        for vdfURL in vdfCandidates {
            guard let text = try? String(contentsOf: vdfURL, encoding: .utf8),
                  let root = try? VDFParser.parse(text),
                  let folders = root["libraryfolders"]?.objectValue
            else { continue }

            for value in folders.values {
                guard let windowsPath = value.objectValue?["path"]?.stringValue,
                      let mapped = mapWindowsPath(windowsPath, bottleURL: bottleURL)
                else { continue }

                let standardized = mapped.standardizedFileURL.path
                var isDirectory: ObjCBool = false
                if !seen.contains(standardized),
                   FileManager.default.fileExists(
                       atPath: mapped.path(percentEncoded: false),
                       isDirectory: &isDirectory
                   ),
                   isDirectory.boolValue {
                    seen.insert(standardized)
                    roots.append(mapped)
                }
            }
        }

        return roots
    }

    /// Whether `component` is a plain name safe to join onto a trusted root.
    ///
    /// Manifest and VDF contents are not trusted input (spoofed
    /// `appmanifest_*.acf` files are common in the repack ecosystem) and
    /// `URL.appending(path:)` does not collapse `..`, so an unchecked component
    /// escapes the library and reaches the games list, the running-state
    /// matcher, and the executable set handed to taskkill.
    static func isSafePathComponent(_ component: String) -> Bool {
        guard !component.isEmpty, component != ".", component != ".." else { return false }
        return !component.contains("/") && !component.contains("\\") && !component.contains("\0")
    }

    /// Maps a Windows path from a VDF file (`D:\\SteamLibrary`) to its
    /// location inside the prefix: `drive_c` for the C drive, the
    /// `dosdevices/<letter>:` symlink for everything else.
    ///
    /// Returns `nil` when any component would escape the prefix.
    static func mapWindowsPath(_ windowsPath: String, bottleURL: URL) -> URL? {
        let normalized = windowsPath.replacingOccurrences(of: "\\", with: "/")
        guard normalized.count >= 2 else { return nil }

        let driveLetter = normalized.prefix(1).lowercased()
        guard normalized[normalized.index(normalized.startIndex, offsetBy: 1)] == ":",
              driveLetter.first?.isLetter == true
        else { return nil }

        let rest = String(normalized.dropFirst(2)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let components = rest.split(separator: "/").map(String.init)
        guard components.allSatisfy(isSafePathComponent) else { return nil }

        let base: URL = if driveLetter == "c" {
            bottleURL.appending(path: "drive_c")
        } else {
            bottleURL.appending(path: "dosdevices").appending(path: "\(driveLetter):")
        }

        return components.reduce(base) { $0.appending(path: $1) }
    }

    /// Fully installed games in one library root whose install directory exists.
    private static func games(inLibrary library: URL) -> [SteamGame] {
        let steamApps = library.appending(path: "steamapps")
        guard let contents = try? FileManager.default.contentsOfDirectory(
            atPath: steamApps.path(percentEncoded: false)
        )
        else { return [] }

        var found: [SteamGame] = []
        for filename in contents where filename.hasPrefix("appmanifest_") && filename.hasSuffix(".acf") {
            guard let manifest = SteamAppManifest(contentsOf: steamApps.appending(path: filename)),
                  manifest.isFullyInstalled,
                  isSafePathComponent(manifest.installDir),
                  !nonGameAppIds.contains(manifest.appId)
            else { continue }

            let installURL = steamApps.appending(path: "common").appending(path: manifest.installDir)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(
                atPath: installURL.path(percentEncoded: false), isDirectory: &isDirectory
            ), isDirectory.boolValue
            else { continue }

            found.append(SteamGame(
                appId: manifest.appId,
                name: manifest.name,
                installURL: installURL,
                manifest: manifest
            ))
        }
        return found
    }

    /// Lowercased names of ``executableURLs(under:)``. Used to match a game's
    /// processes in the bottle's task list.
    public static func executableNames(under installURL: URL) -> Set<String> {
        Set(executableURLs(under: installURL).map { $0.lastPathComponent.lowercased() })
    }

    /// Picks the overrides a library launch should carry from the game's
    /// executables' persisted settings: the shallowest one that has any, ties
    /// broken by name, then by path, so the pick does not move between scans.
    ///
    /// Steam games surface as ordinary Programs, so a user can tune one in the
    /// Programs tab, and those settings have to survive the Play button.
    public static func preferredOverrides(among candidates: [ProgramOverrideCandidate]) -> ProgramOverrides? {
        candidates
            .filter { !$0.overrides.isEmpty }
            .min { lhs, rhs in
                let left = lhs.url.pathComponents.count
                let right = rhs.url.pathComponents.count
                guard left == right else { return left < right }
                let byName = lhs.url.lastPathComponent.localizedCaseInsensitiveCompare(rhs.url.lastPathComponent)
                guard byName == .orderedSame else { return byName == .orderedAscending }
                return lhs.url.path(percentEncoded: false) < rhs.url.path(percentEncoded: false)
            }?
            .overrides
    }
}

/// One executable's persisted overrides, for ``SteamLibrary/preferredOverrides(among:)``.
public struct ProgramOverrideCandidate: Equatable, Sendable {
    public let url: URL
    public let overrides: ProgramOverrides

    public init(url: URL, overrides: ProgramOverrides) {
        self.url = url
        self.overrides = overrides
    }
}
