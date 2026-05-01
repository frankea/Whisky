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
/// let script = program.generateTerminalCommand()
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
