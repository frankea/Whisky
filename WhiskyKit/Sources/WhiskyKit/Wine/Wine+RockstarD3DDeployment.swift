//
//  Wine+RockstarD3DDeployment.swift
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

extension Wine {
    /// Deploys DXVK for a launch, and with it the Rockstar Games Launcher's
    /// Direct3D in `system32` when the launch decides on it (#382).
    ///
    /// With the GPTK payload deployed, Wine's own `d3d11` is not in the
    /// runtime, so the launcher can only draw if `system32\d3d11.dll` is
    /// Wine's own (``RockstarD3DLayout/swapped(source:)``). That is a property
    /// of the bottle, not of one launch, so it is decided by the launches
    /// that start what the bottle's DXVK consumers run under:
    ///
    /// - A launch of Steam, of Rockstar's `Launcher.exe`, or of a front end
    ///   whose folder holds Whisky's copies keeps the layout: it resolves it
    ///   for the bottle and swaps, keeps or tears it down to match.
    /// - Any other launch that deploys DXVK suspends it: DXVK takes
    ///   `system32\d3d11.dll` back for that session, since whatever it starts
    ///   may need it there, and the next launch that keeps the layout swaps
    ///   it again. The copies and the record stay, and so do `Launcher.exe`'s
    ///   swapped entry and renderer when the launch writes no Rockstar chain:
    ///   a Rockstar start inside that session gets DXVK's `d3d11` with Wine's
    ///   `dxgi`, the pair every DXVK process has, and cannot draw, as on any
    ///   layout where Wine's own `d3d11` is out of reach. The settings keep
    ///   showing the swap as active, which it is again from the next start
    ///   of Steam or the launcher from Whisky.
    /// - In a bottle without Rockstar, and with no record of an earlier swap,
    ///   DXVK is deployed exactly as it always was.
    ///
    /// The record is read and written under the bottle folder's lock, the one
    /// the DXMT game folder record takes, so the app and `whisky` cannot
    /// interleave. It is released before the DXMT reconcile that follows in
    /// `deployLauncherAndGameLayers` takes it again: each call opens its own
    /// descriptor, and a second `flock` on the same folder blocks even within
    /// one process, so nesting the two would deadlock.
    ///
    /// - Parameters:
    ///   - bottle: The bottle the launch runs in.
    ///   - dxvkFolder: The DXVK payload.
    ///   - rockstar: The launch.
    ///   - ops: The file operations; tests record them.
    /// - Returns: The layout the launch decided, for the DLL override step,
    ///   or `nil` when it decided none and that step resolves it.
    /// - Throws: An error if DXVK cannot be deployed. A swap that fails puts
    ///   DXVK back instead of throwing.
    @MainActor
    static func deployDXVK(
        bottle: Bottle, from dxvkFolder: URL, rockstar: RockstarD3DLaunch, ops: RockstarD3DFileOps = .live
    ) throws -> RockstarD3DLayout? {
        let swap = RockstarD3DSwap(bottle: bottle, dxvkFolder: dxvkFolder, launch: rockstar, ops: ops)
        let outcome = DXMTGameFolderRecord.withLock(in: bottle.url) {
            Result { try reconcileRockstarD3D(swap) }
        }
        return try outcome.get()
    }

