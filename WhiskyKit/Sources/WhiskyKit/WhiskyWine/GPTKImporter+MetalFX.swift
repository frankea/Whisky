//
//  GPTKImporter+MetalFX.swift
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

/// MetalFX has exactly one entry point: the DLSS API. D3DMetal links MetalFX and
/// builds its scalers, but only for a game that calls `NVSDK_NGX_D3D12_*` in
/// `nvngx.dll`, which Apple implements as `nvngx-on-metalfx.dll`. With no such
/// DLL in the tree `D3DM_ENABLE_METALFX=1` has nothing to hook, which is why
/// MetalFX could not be enabled in any bottle.
///
/// Two things make this more than a file copy:
///
/// - The bridge is a hybrid PE and unixlib module. Its `DllMain` calls
///   `__wine_init_unix_call` before anything else and returns false when that
///   fails, so the PE on its own loads as a builtin and immediately dies with
///   `ERROR_DLL_INIT_FAILED`, which reads like a corrupt DLL and is not. It needs
///   a unix half beside it, exactly like the four D3D forwarders.
/// - Builtins are keyed by their PE export name, and this one exports as
///   `nvngx.dll` rather than the filename Apple ships it under.
///
/// `nvapi64.dll`, the other half of ``nvidiaBridgeDLLNames``, deliberately stays
/// out: Chromium probes for an NVIDIA GPU, and handing it one makes it load
/// D3DMetal and take Steam's helper process down. Nothing probes for nvngx that
/// way, and NGX reports DLSS available without it.
extension GPTKImporter {
    /// Apple's bridge under the name the payload ships it as.
    static let metalFXBridgeSourceName = "nvngx-on-metalfx.dll"
    /// The name it has to be installed under, because that is what its PE export
    /// directory says and the builtin loader matches on that, not the filename.
    static let metalFXBridgeName = "nvngx.dll"
    /// Its unix half, which shares the payload's single shared dylib with every
    /// other bridge.
    static let metalFXBridgeUnixName = "nvngx.so"

    /// Where the bridge lives in the store, or `nil` for a payload too old to
    /// carry one.
    static func metalFXBridgeSource(inStore store: URL) -> URL? {
        let source = store.appending(path: "lib").appending(path: "wine")
            .appending(path: "x86_64-windows").appending(path: metalFXBridgeSourceName)
        return FileManager.default.fileExists(atPath: source.path(percentEncoded: false)) ? source : nil
    }

    /// Whether the tree holds a bridge this store put there. Compared by content
    /// so a copy someone installed by hand is left alone by remove.
    static func isMetalFXBridgeInstalled(inLibraryFolder folder: URL, usingStore store: URL) -> Bool {
        guard let source = metalFXBridgeSource(inStore: store) else { return false }
        return FileManager.default.contentsEqual(
            atPath: metalFXBridgePE(inLibraryFolder: folder).path(percentEncoded: false),
            andPath: source.path(percentEncoded: false)
        )
    }

    static func metalFXBridgePE(inLibraryFolder folder: URL) -> URL {
        folder.appending(path: "Wine").appending(path: "lib").appending(path: "wine")
            .appending(path: "x86_64-windows").appending(path: metalFXBridgeName)
    }

    static func metalFXBridgeUnixLink(inLibraryFolder folder: URL) -> URL {
        folder.appending(path: "Wine").appending(path: "lib").appending(path: "wine")
            .appending(path: "x86_64-unix").appending(path: metalFXBridgeUnixName)
    }

    /// Puts the bridge in the tree under its export name with a unix half beside
    /// it. Does nothing when the payload is too old to carry one.
    ///
    /// Purely additive: Wine ships no `nvngx.dll`, so unlike the forwarders there
    /// is no builtin here to back up and nothing to restore on the way out.
    static func installMetalFXBridge(intoLibraryFolder folder: URL, usingStore store: URL) throws {
        guard let source = metalFXBridgeSource(inStore: store) else { return }
        let fileManager = FileManager.default
        let destination = metalFXBridgePE(inLibraryFolder: folder)
        let link = metalFXBridgeUnixLink(inLibraryFolder: folder)

        // The shared runtime is normally Whisky-owned, but a user or another tool can still
        // install its own nvngx implementation. Treat both halves as user data unless they are
        // absent or already byte/target-identical to ours.
        if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
            guard fileManager.contentsEqual(
                atPath: destination.path(percentEncoded: false),
                andPath: source.path(percentEncoded: false)
            )
            else {
                logger.warning("Leaving an existing foreign \(metalFXBridgeName, privacy: .public) untouched")
                return
            }
        }
        let existingLinkTarget = try? fileManager.destinationOfSymbolicLink(
            atPath: link.path(percentEncoded: false)
        )
        let linkPathExists = existingLinkTarget != nil
            || fileManager.fileExists(atPath: link.path(percentEncoded: false))
        guard !linkPathExists || existingLinkTarget == unixLinkDestination else {
            logger.warning("Leaving an existing foreign \(metalFXBridgeUnixName, privacy: .public) untouched")
            return
        }

