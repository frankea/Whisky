//
//  ProgramShortcut.swift
//  Whisky
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
@preconcurrency import QuickLookThumbnailing
import WhiskyKit

class ProgramShortcut {
    private static let infoPlist = """
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

    @MainActor
    private static func generateThumbnail(for url: URL) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 512, height: 512),
            scale: 2.0,
            representationTypes: .thumbnail
        )
        guard let thumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else {
            return nil
        }
        return thumbnail.nsImage
    }

    @MainActor
    static func createShortcut(_ program: Program, app: URL, name: String) async {
        let contents = app.appending(path: "Contents")
        let macos = contents.appending(path: "MacOS")
        do {
            try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)

            let script = "#!/bin/bash\n\(program.generateTerminalCommand())"
            let scriptUrl = macos.appending(path: "launch")
            try script.write(to: scriptUrl, atomically: false, encoding: .utf8)
            // Use 0o755 (owner write, world read+execute) for security - prevents other users from modifying
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: scriptUrl.path(percentEncoded: false)
            )

            try infoPlist.write(
                to: contents.appending(path: "Info").appendingPathExtension("plist"),
                atomically: false,
                encoding: .utf8
            )

            let programUrl = program.url
            if let image = await generateThumbnail(for: programUrl) {
                NSWorkspace.shared.setIcon(
                    image,
                    forFile: app.path(percentEncoded: false),
                    options: NSWorkspace.IconCreationOptions()
                )
            }
            NSWorkspace.shared.activateFileViewerSelecting([app])
        } catch {
            print(error)
        }
    }
}
