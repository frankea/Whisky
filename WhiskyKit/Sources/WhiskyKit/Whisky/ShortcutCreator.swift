//
//  ShortcutCreator.swift
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

import AppKit
import Foundation

/// Creates macOS `.app` shortcut bundles for launching Windows programs via Wine.
///
/// This caseless enum provides shared shortcut creation logic used by both
/// the Whisky app and WhiskyCmd CLI. It handles bundle structure creation,
/// launch script writing, the bundle icon and Info.plist generation.
///
/// The QuickLook thumbnail fallback and Finder integration remain in the app
/// target (``ProgramShortcut``).
///
/// ## Usage
///
/// ```swift
/// let appURL = URL(filePath: "~/Applications/MyGame.app")
/// try ShortcutCreator.createShortcut(for: program, at: appURL, name: "MyGame")
/// ```
public enum ShortcutCreator {
    /// The icon file a shortcut bundle carries in `Contents/Resources`,
    /// without its `.icns` extension.
    public static let iconFileName = "AppIcon"

    /// The Info.plist of a shortcut app bundle.
    ///
    /// - Parameters:
    ///   - name: The shortcut's display name, used as `CFBundleName`.
    ///   - iconFileName: The `.icns` file in `Contents/Resources` that holds
    ///     the shortcut's icon, without its extension, or `nil` for none.
    /// - Returns: The property list, in XML format.
    /// - Throws: If the property list cannot be serialized.
    public static func infoPlist(name: String, iconFileName: String? = nil) throws -> Data {
        var plist: [String: Any] = [
            "CFBundleExecutable": "launch",
            "CFBundleName": name,
            "CFBundlePackageType": "APPL",
            "CFBundleSupportedPlatforms": ["MacOSX"],
            "LSMinimumSystemVersion": "14.0",
            "LSApplicationCategoryType": "public.app-category.games"
        ]
        if let iconFileName {
            plist["CFBundleIconFile"] = iconFileName
        }
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }

    /// Creates a shortcut bundle that launches `program` through Whisky's live
    /// pipeline, with the program's own icon when it has one.
    ///
    /// - Parameters:
    ///   - program: The program the shortcut launches.
    ///   - appURL: The destination URL for the `.app` bundle. Anything already
    ///     there is replaced.
    ///   - name: The shortcut's display name.
    /// - Returns: Whether the bundle got the program's icon.
    /// - Throws: An error if the bundle directories or files cannot be created.
    @MainActor
    @discardableResult
    public static func createShortcut(for program: Program, at appURL: URL, name: String) throws -> Bool {
        let target = liveTarget(for: program.url, bottle: program.bottle)
        return try createShortcutBundle(
            at: appURL,
            launchScript: liveLaunchScript(for: target),
            name: name,
            icon: program.peFile?.bestIcon()
        )
    }

    /// Creates a macOS `.app` bundle that launches a Windows program via Wine.
    ///
    /// The bundle structure created is:
    /// ```
    /// <name>.app/
    ///   Contents/
    ///     Info.plist
    ///     MacOS/
    ///       launch          (executable shell script)
    ///     Resources/
    ///       AppIcon.icns    (when an icon is given)
    /// ```
    ///
    /// An existing bundle at `appURL` is removed first, so nothing of it
    /// survives, such as a Finder custom icon that would hide the new one.
    ///
    /// - Parameters:
    ///   - appURL: The destination URL for the `.app` bundle.
    ///   - launchScript: The shell command to execute when the app is launched.
    ///   - name: The display name for the shortcut, written as `CFBundleName`.
    ///   - icon: The image to embed as the bundle's icon, or `nil` for none.
    /// - Returns: Whether the icon was written into the bundle.
    /// - Throws: An error if the bundle directories or files cannot be created.
    @discardableResult
    public static func createShortcutBundle(
        at appURL: URL,
        launchScript: String,
        name: String,
        icon: NSImage? = nil
    ) throws -> Bool {
        if FileManager.default.fileExists(atPath: appURL.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: appURL)
        }

        let contents = appURL.appending(path: "Contents")
        let macos = contents.appending(path: "MacOS")

        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)

        let script = "#!/bin/bash\n\(launchScript)"
        let scriptUrl = macos.appending(path: "launch")
        try script.write(to: scriptUrl, atomically: false, encoding: .utf8)

        // Use 0o755 (owner write, world read+execute) for security
        // Prevents other users from modifying the launch script
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptUrl.path(percentEncoded: false)
        )

        let iconURL = contents.appending(path: "Resources")
            .appending(path: iconFileName).appendingPathExtension("icns")
        let iconWritten = icon.map { ShortcutIcon.write($0, to: iconURL) } ?? false

        try infoPlist(name: name, iconFileName: iconWritten ? iconFileName : nil)
            .write(to: contents.appending(path: "Info").appendingPathExtension("plist"))
        return iconWritten
    }
}

