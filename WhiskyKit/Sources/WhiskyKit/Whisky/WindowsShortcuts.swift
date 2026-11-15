//
//  WindowsShortcuts.swift
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

/// A folder of a bottle that Windows installers write shortcuts to.
public struct WindowsShortcutFolder: Hashable, Sendable {
    /// The folder.
    public let url: URL
    /// Start Menu shortcuts live in nested program folders; Desktop ones don't.
    public let recursive: Bool
}

/// Finds the shortcuts Windows installers create in a bottle and decides which
/// of them stand for a program.
public enum WindowsShortcuts {
    /// The Start Menu and Desktop folders of `driveC`, for `wineUsername`.
    public static func folders(driveC: URL, wineUsername: String) -> [WindowsShortcutFolder] {
        let users = driveC.appending(path: "users")
        let startMenu = ["Microsoft", "Windows", "Start Menu"]
        let globalStartMenu = startMenu.reduce(driveC.appending(path: "ProgramData")) { $0.appending(path: $1) }
        let userStartMenu = startMenu.reduce(
            users.appending(path: wineUsername).appending(path: "AppData").appending(path: "Roaming")
        ) { $0.appending(path: $1) }

        return [
            WindowsShortcutFolder(url: globalStartMenu, recursive: true),
            WindowsShortcutFolder(url: userStartMenu, recursive: true),
            WindowsShortcutFolder(
                url: users.appending(path: wineUsername).appending(path: "Desktop"),
                recursive: false
            ),
            WindowsShortcutFolder(url: users.appending(path: "Public").appending(path: "Desktop"), recursive: false)
        ]
    }

    /// Every `.lnk` file in the bottle's shortcut folders, sorted by path
    /// within each folder.
    ///
    /// Folders that don't exist are skipped, and so are folders that are
    /// symbolic links: Wine can link the profile's Desktop to the Mac's own
    /// Desktop, which is not the bottle's and needs a privacy prompt to read.
    /// Hidden files are ignored.
    public static func findShortcuts(driveC: URL, wineUsername: String) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        var found: [URL] = []

        for folder in folders(driveC: driveC, wineUsername: wineUsername) {
            let isLink = (try? folder.url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false
            guard !isLink else { continue }

            var options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
            if !folder.recursive {
                options.insert(.skipsSubdirectoryDescendants)
            }
            guard let enumerator = FileManager.default.enumerator(
                at: folder.url,
                includingPropertiesForKeys: keys,
                options: options
            )
            else { continue }

            var inFolder: [URL] = []
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "lnk" {
                guard (try? url.resourceValues(forKeys: Set(keys)))?.isRegularFile ?? false else { continue }
                inFolder.append(url)
            }
            found += inFolder.sorted { $0.path(percentEncoded: false) < $1.path(percentEncoded: false) }
        }

        return found
    }

    /// Words in a shortcut's name that mark it as something other than the
    /// program: its uninstaller, documentation or web links.
    static let nonProgramNameWords: Set<String> = [
        "uninstall", "uninstaller", "uninst", "desinstalar", "desinstalador", "deinstallieren",
        "readme", "leiame", "manual", "help", "ajuda", "license", "licença", "licenca", "eula",
        "changelog", "website", "homepage", "documentation"
    ]

    /// Multi-word names with the same meaning as ``nonProgramNameWords``.
    static let nonProgramNamePhrases = ["read me", "leia-me", "leia me", "release notes", "web site"]

    /// Executables that are never the program a shortcut is for.
    static let nonProgramExecutables: Set<String> = ["update.exe", "uninstall.exe", "uninst.exe"]

