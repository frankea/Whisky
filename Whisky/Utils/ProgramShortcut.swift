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
import os.log
@preconcurrency import QuickLookThumbnailing
import WhiskyKit

class ProgramShortcut {
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

    /// Creates a shortcut `.app` bundle with icon extraction and Finder reveal.
    ///
    /// Uses ``ShortcutCreator`` from WhiskyKit for the core bundle creation,
    /// then adds icon extraction (QuickLook) and Finder integration (AppKit)
    /// which are only available in the app target.
    @MainActor
    static func createShortcut(_ program: Program, app: URL, name: String) async {
        do {
            // Core bundle creation via shared WhiskyKit logic
            let launchScript = program.generateTerminalCommand()
            try ShortcutCreator.createShortcutBundle(at: app, launchScript: launchScript, name: name)

            // App-specific: extract icon from PE file and set on the .app bundle
            let programUrl = program.url
            if let image = await generateThumbnail(for: programUrl) {
                NSWorkspace.shared.setIcon(
                    image,
                    forFile: app.path(percentEncoded: false),
                    options: NSWorkspace.IconCreationOptions()
                )
            }

            // Reveal in Finder
            NSWorkspace.shared.activateFileViewerSelecting([app])
        } catch {
            Logger.wineKit.error("Failed to create program shortcut: \(error.localizedDescription)")
        }
    }
}