        if !fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
            try fileManager.copyItem(at: source, to: destination)
        }

        try fileManager.createDirectory(
            at: link.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        if existingLinkTarget == nil {
            try fileManager.createSymbolicLink(
                atPath: link.path(percentEncoded: false),
                withDestinationPath: unixLinkDestination
            )
        }
        logger.info("Installed the MetalFX bridge as \(metalFXBridgeName, privacy: .public)")
    }

    /// Takes the bridge back out, leaving anything this store did not install.
    ///
    /// The unix link goes only when it points where we pointed it; `removeItem`
    /// acts on the link itself, so a dangling one is cleared too.
    static func removeMetalFXBridge(fromLibraryFolder folder: URL, usingStore store: URL) {
        let fileManager = FileManager.default
        let bridge = metalFXBridgePE(inLibraryFolder: folder)
        let bridgeExists = fileManager.fileExists(atPath: bridge.path(percentEncoded: false))
        let installedByUs = isMetalFXBridgeInstalled(inLibraryFolder: folder, usingStore: store)
        if installedByUs {
            try? fileManager.removeItem(at: bridge)
        }

        // Clean up our half of an interrupted install even when the PE copy never landed,
        // but keep a complete foreign bridge (including a same-target unix half) together.
        let link = metalFXBridgeUnixLink(inLibraryFolder: folder)
        let target = try? fileManager.destinationOfSymbolicLink(atPath: link.path(percentEncoded: false))
        if installedByUs || !bridgeExists, target == unixLinkDestination {
            try? fileManager.removeItem(at: link)
        }
    }

    // MARK: - Prefixes

    /// Drops a placeholder for the bridge into a prefix's `system32`.
    ///
    /// Not optional and not cosmetic: with no entry there the loader never looks
    /// in the builtin directory, and `LoadLibrary("nvngx.dll")` fails with
    /// `ERROR_MOD_NOT_FOUND` however well the tree is set up. `wineboot` writes
    /// one whenever a prefix is made or updated, so new bottles get it for free;
    /// every bottle that already exists predates the name.
    static func seedMetalFXBridgePlaceholder(inBottle bottle: URL, fromLibraryFolder folder: URL) {
        let fileManager = FileManager.default
        let source = metalFXBridgePE(inLibraryFolder: folder)
        guard fileManager.fileExists(atPath: source.path(percentEncoded: false)) else { return }

        let system32 = bottle.appending(path: "drive_c").appending(path: "windows")
            .appending(path: "system32")
        guard fileManager.fileExists(atPath: system32.path(percentEncoded: false)) else { return }

        let placeholder = system32.appending(path: metalFXBridgeName)
        guard !fileManager.fileExists(atPath: placeholder.path(percentEncoded: false)) else { return }
        try? fileManager.copyItem(at: source, to: placeholder)
    }

    /// Takes a prefix's placeholder back out, which makes the bridge unreachable
    /// from that bottle without touching the shared tree.
    ///
    /// Removes any builtin-marked entry, not just a copy this app wrote:
    /// `wineboot` writes its own stub for every builtin it finds, so a prefix
    /// update after the bridge was installed recreates one, and leaving that in
    /// place would quietly defeat the opt-out. A *native* DLL is left alone,
    /// that is someone's own `nvngx`, not something we or Wine put there.
    static func clearMetalFXBridgePlaceholder(inBottle bottle: URL) {
        let placeholder = bottle.appending(path: "drive_c").appending(path: "windows")
            .appending(path: "system32").appending(path: metalFXBridgeName)
        guard FileManager.default.fileExists(atPath: placeholder.path(percentEncoded: false)) else { return }
        guard (try? Wine.isNativePE(placeholder)) == false else { return }
        try? FileManager.default.removeItem(at: placeholder)
    }

    /// Installs the bridge into a tree that already holds the payload.
    ///
    /// An install set up before the bridge existed has the payload deployed and
    /// never deploys again, so it would stay without MetalFX until it happened
    /// to reimport. Idempotent and cheap enough to run at launch.
    ///
    /// Deliberately seeds no prefixes. The tree-side bridge is inert on its own,
    /// and which bottles can reach it is ``Wine/applyMetalFX(bottle:)``'s
    /// decision at launch, from the per-bottle setting.
    public static func ensureMetalFXBridgeInstalled() {
        let folder = WhiskyWineInstaller.libraryFolder
        guard isDeployed(inLibraryFolder: folder) else { return }

        do {
            try installMetalFXBridge(intoLibraryFolder: folder, usingStore: storeFolder)
        } catch {
            logger.error("Installing the MetalFX bridge failed: \(error.localizedDescription)")
        }
    }
}
