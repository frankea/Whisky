//
//  Wine+DXMTGameFolder.swift
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

import CryptoKit
import Foundation
import os.log

/// What a launch does with the DXMT copies Whisky keeps beside a game's executables.
///
/// A launcher that carries a game's plan, such as `steam.exe -applaunch`, keeps
/// DXVK in `system32`, since its own Chromium processes need it, and one
/// `system32` cannot hold both layers: both ship `d3d11.dll`. A game whose plan
/// is DXMT gets DXMT's trio in its own folder instead, which Wine's loader
/// searches before `system32` for a native DLL (#378).
enum DXMTGameFolderAction: Equatable {
    /// A launcher carries the game's DXMT plan: the trio goes beside each of
    /// the game's executables, and copies already there are kept current.
    case deploy
    /// The game itself starts on DXMT, which `system32` serves: copies already
    /// beside it are kept current, and none are added.
    case refresh
    /// The launch's plan is not DXMT: the copies Whisky placed beside the
    /// game are removed, so they cannot take over from the plan's layer.
    case remove

    /// The action for a launch.
    ///
    /// - Parameters:
    ///   - effectiveBackend: The launch's backend after overrides and `.recommended` resolution.
    ///   - launcherCarriesDescendantPlan: Whether a launcher is started to carry a game's plan.
    init(effectiveBackend: GraphicsBackend, launcherCarriesDescendantPlan: Bool) {
        if effectiveBackend == .dxmt {
            self = launcherCarriesDescendantPlan ? .deploy : .refresh
        } else {
            self = .remove
        }
    }
}

/// The DXMT copies Whisky placed in a bottle's game folders, each with the
/// SHA-256 of what it wrote, so a copy is only ever replaced or removed while
/// it is still exactly what Whisky put there.
struct DXMTGameFolderRecord: Codable, Equatable {
    /// Each copy's path relative to the bottle's `drive_c`, to its lowercase hex SHA-256.
    var copies: [String: String] = [:]

    static func url(in bottleURL: URL) -> URL {
        bottleURL.appending(path: ".dxmt-game-folder-copies.plist")
    }

    /// The bottle's record, or an empty one when there is none or it cannot be read.
    static func load(from bottleURL: URL) -> DXMTGameFolderRecord {
        guard let data = try? Data(contentsOf: url(in: bottleURL)),
              let record = try? PropertyListDecoder().decode(DXMTGameFolderRecord.self, from: data)
        else { return DXMTGameFolderRecord() }
        return record
    }

    /// Writes the record, or removes the file once no copy is left.
    func save(to bottleURL: URL) throws {
        let url = Self.url(in: bottleURL)
        guard !copies.isEmpty else {
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: url)
            }
            return
        }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    /// Whether any copy is recorded in the folder with the given key.
    func hasCopies(inFolder key: String) -> Bool {
        Wine.dxmtGameFolderDLLs.contains { copies[DXMTGameFolder.key(key, $0)] != nil }
    }
}

/// A folder holding game executables, once it is known to be one Whisky may write into.
struct DXMTGameFolder {
    /// The folder with its symbolic links resolved.
    let url: URL
    /// Its path relative to the bottle's `drive_c`.
    let key: String
    /// The executables the launch named in it.
    var executables: [URL]

    /// The record key of `dll` in the folder with key `folder`.
    static func key(_ folder: String, _ dll: String) -> String {
        folder.isEmpty ? dll : "\(folder)/\(dll)"
    }

    func key(for dll: String) -> String {
        Self.key(key, dll)
    }
}

extension Wine {
    /// DXMT's trio as a game folder gets it. `winemetal.dll` stays in
    /// `system32` only, where its builtin redirect already serves the trio.
    static let dxmtGameFolderDLLs = ["d3d11.dll", "d3d10core.dll", "dxgi.dll"]