    /// Whether a shortcut named `name` that points at `targetPath` (a Unix path
    /// into the bottle) stands for a program worth pinning.
    ///
    /// Only shortcuts to `.exe` files outside `C:\windows` qualify, and not
    /// uninstallers, documentation or web links. Squirrel-style shortcuts that
    /// target `Update.exe` are skipped as well: the arguments that make them
    /// start the real program are not carried over to a pin. So are the helpers
    /// and crash reporters the program list hides
    /// (``Bottle/noiseExecutableNames``).
    public static func isProgramShortcut(name: String, targetPath: String) -> Bool {
        let target = targetPath.lowercased()
        let executable = (target as NSString).lastPathComponent
        guard executable.hasSuffix(".exe") else { return false }
        guard !target.contains("/drive_c/windows/") else { return false }
        guard !nonProgramExecutables.contains(executable), !executable.hasPrefix("unins") else { return false }
        guard !Bottle.noiseExecutableNames.contains(executable) else { return false }

        let lowered = name.lowercased()
        guard !nonProgramNamePhrases.contains(where: { lowered.contains($0) }) else { return false }
        let words = lowered.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        return !words.contains(where: { nonProgramNameWords.contains($0) })
    }
}

/// The Windows shortcuts of a bottle that were already handled, so each one
/// pins its program once and the `.lnk` files can stay where the installer
/// put them.
///
/// Stored in the bottle folder, keyed by each shortcut's path relative to
/// `drive_c`, so moving or duplicating the bottle keeps the record valid.
public struct HandledShortcuts: Codable, Equatable, Sendable {
    /// The record's file name inside the bottle folder.
    public static let fileName = "HandledShortcuts.plist"

    /// Lowercased paths, relative to `drive_c`, of the shortcuts handled so far.
    public private(set) var links: Set<String>

    public init(links: Set<String> = []) {
        self.links = links
    }

    /// Whether the bottle has a record, even an empty or unreadable one.
    ///
    /// A bottle without one was last opened by a version that deleted each
    /// Start Menu shortcut it read and kept no record (see
    /// ``StartMenuShortcutSync``).
    public static func exists(in bottleURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: bottleURL.appending(path: fileName).path(percentEncoded: false))
    }

    /// Starts an empty record for a new bottle, so that the first program
    /// installed in it is pinned like any later one.
    public static func startRecord(in bottleURL: URL) throws {
        try HandledShortcuts().save(to: bottleURL)
    }

    /// The bottle's record, or an empty one when it has none or it can't be read.
    public static func load(from bottleURL: URL) -> HandledShortcuts {
        guard let data = try? Data(contentsOf: bottleURL.appending(path: fileName)),
              let record = try? PropertyListDecoder().decode(HandledShortcuts.self, from: data)
        else { return HandledShortcuts() }
        return record
    }

    /// Writes the record into the bottle folder.
    public func save(to bottleURL: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        try encoder.encode(self).write(to: bottleURL.appending(path: Self.fileName), options: .atomic)
    }

    /// The key for `link`: its path relative to `driveC`, lowercased because
    /// bottles live on case-insensitive volumes and Windows paths ignore case.
    public static func key(for link: URL, driveC: URL) -> String {
        let linkPath = link.standardizedFileURL.path(percentEncoded: false)
        var root = driveC.standardizedFileURL.path(percentEncoded: false)
        if !root.hasSuffix("/") {
            root += "/"
        }
        let relative = linkPath.hasPrefix(root) ? String(linkPath.dropFirst(root.count)) : linkPath
        return relative.lowercased()
    }

    /// Whether `link` was handled before.
    public func contains(_ link: URL, driveC: URL) -> Bool {
        links.contains(Self.key(for: link, driveC: driveC))
    }

    /// Records `link` as handled.
    public mutating func insert(_ link: URL, driveC: URL) {
        links.insert(Self.key(for: link, driveC: driveC))
    }

    /// The record without the shortcuts that are no longer among `present`,
    /// so a shortcut an uninstaller removed and a reinstall wrote again is
    /// handled like a new one.
    public func keeping(_ present: [URL], driveC: URL) -> HandledShortcuts {
        HandledShortcuts(links: links.intersection(present.map { Self.key(for: $0, driveC: driveC) }))
    }
}