    @MainActor
    private static func reconcileRockstarD3D(_ swap: RockstarD3DSwap) throws -> RockstarD3DLayout? {
        let bottle = swap.bottle
        let recordExists = RockstarD3DLayoutRecord.exists(in: bottle.url)
        let record = RockstarD3DLayoutRecord.load(from: bottle.url)
        let executable = swap.launch.url.lastPathComponent
        guard swap.launch.keepsLayout(record: record, bottleURL: bottle.url) else {
            try swap.deployPlainDXVK()
            if recordExists {
                Logger.wineKit.info("Rockstar layout suspended: DXVK's d3d11 for \(executable, privacy: .public)")
            }
            return nil
        }
        guard swap.launch.engages(bottle) else {
            bottle.rockstarD3DLayout = nil
            if recordExists {
                try tearDown(swap, record: record)
            } else {
                try swap.deployPlainDXVK()
            }
            return nil
        }
        let (inputs, scan) = rockstarLayoutInputs(
            bottle: bottle, launch: swap.launch, dxvkFolder: swap.dxvkFolder, record: record
        )
        var layout = RockstarD3DLayout.resolve(inputs)
        if case let .swapped(source) = layout {
            layout = try applySwap(
                swap, source: source, dxgiSource: inputs.dxgiSource.url, scan: scan,
                onDisk: (record, recordExists)
            )
        } else {
            layout = try leaveSwap(swap, layout: layout, onDisk: (record, recordExists))
        }
        bottle.rockstarD3DLayout = layout
        Logger.wineKit.info("Rockstar layout: \(layout.summary, privacy: .public)")
        return layout
    }

    /// What a launch that decides on the swap reads about the bottle, in the
    /// order ``RockstarD3DLayout/resolve(_:)`` checks it, stopping at the
    /// first check that fails: on a runtime without the GPTK payload only the
    /// payload's two marker files are read, and the library scan, the costly
    /// part, only runs once everything before it passed.
    ///
    /// - Parameters:
    ///   - bottle: The bottle.
    ///   - launch: The launch, for the runtime and the backends.
    ///   - dxvkFolder: The DXVK payload.
    ///   - record: The bottle's swap record.
    /// - Returns: The inputs, and the consumer scan when it ran.
    @MainActor
    static func rockstarLayoutInputs(
        bottle: Bottle, launch: RockstarD3DLaunch, dxvkFolder: URL, record: RockstarD3DLayoutRecord?
    ) -> (RockstarD3DLayout.Inputs, RockstarD3DConsumerScan) {
        let runtime = launch.runtime
        var inputs = RockstarD3DLayout.Inputs(payloadLayout: RockstarD3DLayout.resolve(
            payloadDeployed: launch.payloadDeployed, libraryFolder: runtime.libraryFolder, store: runtime.store
        ))
        guard inputs.payloadLayout != .builtin else { return (inputs, RockstarD3DConsumerScan()) }
        inputs.enabled = bottle.settings.rockstarWineD3D
        guard inputs.enabled else { return (inputs, RockstarD3DConsumerScan()) }
        inputs.d3d11Source = WineD3DSource.resolve(
            "d3d11.dll",
            libraryFolder: runtime.libraryFolder,
            store: runtime.store
        )
        guard inputs.d3d11Source.url != nil else { return (inputs, RockstarD3DConsumerScan()) }
        inputs.dxgiSource = WineD3DSource.resolve(
            "dxgi.dll",
            libraryFolder: runtime.libraryFolder,
            store: runtime.store
        )
        guard inputs.dxgiSource.url != nil else { return (inputs, RockstarD3DConsumerScan()) }
        inputs.bottleUsesNativeD3D11 = rockstarBottleUsesNativeD3D11(
            bottle: bottle, recommendedBackend: launch.recommendedBackend,
            builtinD3D12IsD3DMetal: launch.payloadDeployed
        )
        guard !inputs.bottleUsesNativeD3D11 else { return (inputs, RockstarD3DConsumerScan()) }
        let scan = rockstarD3DConsumers(
            bottle: bottle, recommendedBackend: launch.recommendedBackend, dxvkFolder: dxvkFolder, record: record
        )
        inputs.dxvkPlanGames = scan.dxvkPlanGames
        inputs.unservedConsumers = scan.unserved
        return (inputs, scan)
    }

