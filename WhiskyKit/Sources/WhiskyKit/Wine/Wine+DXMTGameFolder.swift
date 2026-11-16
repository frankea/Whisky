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

extension Wine {
    /// DXMT's trio as a game folder gets it. `winemetal.dll` stays in
    /// `system32` only, where its builtin redirect already serves the trio.
    static let dxmtGameFolderDLLs = ["d3d11.dll", "d3d10core.dll", "dxgi.dll"]

    /// Copies one trio file from the payload (the second URL) into a game folder (the first).
    typealias DXMTFileInstaller = (_ destination: URL, _ source: URL) throws -> Void

    /// Places, refreshes or removes DXMT's trio beside a game's executables.
    ///
    /// Never fails the launch: whatever goes wrong is logged, and a folder that
    /// does not get the trio runs the game on what `system32` holds, as before.
    ///
    /// Only folders inside the bottle's `drive_c` are written, with symbolic
    /// links resolved, and never one under `drive_c/windows`. A folder gets
    /// the whole trio or none of it: when the game ships one of the three
    /// itself, under any spelling, the folder is left to the game. A copy is
    /// removed or replaced only while its content still matches what the
    /// bottle's record says Whisky wrote, or the payload's own bytes.
    ///
    /// Besides the folders of `executables`, the folders of the same game
    /// that hold recorded copies follow the action too, so a launch of an
    /// Unreal game's root stub also keeps its `Binaries/Win64` in step.
    ///
    /// - Parameters:
    ///   - action: What this launch does with the copies.
    ///   - executables: The game's executables, or the program being launched.
    ///   - bottleURL: The bottle they are in.
    ///   - payloadRoot: The DXMT payload, with an `x64` and an `x32` folder.
    ///   - folders: Folders of the game named without an executable, such as its install folder.
    ///     They get no trio of their own, having no executable to choose its architecture.
    ///   - installer: What copies a trio file into place. Tests make it fail.
    static func reconcileDXMTGameFolders(
        _ action: DXMTGameFolderAction, executables: [URL], bottleURL: URL, payloadRoot: URL,
        folders: [URL] = [],
        installer: @escaping DXMTFileInstaller = installDXMTFile(at:from:)
    ) {
        DXMTGameFolderRecord.withLock(in: bottleURL) {
            let original = DXMTGameFolderRecord.load(from: bottleURL)
            // A refresh only touches recorded copies; without any, it has nothing to do.
            guard action != .refresh || !original.copies.isEmpty else { return }
            let driveC = dxmtDriveC(bottleURL)
            var state = DXMTReconcileState(payloadRoot: payloadRoot, installer: installer, record: original)
            // A folder that is gone took its copies with it.
            state.record.copies = original.copies.filter { key, _ in
                isDirectory(driveC.appending(path: DXMTGameFolder.folderKey(ofCopy: key)))
            }

            let named = namedDXMTGameFolders(executables: executables, folders: folders, bottleURL: bottleURL)
            for folder in named {
                applyDXMTAction(action, to: folder, state: &state)
            }
            // Every one of these holds recorded copies, so refreshing them is what a deploy does too.
            for folder in sameGameRecordedFolders(of: named, record: state.record, bottleURL: bottleURL) {
                applyDXMTAction(action == .remove ? .remove : .refresh, to: folder, state: &state)
            }

            guard state.record != original else { return }
            do {
                try state.record.save(to: bottleURL)
            } catch {
                // Untracked copies could never be taken back, so they go now.
                Logger.wineKit.warning(
                    "Could not save the DXMT game folder record: \(error.localizedDescription, privacy: .public)"
                )
                for url in state.placed {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
    }

    /// The folders of `executables`, then those of `folders` not already among them.
    private static func namedDXMTGameFolders(
        executables: [URL], folders: [URL], bottleURL: URL
    ) -> [DXMTGameFolder] {
        let driveC = dxmtDriveC(bottleURL)
        var named = dxmtGameFolders(for: executables, bottleURL: bottleURL)
        for folder in folders {
            guard let (url, key) = dxmtWritableFolder(folder, driveC: driveC),
                  !named.contains(where: { $0.key.lowercased() == key.lowercased() })
            else { continue }
            named.append(DXMTGameFolder(url: url, key: key, executables: []))
        }
        return named
    }

    private static func applyDXMTAction(
        _ action: DXMTGameFolderAction, to folder: DXMTGameFolder, state: inout DXMTReconcileState
    ) {
        switch action {
        case .deploy:
            deployDXMTTrio(into: folder, state: &state)
        case .refresh where state.record.hasCopies(inFolder: folder.key):
            deployDXMTTrio(into: folder, state: &state)
        case .refresh:
            break
        case .remove:
            removeDXMTCopies(in: folder, state: &state)
        }
    }

    /// Copies a trio file into a game folder, unless it already holds the same bytes.
    static func installDXMTFile(at destination: URL, from source: URL) throws {
        _ = try FileManager.default.installFileIfContentDiffers(at: destination, from: source)
    }

    /// The folders of `executables` Whisky may write into, each once, in the order given.
    static func dxmtGameFolders(for executables: [URL], bottleURL: URL) -> [DXMTGameFolder] {
        let driveC = dxmtDriveC(bottleURL)
        var folders: [DXMTGameFolder] = []
        for executable in executables {
            guard let (folderURL, key) = dxmtWritableFolder(executable.deletingLastPathComponent(), driveC: driveC)
            else { continue }
            if let index = folders.firstIndex(where: { $0.key.lowercased() == key.lowercased() }) {
                folders[index].executables.append(executable)
            } else {
                folders.append(DXMTGameFolder(url: folderURL, key: key, executables: [executable]))
            }
        }
        return folders
    }

    /// The key of `folder` relative to the bottle's `drive_c`, when Whisky may write into it.
    static func dxmtGameFolderKey(_ folder: URL, bottleURL: URL) -> String? {
        dxmtWritableFolder(folder, driveC: dxmtDriveC(bottleURL))?.1
    }

    /// The architecture of the folder's largest readable executable, which is
    /// the game rather than a helper beside it, or `nil` when none can be read.
    ///
    /// A trio of the other architecture is harmless to a helper: Wine's loader
    /// skips a native DLL whose machine does not match and keeps searching.
    static func dxmtGameFolderArchitecture(_ folder: DXMTGameFolder) -> Architecture? {
        let candidates = folder.executables.compactMap { url -> (architecture: Architecture, size: Int)? in
            guard let architecture = try? PEFile(url: url).architecture, architecture != .unknown else { return nil }
            return (architecture, (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return candidates.max { $0.size < $1.size }?.architecture
    }

    /// The bottle's `drive_c` with its symbolic links resolved.
    private static func dxmtDriveC(_ bottleURL: URL) -> URL {
        bottleURL.appending(path: "drive_c").standardizedFileURL.resolvingSymlinksInPath()
    }

    /// `folder` resolved, and its key, when it is a folder inside `drive_c` and outside `drive_c/windows`.
    private static func dxmtWritableFolder(_ folder: URL, driveC: URL) -> (URL, String)? {
        let driveCComponents = driveC.pathComponents.map { $0.lowercased() }
        let resolved = folder.standardizedFileURL.resolvingSymlinksInPath()
        let components = resolved.pathComponents
        guard components.count >= driveCComponents.count,
              components.prefix(driveCComponents.count).map({ $0.lowercased() }) == driveCComponents
        else {
            Logger.wineKit.debug("Leaving the folder of an executable outside drive_c alone")
            return nil
        }
        let relative = Array(components.dropFirst(driveCComponents.count))
        guard relative.first?.lowercased() != "windows", isDirectory(resolved) else { return nil }
        return (resolved, relative.joined(separator: "/"))
    }

    /// The folders holding recorded copies that belong to the same game as
    /// one of `named`, other than `named` themselves, with the executables in each.
    private static func sameGameRecordedFolders(
        of named: [DXMTGameFolder], record: DXMTGameFolderRecord, bottleURL: URL
    ) -> [DXMTGameFolder] {
        let driveC = dxmtDriveC(bottleURL)
        let namedKeys = Set(named.map { $0.key.lowercased() })
        return record.folderKeys.sorted().compactMap { key in
            guard !namedKeys.contains(key.lowercased()), named.contains(where: { $0.belongsToSameGame(key) }),
                  let (url, resolvedKey) = dxmtWritableFolder(driveC.appending(path: key), driveC: driveC),
                  resolvedKey.lowercased() == key.lowercased()
            else { return nil }
            let entries = folderEntries(url)
            let executables = entries.filter { $0.lowercased().hasSuffix(".exe") }.map { url.appending(path: $0) }
            return DXMTGameFolder(url: url, key: key, executables: executables)
        }
    }

    /// What one reconcile carries from folder to folder.
    private struct DXMTReconcileState {
        let payloadRoot: URL
        let installer: DXMTFileInstaller
        var record: DXMTGameFolderRecord
        /// The files this reconcile placed, which go again if the record cannot be saved.
        var placed: [URL] = []
    }

    /// What a trio file in a game folder is, as far as a deploy is concerned.
    private enum DXMTCopyState {
        /// Nothing there.
        case absent
        /// Whisky's copy, as recorded.
        case placed
        /// Not recorded, but the payload's own bytes: adopted once the whole trio is in place.
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

    private static func dxmtCopyState(
        of dll: String, in folder: DXMTGameFolder, entries: [String], recorded: String?, source: Data
    ) -> DXMTCopyState {
        // On a case-sensitive volume `DXGI.dll` is a file of its own, and still the game's.
        if entries.contains(where: { $0.lowercased() == dll && $0 != dll }) {
            return .foreign
        }
        let url = folder.url.appending(path: dll)
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
    private static func deployDXMTTrio(into folder: DXMTGameFolder, state: inout DXMTReconcileState) {
        guard let architecture = dxmtGameFolderArchitecture(folder) else {
            Logger.wineKit.info("Not placing DXMT in a game folder with no readable executable")
            return
        }
        let payload = state.payloadRoot.appending(path: architecture == .x32 ? "x32" : "x64")
        let sources = dxmtGameFolderDLLs.map { payload.appending(path: $0) }
        let sourceData = sources.compactMap { url in
            (try? isNativePE(url)) == true ? try? Data(contentsOf: url) : nil
        }
        guard sourceData.count == sources.count else {
            Logger.wineKit.info("The DXMT payload has no native trio for a game folder's architecture")
            return
        }

        let entries = folderEntries(folder.url)
        var writes: [DXMTCopyWrite] = []
        for (index, dll) in dxmtGameFolderDLLs.enumerated() {
            let recorded = state.record.copies[folder.key(for: dll)]
            let copyState = dxmtCopyState(
                of: dll, in: folder, entries: entries, recorded: recorded, source: sourceData[index]
            )
            guard copyState != .foreign else {
                Logger.wineKit.info("Not placing DXMT beside a game that ships its own \(dll, privacy: .public)")
                state.record.copies[folder.key(for: dll)] = nil
                removeDXMTCopies(in: folder, state: &state)
                return
            }
            writes.append(DXMTCopyWrite(
                dll: dll, source: sources[index], hash: sha256(sourceData[index]),
                wasAbsent: copyState == .absent, recorded: copyState == .placed ? recorded : nil
            ))
        }

        writeDXMTTrio(writes, into: folder, state: &state)
    }

    /// Writes a deploy's trio files, or, when one fails, takes back every copy
    /// of the folder that is Whisky's, so the folder never keeps a partial set.
    /// An adopted file predates this deploy and stays, untracked as it was.
    private static func writeDXMTTrio(
        _ writes: [DXMTCopyWrite], into folder: DXMTGameFolder, state: inout DXMTReconcileState
    ) {
        var written: [URL] = []
        do {
            for write in writes {
                let destination = folder.url.appending(path: write.dll)
                try state.installer(destination, write.source)
                state.record.copies[folder.key(for: write.dll)] = write.hash
                // An adopted copy predates this reconcile, so a failed save leaves it be.
                if write.wasAbsent || write.recorded != nil {
                    written.append(destination)
                }
            }
            state.placed += written
        } catch {
            Logger.wineKit.warning(
                "Could not place DXMT in a game folder: \(error.localizedDescription, privacy: .public)"
            )
            for write in writes {
                let destination = folder.url.appending(path: write.dll)
                let hashes = Set([write.hash, write.recorded].compactMap { $0 })
                let wasWhiskys = write.recorded != nil && fileHash(destination).map(hashes.contains) == true
                if write.wasAbsent || wasWhiskys {
                    try? FileManager.default.removeItem(at: destination)
                }
                state.record.copies[folder.key(for: write.dll)] = nil
            }
        }
    }

    /// Removes the folder's recorded copies whose content still matches the
    /// record. A file the record does not name stays, even with the payload's
    /// bytes: Whisky cannot tell a copy whose record was lost from one the
    /// user put there, and a lost record's copies are adopted by the next deploy.
    private static func removeDXMTCopies(in folder: DXMTGameFolder, state: inout DXMTReconcileState) {
        let entries = folderEntries(folder.url)
        for dll in dxmtGameFolderDLLs {
            let key = folder.key(for: dll)
            let url = folder.url.appending(path: dll)
            // Only the exact spelling Whisky writes: on a case-insensitive volume
            // `DXGI.dll` answers to `dxgi.dll` too, and is still the game's.
            guard entries.contains(dll), !isSymbolicLink(url), let hash = fileHash(url) else {
                // Gone, or not Whisky's to remove.
                state.record.copies[key] = nil
                continue
            }
            guard state.record.copies[key] == hash else {
                // No longer what Whisky wrote: not Whisky's to remove.
                state.record.copies[key] = nil
                continue
            }
            do {
                try FileManager.default.removeItem(at: url)
                state.record.copies[key] = nil
            } catch {
                let reason = error.localizedDescription
                Logger.wineKit.warning(
                    "Could not remove DXMT's \(dll, privacy: .public) from a game folder: \(reason, privacy: .public)"
                )
            }
        }
    }

    /// The names in `folder`, as stored, or none when it cannot be read.
    private static func folderEntries(_ folder: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
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