public extension ShortcutCreator {
    /// What a live shortcut launches.
    enum LiveTarget: Equatable {
        /// A Steam game, launched by App ID through the client so DRM and
        /// GameDB profiles apply.
        ///
        /// Deliberately not pinned to a bottle: the App ID is Steam's own
        /// identity for the game, and resolving it at launch means the
        /// shortcut follows the copy that is actually installed rather than
        /// breaking when its bottle moves or is deleted. A game installed in
        /// two bottles launches from whichever was played most recently.
        case steamGame(appId: Int)
        /// A program addressed by bottle name and Windows path. The Windows
        /// path is bottle-relative by construction, so the shortcut survives
        /// the bottle moving.
        case program(bottleName: String, windowsPath: String)
    }

    /// Picks the live target for a program: a Steam game when the executable
    /// belongs to one of the bottle's Steam libraries (or ships a
    /// steam_appid.txt), otherwise a bottle-name + Windows-path launch.
    @MainActor
    static func liveTarget(for url: URL, bottle: Bottle) -> LiveTarget {
        if SteamLibrary.detectInstall(bottleURL: bottle.url) != nil {
            let games = SteamLibrary.enumerate(bottleURL: bottle.url)
            let path = url.standardizedFileURL.path
            if let game = games.first(where: {
                path.hasPrefix($0.installURL.standardizedFileURL.path + "/")
            }) {
                return .steamGame(appId: game.appId)
            }
            if let appId = SteamAppManifest.findAppIdForProgram(at: url) {
                return .steamGame(appId: appId)
            }
        }

        let windowsPath = windowsPath(for: url, bottleURL: bottle.url)
            ?? url.path(percentEncoded: false)
        return .program(bottleName: bottle.settings.name, windowsPath: windowsPath)
    }

    /// A launch script that goes through Whisky's live pipeline (WhiskyCmd)
    /// instead of baking the environment at creation time: current settings,
    /// GameDB profiles, backend deployment, and run logs all apply at launch,
    /// and nothing breaks when the bottle moves or settings change.
    ///
    /// - Parameters:
    ///   - target: What the shortcut launches.
    ///   - notFoundTitle: Title of the alert shown when Whisky can't be found,
    ///     in the language the shortcut is created in.
    ///   - notFoundMessage: Message of that alert.
    static func liveLaunchScript(
        for target: LiveTarget,
        notFoundTitle: String = String(localized: "shortcut.notFound.title", defaultValue: "Whisky not found"),
        notFoundMessage: String = String(
            localized: "shortcut.notFound.message",
            defaultValue: "Install Whisky to use this shortcut."
        )
    ) -> String {
        let invocation = switch target {
        case let .steamGame(appId):
            "launch \(appId)"
        case let .program(bottleName, windowsPath):
            "run \(shellQuoted(bottleName)) \(shellQuoted(windowsPath))"
        }
        // Translated text can hold quotes and backslashes: quote it for
        // AppleScript first, then quote the whole -e argument for the shell.
        let alert = "display alert \(appleScriptQuoted(notFoundTitle))"
            + " message \(appleScriptQuoted(notFoundMessage))"

        return """
        WHISKY_CMD="/Applications/Whisky.app/Contents/Resources/WhiskyCmd"
        if [ ! -x "$WHISKY_CMD" ]; then
            WHISKY_APP="$(mdfind "kMDItemCFBundleIdentifier == '\(Bundle
            .whiskyBundleIdentifier)'" 2>/dev/null | head -n 1)"
            WHISKY_CMD="$WHISKY_APP/Contents/Resources/WhiskyCmd"
        fi
        if [ ! -x "$WHISKY_CMD" ]; then
            osascript -e \(shellQuoted(alert))
            exit 1
        fi
        exec "$WHISKY_CMD" \(invocation)
        """
    }

    /// The Windows-style path (`C:\...`) of a file on the bottle's C drive,
    /// or `nil` when the file lives elsewhere.
    static func windowsPath(for url: URL, bottleURL: URL) -> String? {
        let path = url.standardizedFileURL.path
        let driveC = bottleURL.standardizedFileURL.appending(path: "drive_c").path
        guard path.hasPrefix(driveC + "/") else { return nil }
        let rest = String(path.dropFirst(driveC.count + 1))
        return "C:\\" + rest.replacingOccurrences(of: "/", with: "\\")
    }

    /// Wraps a value in single quotes for safe shell interpolation.
    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Wraps a value in double quotes as an AppleScript string literal.
    static func appleScriptQuoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"" + escaped + "\""
    }
}
