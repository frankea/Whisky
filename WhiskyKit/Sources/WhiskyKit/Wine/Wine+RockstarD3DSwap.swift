//
//  Wine+RockstarD3DSwap.swift
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

/// The file operations of the Rockstar swap, one closure each, so tests can
/// record their order and make any of them fail.
struct RockstarD3DFileOps {
    /// Copies a DXVK file into a copy folder, unless it already holds the same bytes.
    var installCopy: (_ destination: URL, _ source: URL) throws -> Void = { destination, source in
        _ = try FileManager.default.installFileIfContentDiffers(at: destination, from: source)
    }

    /// Removes a copy.
    var removeCopy: (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }

    /// Creates a folder for copies.
    var createFolder: (URL) throws -> Void = {
        try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
    }

    /// Removes a folder Whisky created, only while nothing but Finder's
    /// `.DS_Store` is in it.
    var removeFolderIfEmpty: (URL) -> Void = { url in
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false)),
              entries.allSatisfy({ $0 == ".DS_Store" })
        else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Deploys DXVK, with Wine's `d3d11` from the given source in `system32` or DXVK's own.
    var enableDXVK: @MainActor (
        _ bottle: Bottle, _ dxvkFolder: URL, _ system32D3D11Source: URL?, _ reconcileDXGI: (URL) -> Void
    ) throws -> Void = { bottle, dxvkFolder, source, reconcileDXGI in
        try Wine.enableDXVK(
            bottle: bottle, from: dxvkFolder, system32D3D11Source: source, reconcileDXGI: reconcileDXGI
        )
    }

    /// Writes the record.
    var saveRecord: (RockstarD3DLayoutRecord, URL) throws -> Void = { try $0.save(to: $1) }

    /// Removes the record.
    var removeRecord: (URL) throws -> Void = { try RockstarD3DLayoutRecord.remove(from: $0) }

    /// The operations on the real file system.
    static var live: RockstarD3DFileOps {
        RockstarD3DFileOps()
    }
}

/// One launch's work on the swap, carried through its steps.
struct RockstarD3DSwap {
    let bottle: Bottle
    let dxvkFolder: URL
    let launch: RockstarD3DLaunch
    let ops: RockstarD3DFileOps

    /// The bottle's `drive_c`, which the record's keys are relative to.
    var driveC: URL {
        Wine.rockstarDriveC(bottle.url)
    }

    var system32: URL {
        bottle.url.appending(path: "drive_c").appending(path: "windows").appending(path: "system32")
    }

    /// Puts the right `dxgi.dll` into the prefix, against the launch's runtime.
    func reconcileDXGI(_ prefixRoot: URL) {
        Wine.reconcileDXGIForDXVK(
            prefixRoot: prefixRoot, gptkPayloadIsDeployed: launch.payloadDeployed,
            libraryFolder: launch.runtime.libraryFolder, store: launch.runtime.store
        )
    }

    /// DXVK exactly as a launch deployed it before the swap existed.
    @MainActor
    func deployPlainDXVK() throws {
        try ops.enableDXVK(bottle, dxvkFolder, nil) { Wine.reconcileDXGIForDXVK(prefixRoot: $0) }
    }
}

/// What a swap writes, and the record it ends with.
struct RockstarD3DSwapPlan {
    /// DXVK's `d3d11.dll` and `d3d10core.dll` hashes, by name.
    var payload: [String: String]
    /// Each copy the swap wants, by key relative to `drive_c`, to its hash.
    var wanted: [String: String]
    /// Recorded copies no longer wanted, in folders that are still there.
    var stale: [String: String]
    /// The folders to create, parent first.
    var folders: [String]
    /// The record saved before anything is written.
    var interim: RockstarD3DLayoutRecord
    /// The record saved last, its `system32D3D11` filled in once the copy is in place.
    var final: RockstarD3DLayoutRecord
}

/// Why a swap stopped part way.
enum RockstarD3DSwapError: LocalizedError, Equatable {
    /// A file the swap needs cannot be read.
    case unreadable
    /// After the deploy, the named `system32` DLL is not Wine's stripped copy.
    case notInPlace(String)

    var errorDescription: String? {
        switch self {
        case .unreadable:
            "DXVK's d3d11 or d3d10core, Wine's d3d11 or the engine version cannot be read"
        case let .notInPlace(dll):
            "system32 \(dll) is not Wine's own after the deploy"
        }
    }
}