    /// Deploys DXVK for a launch that decided against the swap: a teardown
    /// when an earlier swap is on record, DXVK as it always was otherwise.
    @MainActor
    private static func leaveSwap(
        _ swap: RockstarD3DSwap, layout: RockstarD3DLayout,
        onDisk: (record: RockstarD3DLayoutRecord?, exists: Bool)
    ) throws -> RockstarD3DLayout {
        if onDisk.exists {
            try tearDown(swap, record: onDisk.record)
        } else {
            try swap.deployPlainDXVK()
        }
        return layout
    }

    /// Takes the swap back: DXVK into `system32` whatever its `d3d11.dll`
    /// slot holds, then the recorded copies that are still Whisky's, then the
    /// folders Whisky created while they are empty, then the record.
    ///
    /// The DXVK deploy is the one every DXVK launch did before the swap
    /// existed, and it replaces `system32\d3d11.dll` atomically, so the bottle
    /// is never without one. A copy is removed only under the exact name
    /// Whisky wrote, when it is not a symbolic link, and while it hashes to
    /// what the record says or to the current payload: anything else is no
    /// longer Whisky's and stays, and its entry goes. A removal that fails
    /// keeps its entry and the record, so the next launch tries again.
    ///
    /// - Throws: An error if DXVK cannot be deployed, which fails the launch
    ///   as a DXVK deploy failure always has.
    @MainActor
    static func tearDown(_ swap: RockstarD3DSwap, record: RockstarD3DLayoutRecord?) throws {
        try swap.ops.enableDXVK(swap.bottle, swap.dxvkFolder, nil, swap.reconcileDXGI)
        var remaining = record ?? RockstarD3DLayoutRecord(engineStamp: "", sourceSHA256: "")
        remaining.copies = removeRockstarCopies(
            remaining.copies,
            swap: swap,
            payload: rockstarPayloadHashes(swap.dxvkFolder)
        )
        for key in remaining.createdFolders {
            swap.ops.removeFolderIfEmpty(swap.driveC.appending(path: key))
        }
        do {
            if remaining.copies.isEmpty {
                try swap.ops.removeRecord(swap.bottle.url)
            } else {
                try swap.ops.saveRecord(remaining, swap.bottle.url)
            }
        } catch {
            Logger.wineKit.warning(
                "Could not update the Rockstar layout record: \(error.localizedDescription, privacy: .public)"
            )
        }
        Logger.wineKit.info("Rockstar layout torn down: system32 d3d11 is DXVK's again")
    }

    /// Removes each of `copies` that is still Whisky's, and returns the ones
    /// whose removal failed. A copy that is gone, or no longer Whisky's, is
    /// dropped and left where it is.
    @MainActor
    static func removeRockstarCopies(
        _ copies: [String: String], swap: RockstarD3DSwap, payload: [String: String]
    ) -> [String: String] {
        var failed: [String: String] = [:]
        for (key, recorded) in copies.sorted(by: { $0.key < $1.key }) {
            let url = swap.driveC.appending(path: key)
            let dll = url.lastPathComponent
            let entries = (try? FileManager.default.contentsOfDirectory(
                atPath: url.deletingLastPathComponent().path(percentEncoded: false)
            )) ?? []
            // Only the exact spelling Whisky writes: on a case-insensitive volume
            // `D3D11.dll` answers to `d3d11.dll` too, and is still the program's.
            guard entries.contains(dll), !rockstarIsSymbolicLink(url),
                  let hash = RockstarD3DLayoutRecord.sha256(of: url), hash == recorded || hash == payload[dll]
            else { continue }
            do {
                try swap.ops.removeCopy(url)
            } catch {
                Logger.wineKit.warning(
                    "Could not remove a Rockstar layout copy: \(error.localizedDescription, privacy: .public)"
                )
                failed[key] = recorded
            }
        }
        return failed
    }
}

/// Where the swap reads Wine's DLLs from; tests point it at fixtures.
struct RockstarD3DRuntime: Equatable, Sendable {
    /// The runtime's `Libraries` folder.
    var libraryFolder: URL
    /// The GPTK store, whose `originals/` holds Wine's `d3d11` and `dxgi`
    /// while the payload is deployed.
    var store: URL

