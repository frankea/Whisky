//
//  GPTKImporter+NVAPI.swift
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

/// Apple's NVAPI, which is what makes MetalFX reachable in practice.
///
/// The MetalFX bridge answers NGX, but nothing asks NGX until NVAPI has said
/// there is an NVIDIA GPU behind it. NVIDIA Streamline, which is how most
/// current games reach DLSS, queries NVAPI first and stops there when it finds
/// nothing: measured on Deep Rock Galactic, a relay trace scoped to `nvngx.*`
/// recorded zero `NVSDK_NGX_*` calls and the game offered no DLSS option at all,
/// with no error to explain it. Wine's own `nvapi64` is a placeholder that
/// exports nothing, so that is the answer every game got.
///
/// Deploying it has a cost, which is why it stayed in the store for so long:
/// Chromium probes for an NVIDIA GPU on startup, and answering makes it load
/// D3DMetal and take a launcher's helper process down with it. That is handled
/// per executable instead of by withholding the DLL from everything, in
/// ``Wine.disablingNVAPI(in:)``.
extension GPTKImporter {
    /// Wine's placeholder, kept beside the deployed bridge so removal can put the
    /// tree back without consulting the per-runtime originals record.
    static let nvapiPlaceholderSuffix = ".wine-placeholder"

    /// Where the bridge lives in the store, or `nil` for a payload without one.
    static func nvapiBridgeSource(inStore store: URL) -> URL? {
        let source = store.appending(path: "lib").appending(path: "wine")
            .appending(path: "x86_64-windows").appending(path: nvapiBridgeName)
        return FileManager.default.fileExists(atPath: source.path(percentEncoded: false)) ? source : nil
    }

    static func nvapiBridgePE(inLibraryFolder folder: URL) -> URL {
        folder.appending(path: "Wine").appending(path: "lib").appending(path: "wine")
            .appending(path: "x86_64-windows").appending(path: nvapiBridgeName)
    }

    static func nvapiBridgeUnixLink(inLibraryFolder folder: URL) -> URL {
        folder.appending(path: "Wine").appending(path: "lib").appending(path: "wine")
            .appending(path: "x86_64-unix").appending(path: nvapiBridgeUnixName)
    }

    static func nvapiPlaceholderBackup(inLibraryFolder folder: URL) -> URL {
        nvapiBridgePE(inLibraryFolder: folder).appendingPathExtension(
            String(nvapiPlaceholderSuffix.dropFirst())
        )
    }

    /// Whether the tree holds a bridge this store put there.
    static func isNVAPIBridgeInstalled(inLibraryFolder folder: URL, usingStore store: URL) -> Bool {
        guard let source = nvapiBridgeSource(inStore: store) else { return false }
        return FileManager.default.contentsEqual(
            atPath: nvapiBridgePE(inLibraryFolder: folder).path(percentEncoded: false),
            andPath: source.path(percentEncoded: false)
        )
    }

    /// Puts the bridge in the tree with a unix half beside it, keeping Wine's
    /// placeholder so ``removeNVAPIBridge(fromLibraryFolder:usingStore:)`` can
    /// put it back.
    ///
    /// Unlike the MetalFX bridge this is not purely additive: Wine ships an
    /// `nvapi64` of its own, so the file being replaced is backed up rather than
    /// overwritten.
    static func installNVAPIBridge(intoLibraryFolder folder: URL, usingStore store: URL) throws {
        guard let source = nvapiBridgeSource(inStore: store) else { return }
        guard !isNVAPIBridgeInstalled(inLibraryFolder: folder, usingStore: store) else { return }
        let fileManager = FileManager.default
        let destination = nvapiBridgePE(inLibraryFolder: folder)
        let backup = nvapiPlaceholderBackup(inLibraryFolder: folder)
        let link = nvapiBridgeUnixLink(inLibraryFolder: folder)

        if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
            // Only the first install backs up: a second one would otherwise save
            // Apple's DLL over the placeholder and lose it for good.
            if !fileManager.fileExists(atPath: backup.path(percentEncoded: false)) {
                try fileManager.copyItem(at: destination, to: backup)
            }
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)

        try fileManager.createDirectory(
            at: link.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? fileManager.removeItem(at: link)
        try fileManager.createSymbolicLink(
            atPath: link.path(percentEncoded: false),
            withDestinationPath: unixLinkDestination
        )
        logger.info("Installed Apple's NVAPI as \(nvapiBridgeName, privacy: .public)")
    }

    /// Takes the bridge back out and restores Wine's placeholder.
    static func removeNVAPIBridge(fromLibraryFolder folder: URL, usingStore store: URL) {
        let fileManager = FileManager.default
        guard isNVAPIBridgeInstalled(inLibraryFolder: folder, usingStore: store) else { return }
        let destination = nvapiBridgePE(inLibraryFolder: folder)
        let backup = nvapiPlaceholderBackup(inLibraryFolder: folder)

        try? fileManager.removeItem(at: destination)
        if fileManager.fileExists(atPath: backup.path(percentEncoded: false)) {
            try? fileManager.moveItem(at: backup, to: destination)
        }

        let link = nvapiBridgeUnixLink(inLibraryFolder: folder)
        let target = try? fileManager.destinationOfSymbolicLink(atPath: link.path(percentEncoded: false))
        if target == unixLinkDestination {
            try? fileManager.removeItem(at: link)
        }
    }

    /// Installs the bridge into a tree that already holds the payload, so an
    /// install set up before this existed picks it up without reimporting.
    /// Idempotent and cheap enough to run at launch, like the MetalFX half.
    public static func ensureNVAPIBridgeInstalled() {
        let folder = WhiskyWineInstaller.libraryFolder
        guard isDeployed(inLibraryFolder: folder) else { return }

        do {
            try installNVAPIBridge(intoLibraryFolder: folder, usingStore: storeFolder)
        } catch {
            logger.error("Installing Apple's NVAPI failed: \(error.localizedDescription)")
        }
    }
}