extension Wine {
    /// Puts the swapped layout in place, or keeps it, and returns it; or,
    /// when a step fails, puts DXVK back and returns why.
    ///
    /// Every file this may create is on record before it exists: a record
    /// naming the copies about to be written (with the payload's hash) is
    /// saved first, and the finished record last. A crash at any point leaves
    /// only files a teardown removes, since it removes a recorded copy that
    /// hashes to the record or to the payload. The copies are placed before
    /// `system32` changes, so a Chromium GPU process respawning in between
    /// already finds DXVK beside it. Then DXVK is deployed with Wine's `d3d11`
    /// in its `system32` slot, and both Wine files are checked: `dxgi` is only
    /// logged when it cannot be placed, and the launcher needs it.
    ///
    /// A bottle already in the layout writes none of the swap's files again:
    /// its copies, `system32\d3d11.dll` and the record keep their inode and
    /// modification date, and only the DXVK deploy every launch makes runs.
    ///
    /// - Parameters:
    ///   - swap: The launch's work.
    ///   - source: Wine's builtin-marked `d3d11.dll`.
    ///   - dxgiSource: Wine's builtin-marked `dxgi.dll`, which `system32` must hold stripped.
    ///   - scan: The bottle's consumers.
    ///   - onDisk: The record as loaded, and whether its file exists.
    @MainActor
    static func applySwap(
        _ swap: RockstarD3DSwap, source: URL, dxgiSource: URL?, scan: RockstarD3DConsumerScan,
        onDisk: (record: RockstarD3DLayoutRecord?, exists: Bool)
    ) throws -> RockstarD3DLayout {
        guard var plan = rockstarSwapPlan(swap, source: source, scan: scan, record: onDisk.record) else {
            return try failSwap(swap, RockstarD3DSwapError.unreadable, onDisk: onDisk)
        }
        let settled = plan.final.system32D3D11 != nil && onDisk.record == plan.final && plan.folders.isEmpty
            && plan.wanted.allSatisfy { key, hash in
                RockstarD3DLayoutRecord.sha256(of: swap.driveC.appending(path: key)) == hash
            }
        var onDisk = onDisk
        do {
            if !settled {
                if plan.interim != onDisk.record || !onDisk.exists {
                    try swap.ops.saveRecord(plan.interim, swap.bottle.url)
                    onDisk = (plan.interim, true)
                }
                try plan.final.copies.merge(placeRockstarCopies(swap, plan: plan)) { wanted, _ in wanted }
            }
            try swap.ops.enableDXVK(swap.bottle, swap.dxvkFolder, source, swap.reconcileDXGI)
            try verifySwap(system32: swap.system32, source: source, dxgiSource: dxgiSource)
        } catch {
            return try failSwap(swap, error, onDisk: onDisk)
        }
        guard !settled else {
            Logger.wineKit.info("Rockstar layout unchanged")
            return .swapped(source: source)
        }
        plan.final.system32D3D11 = RockstarD3DLayoutRecord.sha256(of: swap.system32.appending(path: "d3d11.dll"))
        do {
            try swap.ops.saveRecord(plan.final, swap.bottle.url)
        } catch {
            // The interim record already names every file, so a teardown still finds them all.
            Logger.wineKit.warning(
                "Could not finish the Rockstar layout record: \(error.localizedDescription, privacy: .public)"
            )
        }
        let count = plan.wanted.count
        Logger.wineKit.info("Rockstar layout swapped: Wine's d3d11 in system32, \(count) DXVK copies placed")
        return .swapped(source: source)
    }

    /// Puts DXVK back after a swap stopped, and returns why it stopped.
    @MainActor
    private static func failSwap(
        _ swap: RockstarD3DSwap, _ error: any Error, onDisk: (record: RockstarD3DLayoutRecord?, exists: Bool)
    ) throws -> RockstarD3DLayout {
        let reason = error.localizedDescription
        Logger.wineKit.warning("Could not swap the Rockstar layout: \(reason, privacy: .public)")
        if onDisk.exists {
            try tearDown(swap, record: onDisk.record)
        } else {
            try swap.deployPlainDXVK()
        }
        return .degraded(.swapFailed(reason))
    }

