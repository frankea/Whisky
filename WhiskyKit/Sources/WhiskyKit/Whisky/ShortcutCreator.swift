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

import Foundation

/// Creates macOS `.app` shortcut bundles for launching Windows programs via Wine.
///
/// This caseless enum provides shared shortcut creation logic used by both
/// the Whisky app and WhiskyCmd CLI. It handles bundle structure creation,
/// launch script writing, and Info.plist generation.
///
/// Icon extraction and Finder integration remain in the app target
/// (``ProgramShortcut``) since they require AppKit/QuickLook.
///
/// ## Usage
///
/// ```swift
/// let appURL = URL(filePath: "~/Applications/MyGame.app")
/// let target = ShortcutCreator.liveTarget(for: program.url, bottle: program.bottle)
/// let script = ShortcutCreator.liveLaunchScript(for: target)
/// try ShortcutCreator.createShortcutBundle(at: appURL, launchScript: script, name: "MyGame")
/// ```
public enum ShortcutCreator {
    /// The Info.plist template for shortcut app bundles.
    public static let infoPlist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>CFBundleExecutable</key>
        <string>launch</string>
        <key>CFBundleSupportedPlatforms</key>
        <array>
            <string>MacOSX</string>
        </array>
        <key>LSMinimumSystemVersion</key>
        <string>14.0</string>
        <key>LSApplicationCategoryType</key>
        <string>public.app-category.games</string>
    </dict>
    </plist>
    """

    /// Creates a macOS `.app` bundle that launches a Windows program via Wine.
    ///
    /// The bundle structure created is:
    /// ```
    /// <name>.app/
    ///   Contents/
    ///     Info.plist
    ///     MacOS/
    ///       launch          (executable shell script)
    /// ```
    ///
    /// - Parameters:
    ///   - appURL: The destination URL for the `.app` bundle.
    ///   - launchScript: The shell command to execute when the app is launched.
    ///   - name: The display name for the shortcut (used for logging).
    /// - Throws: An error if the bundle directories or files cannot be created.
    public static func createShortcutBundle(at appURL: URL, launchScript: String, name: String) throws {
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

        try infoPlist.write(
            to: contents.appending(path: "Info").appendingPathExtension("plist"),
            atomically: false,
            encoding: .utf8
        )
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