    /// The installed runtime and store.
    static var installed: RockstarD3DRuntime {
        RockstarD3DRuntime(libraryFolder: WhiskyWineInstaller.libraryFolder, store: GPTKImporter.storeFolder)
    }
}

/// What the swap needs to know about a launch that deploys DXVK.
struct RockstarD3DLaunch {
    /// The executable being launched.
    let url: URL
    /// The launcher it is (`LauncherType.detect(from:)`), if any.
    let launcher: LauncherType?
    /// The launchers the launch's game starts by itself.
    let descendantLaunchers: [LauncherType]
    /// What `.recommended` resolves to for the bottle's games.
    let recommendedBackend: GraphicsBackend
    /// Whether the GPTK payload is deployed (the launch's `builtinD3D12IsD3DMetal`).
    let payloadDeployed: Bool
    /// Where Wine's DLLs are read from.
    var runtime: RockstarD3DRuntime = .installed

    /// Whether the bottle is Rockstar's: the launcher is installed, or this
    /// launch starts a Rockstar title, whose first run installs it and starts
    /// it in the same session. A property of the bottle, so a front end
    /// started from the Programs tab does not undo the swap.
    @MainActor
    func engages(_ bottle: Bottle) -> Bool {
        Wine.rockstarInstalled(bottleURL: bottle.url) || descendantLaunchers.contains(.rockstar)
    }

    /// Whether every DXVK consumer this launch starts is served while
    /// `system32\d3d11.dll` is Wine's: Steam's own executables, of which
    /// `steam.exe` loads no `d3d11` and the Chromium gets copies, with or
    /// without `-applaunch`; Rockstar's launcher folder, `Launcher.exe` and
    /// `LauncherPatcher.exe` (the updater, which starts `Launcher.exe` when it
    /// is done); and a front end in a folder holding Whisky's copies, started
    /// from the Programs tab.
    ///
    /// Steam is recognised by its folder, not by ``LauncherType/detect(from:)``,
    /// which takes any program with "steam" in its name or path for Steam's:
    /// such a program gets DXVK's set, and with Wine's `d3d11` in `system32`
    /// and no copy beside it, it would not get DXVK.
    ///
    /// The updater keeps the layout because what it starts is the launcher
    /// the swap is for: suspended, `Launcher.exe` would start on DXVK in
    /// `system32` with the degraded set, which is #382 again, and so would
    /// every later Rockstar start in that Steam session. The updater itself
    /// runs on its launch's set, which with the swap reaches Wine's `d3d11`;
    /// no copy can go beside it, since `Launcher.exe` shares its folder.
    ///
    /// Anything else that deploys DXVK (another launcher, a program on a DXVK
    /// override, a Rockstar game started directly) needs DXVK in `system32`.
    /// A Rockstar-store game started directly is one of them: it needs DXVK
    /// there itself, and the launcher it starts cannot draw that session.
    func keepsLayout(record: RockstarD3DLayoutRecord?, bottleURL: URL) -> Bool {
        let folder = url.deletingLastPathComponent()
        let folderKey = Wine.dxmtGameFolderKey(folder, bottleURL: bottleURL)?.lowercased()
        if launcher == .steam, let folderKey, let steamRoot = SteamLibrary.detectInstall(bottleURL: bottleURL),
           Wine.dxmtGameFolderKey(steamRoot, bottleURL: bottleURL)?.lowercased() == folderKey {
            return true
        }
        if Wine.isRockstarLauncher(url)
            || (launcher == .rockstar && Wine.isUnderRockstarLauncher(folder.path(percentEncoded: false))) {
            return true
        }
        guard let record, let folderKey else { return false }
        return record.copyFolderKeys.contains(folderKey)
    }
}