    /// Places, refreshes or removes DXMT's trio beside a game's executables.
    ///
    /// Never fails the launch: whatever goes wrong is logged, and a folder that
    /// does not get the trio runs the game on what `system32` holds, as before.
    ///
    /// Only folders inside the bottle's `drive_c` are written, with symbolic
    /// links resolved, and never one under `drive_c/windows`. A folder gets
    /// the whole trio or none of it: when the game ships one of the three
    /// itself, the folder is left to the game, and so is anything Whisky did
    /// not place there. A copy is removed or replaced only while its content
    /// still matches what the bottle's record says Whisky wrote.
    ///
    /// - Parameters:
    ///   - action: What this launch does with the copies.
    ///   - executables: The game's executables, or the program being launched.
    ///   - bottleURL: The bottle they are in.
    ///   - payloadRoot: The DXMT payload, with an `x64` and an `x32` folder.
    static func reconcileDXMTGameFolders(
        _ action: DXMTGameFolderAction, executables: [URL], bottleURL: URL, payloadRoot: URL
    ) {
        let original = DXMTGameFolderRecord.load(from: bottleURL)
        // Only a deploy places copies; without any recorded, nothing else has work to do.
        guard action == .deploy || !original.copies.isEmpty else { return }
        var record = original
        var placed: [URL] = []
        for folder in dxmtGameFolders(for: executables, bottleURL: bottleURL) {
            switch action {
            case .deploy:
                deployDXMTTrio(into: folder, payloadRoot: payloadRoot, record: &record, placed: &placed)
            case .refresh where record.hasCopies(inFolder: folder.key):
                deployDXMTTrio(into: folder, payloadRoot: payloadRoot, record: &record, placed: &placed)
            case .refresh:
                continue
            case .remove:
                removeDXMTCopies(in: folder, record: &record)
            }
        }
        guard record != original else { return }
        do {
            try record.save(to: bottleURL)
        } catch {
            // Untracked copies could never be taken back, so they go now.
            Logger.wineKit.warning(
                "Could not save the DXMT game folder record: \(error.localizedDescription, privacy: .public)"
            )
            for url in placed {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// The folders of `executables` Whisky may write into, each once, in the order given.
    static func dxmtGameFolders(for executables: [URL], bottleURL: URL) -> [DXMTGameFolder] {
        let driveC = bottleURL.appending(path: "drive_c").standardizedFileURL.resolvingSymlinksInPath()
        let driveCComponents = driveC.pathComponents.map { $0.lowercased() }
        var folders: [DXMTGameFolder] = []
        for executable in executables {
            let folder = executable.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
            let components = folder.pathComponents
            guard components.count >= driveCComponents.count,
                  components.prefix(driveCComponents.count).map({ $0.lowercased() }) == driveCComponents
            else {
                Logger.wineKit.debug("Leaving the folder of an executable outside drive_c alone")
                continue
            }
            let relative = Array(components.dropFirst(driveCComponents.count))
            guard relative.first?.lowercased() != "windows", isDirectory(folder) else { continue }
            let key = relative.joined(separator: "/")
            if let index = folders.firstIndex(where: { $0.key.lowercased() == key.lowercased() }) {
                folders[index].executables.append(executable)
            } else {
                folders.append(DXMTGameFolder(url: folder, key: key, executables: [executable]))
            }
        }
        return folders
    }

    /// The one architecture the folder's executables share, or `nil` when they
    /// disagree or none can be read.
    static func dxmtGameFolderArchitecture(_ folder: DXMTGameFolder) -> Architecture? {
        let architectures = Set(folder.executables.compactMap { try? PEFile(url: $0).architecture })
            .subtracting([.unknown])
        return architectures.count == 1 ? architectures.first : nil
    }

    /// What a trio file in a game folder is, as far as a deploy is concerned.
    private enum DXMTCopyState {
        /// Nothing there.
        case absent
        /// Whisky's copy, as recorded.
        case placed
        /// Not Whisky's, but the payload's own bytes: left in place and not recorded.
        case identical
        /// The game's own, or anything else Whisky did not place.
        case foreign
    }

    /// One trio file a deploy writes.
    private struct DXMTCopyWrite {
        let dll: String
        let source: URL
        /// The SHA-256 of what is written.
        let hash: String
        /// Whether nothing was there before, so whatever is there after a failure is Whisky's.
        let wasAbsent: Bool
        /// The SHA-256 of Whisky's copy that was there before.
        let recorded: String?
    }

    private static func dxmtCopyState(of url: URL, recorded: String?, source: Data) -> DXMTCopyState {
        if isSymbolicLink(url) {
            return .foreign
        }
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return .absent }
        guard let data = try? Data(contentsOf: url) else { return .foreign }
        if let recorded, sha256(data) == recorded {
            return .placed
        }
        return data == source ? .identical : .foreign
    }

    /// Places the payload's trio for the folder's architecture, or leaves the
    /// folder as it was.
    private static func deployDXMTTrio(
        into folder: DXMTGameFolder, payloadRoot: URL, record: inout DXMTGameFolderRecord, placed: inout [URL]
    ) {
        guard let architecture = dxmtGameFolderArchitecture(folder) else {
            Logger.wineKit.info("Not placing DXMT in a game folder whose executables have no single architecture")
            return
        }
        let payload = payloadRoot.appending(path: architecture == .x32 ? "x32" : "x64")
        let sources = dxmtGameFolderDLLs.map { payload.appending(path: $0) }
        let sourceData = sources.compactMap { url in
            (try? isNativePE(url)) == true ? try? Data(contentsOf: url) : nil
        }
        guard sourceData.count == sources.count else {
            Logger.wineKit.info("The DXMT payload has no native trio for a game folder's architecture")
            return
        }

        var writes: [DXMTCopyWrite] = []
        for (index, dll) in dxmtGameFolderDLLs.enumerated() {
            let destination = folder.url.appending(path: dll)
            let recorded = record.copies[folder.key(for: dll)]
            let state = dxmtCopyState(of: destination, recorded: recorded, source: sourceData[index])
            switch state {
            case .absent, .placed:
                writes.append(DXMTCopyWrite(
                    dll: dll, source: sources[index], hash: sha256(sourceData[index]),
                    wasAbsent: state == .absent, recorded: state == .placed ? recorded : nil
                ))
            case .identical:
                record.copies[folder.key(for: dll)] = nil
            case .foreign:
                Logger.wineKit.info("Not placing DXMT beside a game that ships its own \(dll, privacy: .public)")
                record.copies[folder.key(for: dll)] = nil
                removeDXMTCopies(in: folder, record: &record)
                return
            }
        }

        placed += writeDXMTTrio(writes, into: folder, record: &record)
    }

    /// Writes a deploy's trio files, or, when one fails, takes back every copy
    /// of the folder that is Whisky's, so the folder never keeps a partial set.
    ///
    /// - Returns: The files written.
    private static func writeDXMTTrio(
        _ writes: [DXMTCopyWrite], into folder: DXMTGameFolder, record: inout DXMTGameFolderRecord
    ) -> [URL] {
        var written: [URL] = []
        do {
            for write in writes {
                let destination = folder.url.appending(path: write.dll)
                try FileManager.default.installFileIfContentDiffers(at: destination, from: write.source)
                record.copies[folder.key(for: write.dll)] = write.hash
                written.append(destination)
            }
            return written
        } catch {
            Logger.wineKit.warning(
                "Could not place DXMT in a game folder: \(error.localizedDescription, privacy: .public)"
            )
            for write in writes {
                let destination = folder.url.appending(path: write.dll)
                let hashes = Set([write.hash, write.recorded].compactMap { $0 })
                if write.wasAbsent || fileHash(destination).map(hashes.contains) == true {
                    try? FileManager.default.removeItem(at: destination)
                }
                record.copies[folder.key(for: write.dll)] = nil
            }
            return []
        }
    }

    /// Removes the folder's recorded copies whose content still matches the record.
    private static func removeDXMTCopies(in folder: DXMTGameFolder, record: inout DXMTGameFolderRecord) {
        for dll in dxmtGameFolderDLLs {
            let key = folder.key(for: dll)
            guard let recorded = record.copies[key] else { continue }
            let url = folder.url.appending(path: dll)
            guard !isSymbolicLink(url), fileHash(url) == recorded else {
                // Gone, or no longer what Whisky wrote: not Whisky's to remove.
                record.copies[key] = nil
                continue
            }
            do {
                try FileManager.default.removeItem(at: url)
                record.copies[key] = nil
            } catch {
                let reason = error.localizedDescription
                Logger.wineKit.warning(
                    "Could not remove DXMT's \(dll, privacy: .public) from a game folder: \(reason, privacy: .public)"
                )
            }
        }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func fileHash(_ url: URL) -> String? {
        (try? Data(contentsOf: url)).map(sha256)
    }

    private static func isSymbolicLink(_ url: URL) -> Bool {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        return (attributes?[.type] as? FileAttributeType) == .typeSymbolicLink
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
}
