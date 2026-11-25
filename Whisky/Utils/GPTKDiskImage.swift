//
//  GPTKDiskImage.swift
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

import Foundation
import WhiskyKit

/// Mounts Apple's GPTK disk images long enough to import their payload.
///
/// The user may hand us the outer Game Porting Toolkit image (which contains
/// the evaluation-environment image), the evaluation-environment image
/// itself, an already-mounted volume, a bare folder, or an app named
/// "Game Porting Toolkit.app" (#413). Everything resolves to the `lib`
/// payload root, plus the list of mount points to detach once the import
/// completes.
enum GPTKDiskImage {
    /// A resolved payload location and the mounts holding it open.
    struct ResolvedPayload {
        let libRoot: URL
        let mounts: [URL]
    }

    enum DiskImageError: LocalizedError {
        case attachFailed(String)
        /// An app was chosen that doesn't carry D3DMetal, such as a wrapper
        /// that only shares the toolkit's name.
        case appWithoutPayload(String)

        var errorDescription: String? {
            switch self {
            case let .attachFailed(detail):
                String(localized: "gptk.error.attachFailed") + " " + detail
            case let .appWithoutPayload(name):
                String(localized: "gptk.error.appWithoutPayload \(name)")
            }
        }
    }

    /// Resolves `url` (image or folder) to a GPTK payload root, attaching
    /// images as needed. Callers must ``detach(_:)`` every returned mount.
    static func resolvePayload(at url: URL) throws -> ResolvedPayload {
        if let lib = GPTKImporter.locatePayload(under: url) {
            return ResolvedPayload(libRoot: lib, mounts: [])
        }

        let isDiskImage = url.pathExtension.lowercased() == "dmg"
        let isApp = url.pathExtension.lowercased() == "app"
        guard isDiskImage || isApp else {
            throw GPTKImportError.payloadNotFound
        }

        var mounts: [URL] = []
        do {
            // An app may still carry the evaluation environment as an image
            // in its resources; a disk image is attached and searched.
            let searchRoots: [URL]
            if isDiskImage {
                let outer = try attach(url)
                mounts.append(outer)
                if let lib = GPTKImporter.locatePayload(under: outer) {
                    return ResolvedPayload(libRoot: lib, mounts: mounts)
                }
                searchRoots = [outer]
            } else {
                let contents = url.appending(path: "Contents")
                searchRoots = [
                    contents.appending(path: "Resources"),
                    contents.appending(path: "SharedSupport")
                ]
            }

            // The outer GPTK image carries the evaluation environment as a
            // nested image; attach the first one that yields a payload.
            for root in searchRoots {
                let contents = (try? FileManager.default.contentsOfDirectory(
                    at: root, includingPropertiesForKeys: nil
                )) ?? []
                for nested in contents where nested.pathExtension.lowercased() == "dmg" {
                    let inner = try attach(nested)
                    mounts.append(inner)
                    if let lib = GPTKImporter.locatePayload(under: inner) {
                        return ResolvedPayload(libRoot: lib, mounts: mounts)
                    }
                }
            }
            if isApp {
                throw DiskImageError.appWithoutPayload(url.deletingPathExtension().lastPathComponent)
            }
            throw GPTKImportError.payloadNotFound
        } catch {
            for mount in mounts.reversed() {
                detach(mount)
            }
            throw error
        }
    }

    /// Attaches a disk image read-only and returns its mount point.
    static func attach(_ image: URL) throws -> URL {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/hdiutil")
        process.arguments = [
            "attach", "-readonly", "-nobrowse", "-plist", image.path(percentEncoded: false)
        ]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, format: nil
              ) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let mountPoint = entities.compactMap({ $0["mount-point"] as? String }).first
        else {
            throw DiskImageError.attachFailed(image.lastPathComponent)
        }
        return URL(filePath: mountPoint)
    }

    /// Detaches a mount point; failures are ignored (the mount stays behind
    /// for the user, nothing is lost).
    static func detach(_ mountPoint: URL) {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/hdiutil")
        process.arguments = ["detach", mountPoint.path(percentEncoded: false)]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
    }
}