    /// What the swap writes and the records it saves, or `nil` when DXVK's
    /// files, Wine's `d3d11` or the engine's version cannot be read, which
    /// is found before anything is written.
    @MainActor
    static func rockstarSwapPlan(
        _ swap: RockstarD3DSwap, source: URL, scan: RockstarD3DConsumerScan, record: RockstarD3DLayoutRecord?
    ) -> RockstarD3DSwapPlan? {
        let payloadFolder = swap.dxvkFolder.appending(path: "x64")
        var payload: [String: String] = [:]
        for dll in rockstarD3DCopyDLLs {
            let url = payloadFolder.appending(path: dll)
            guard (try? isNativePE(url)) == true, let hash = RockstarD3DLayoutRecord.sha256(of: url) else { return nil }
            payload[dll] = hash
        }
        guard let stamp = GPTKImporter.runtimeVersionStamp(inLibraryFolder: swap.launch.runtime.libraryFolder),
              let sourceHash = RockstarD3DLayoutRecord.sha256(of: source)
        else { return nil }

        var wanted: [String: String] = [:]
        for folder in scan.copyFolders {
            for dll in rockstarD3DCopyDLLs {
                wanted[RockstarD3DLayoutRecord.key(folder.key, dll)] = payload[dll]
            }
        }
        // A recorded folder that is gone took its copies with it.
        let recorded = (record?.copies ?? [:]).filter { key, _ in
            rockstarIsDirectory(swap.driveC.appending(path: DXMTGameFolder.folderKey(ofCopy: key)))
        }
        let folders = scan.copyFolders.flatMap(\.create).filter {
            !rockstarEntryExists(swap.driveC.appending(path: $0))
        }
        let created = deepestFirst((record?.createdFolders ?? []) + folders)

        var interim = record ?? RockstarD3DLayoutRecord(engineStamp: stamp, sourceSHA256: sourceHash)
        interim.copies = recorded.merging(wanted) { old, _ in old }
        interim.createdFolders = created
        let d3d11 = swap.system32.appending(path: "d3d11.dll")
        let final = RockstarD3DLayoutRecord(
            engineStamp: stamp, sourceSHA256: sourceHash,
            system32D3D11: isStrippedCopy(d3d11, of: source) ? RockstarD3DLayoutRecord.sha256(of: d3d11) : nil,
            copies: wanted, createdFolders: created
        )
        return RockstarD3DSwapPlan(
            payload: payload, wanted: wanted, stale: recorded.filter { wanted[$0.key] == nil },
            folders: folders, interim: interim, final: final
        )
    }

    /// Creates the planned folders, places every wanted copy, and removes the
    /// stale ones. Returns the stale copies whose removal failed, which stay
    /// on record.
    @MainActor
    private static func placeRockstarCopies(
        _ swap: RockstarD3DSwap,
        plan: RockstarD3DSwapPlan
    ) throws -> [String: String] {
        for key in plan.folders {
            try swap.ops.createFolder(swap.driveC.appending(path: key))
        }
        let payloadFolder = swap.dxvkFolder.appending(path: "x64")
        for key in plan.wanted.keys.sorted() {
            let destination = swap.driveC.appending(path: key)
            try swap.ops.installCopy(destination, payloadFolder.appending(path: destination.lastPathComponent))
        }
        return removeRockstarCopies(plan.stale, swap: swap, payload: plan.payload)
    }

    /// Checks that `system32` holds Wine's own `d3d11` and `dxgi`, stripped.
    private static func verifySwap(system32: URL, source: URL, dxgiSource: URL?) throws {
        guard isStrippedCopy(system32.appending(path: "d3d11.dll"), of: source) else {
            throw RockstarD3DSwapError.notInPlace("d3d11.dll")
        }
        guard let dxgiSource, isStrippedCopy(system32.appending(path: "dxgi.dll"), of: dxgiSource) else {
            throw RockstarD3DSwapError.notInPlace("dxgi.dll")
        }
    }

    /// `keys` without duplicates (compared without case), deepest first, so
    /// a folder is removed before its parent.
    private static func deepestFirst(_ keys: [String]) -> [String] {
        var seen = Set<String>()
        return keys.filter { seen.insert($0.lowercased()).inserted }.sorted {
            let depths = ($0.split(separator: "/").count, $1.split(separator: "/").count)
            return depths.0 == depths.1 ? $0 < $1 : depths.0 > depths.1
        }
    }

    static func rockstarIsDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
}
