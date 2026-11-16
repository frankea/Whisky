//
//  RockstarD3DLayout.swift
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

/// Which Direct3D the Rockstar Games Launcher's `Launcher.exe` can be given.
///
/// The launcher draws its window with Direct2D on a D3D10.1 device, and no
/// backend Whisky ships can make one: D3DMetal has no D3D10 at all, DXVK
/// answers the device request with `DXGI_ERROR_UNSUPPORTED`, and DXMT 0.80
/// crashes. The launcher stops at "Initializing" on every one of them (#382).
/// Wine's own `d3d11`, `dxgi` and `d3d10core` (wined3d) make the device, but
/// only on wined3d's OpenGL renderer: on Vulkan, which it picks for D3D10 and
/// D3D11 here, the launcher dies at "Initializing group 1".
///
/// Wine's own DLLs are only reachable as builtins while the runtime still has
/// them. Deploying the GPTK payload puts Apple's forwarders into D3DMetal in
/// their place in `lib/wine`, so `d3d11=b` there reaches D3DMetal and fails
/// the same way. The layout is decided by what those two slots hold and, with
/// the payload deployed, by whether the bottle can take Wine's own `d3d11` in
/// its `system32` instead (``swapped(source:)``).
public enum RockstarD3DLayout: Equatable, Sendable {
    /// Wine's own builtins are in the runtime: `Launcher.exe` loads them, on
    /// the OpenGL renderer.
    case builtin
    /// The GPTK payload holds the runtime's slots, so `system32\d3d11.dll` is
    /// Wine's own `d3d11` instead: the builtin-marked file at `source`, copied
    /// with the marker stripped so the loader takes it as a native DLL.
    /// `Launcher.exe` asks for `d3d11` and `dxgi` native first and gets Wine's
    /// own, on the OpenGL renderer.
    ///
    /// Only `d3d11` moves. `system32\d3d10core.dll` stays DXVK's: GPTK never
    /// replaces `d3d10core`, so `d3d10core=b` reaches Wine's own in the
    /// runtime. `system32\dxgi.dll` stays what every DXVK launch already puts
    /// there while the payload is deployed, Wine's own `dxgi` with the marker
    /// stripped. Measured by hand with engine 4.8.3 and GPTK deployed, in a
    /// Steam bottle signed in to Steam:
    ///
    /// - Steam's Chromium GPU process loads the DXVK copy beside it in
    ///   `bin\cef\cef.win64` and renders: on start, after its helpers are
    ///   killed and respawn, and on a cold start. `steam.exe` and the helpers
    ///   that draw nothing load no `d3d11` at all.
    /// - A process with no `d3d11` override, which is what a game on D3DMetal
    ///   gets, still loads the GPTK forwarders: for a DLL in the system
    ///   directory, Wine's default load order is builtin first.
    /// - The launcher signs in and opens its main window with Steam running,
    ///   while `SocialClubHelper.exe` loads the DXVK copy in its own folder.
    ///
    /// Any process that asks for `d3d11` native first and finds no copy in its
    /// own folder gets Wine's `d3d11` too, so the swap is only made while
    /// Whisky can put a DXVK copy beside every such process it knows of.
    case swapped(source: URL)
    /// Wine's own Direct3D cannot be given, so `Launcher.exe` keeps the DXVK
    /// set it had before, with NVIDIA's bridges off. It still cannot draw, but
    /// nothing gets worse for it, and nothing Whisky wrote for the other
    /// layouts is left behind.
    case degraded(Reason)

    /// Why neither Wine's own builtins nor the swap can be used.
    public enum Reason: Equatable, Sendable {
        /// The GPTK payload is deployed, and the runtime's `d3d11.dll` or
        /// `dxgi.dll` is not the Wine original the store backed up: Apple's
        /// forwarder into D3DMetal, the shim Whisky puts in front of one, a
        /// payload copied in by hand, or anything else Whisky cannot vouch for.
        /// What a launch resolves to when it does not decide on the swap.
        case gptkForwarders
        /// The bottle's Wine Direct3D setting for the launcher is off.
        case disabledByUser
        /// Wine's own `d3d11` or `dxgi` for the installed engine cannot be
        /// found (``WineD3DSource``), described for the log.
        case sourceUnavailable(String)
        /// The bottle itself asks for `d3d11` native first (its backend, a
        /// launcher profile, or an override of the user's), so every program
        /// without an entry of its own would get Wine's `d3d11`.
        case bottleUsesNativeD3D11
        /// These installed library games run on DXVK, by name. Copies never go
        /// into a game's folder, so they would get Wine's `d3d11`.
        case dxvkPlanGames([String])
        /// These programs ask for `d3d11` native first where no copy can go:
        /// executable names, or folders relative to `drive_c`.
        case unservedConsumers([String])
        /// A step of the swap failed, described for the log. The bottle was
        /// put back on DXVK.
        case swapFailed(String)
    }

    /// Whether `Launcher.exe` draws on Wine's own Direct3D: from the runtime,
    /// or from the copy in `system32`.
    var usesWineDirect3D: Bool {
        switch self {
        case .builtin, .swapped:
            true
        case .degraded:
            false
        }
    }

    /// The layout for what the runtime's `d3d11.dll` and `dxgi.dll` slots hold.
    ///
    /// - Parameters:
    ///   - d3d11IsForwarder: Whether `lib/wine`'s `d3d11.dll` leads to D3DMetal.
    ///   - dxgiIsForwarder: Whether `lib/wine`'s `dxgi.dll` leads to D3DMetal.
    static func resolve(d3d11IsForwarder: Bool, dxgiIsForwarder: Bool) -> RockstarD3DLayout {
        d3d11IsForwarder || dxgiIsForwarder ? .degraded(.gptkForwarders) : .builtin
    }

    /// The layout for a launch.
    ///
    /// The forwarders are deployed with the rest of the payload, so a runtime
    /// whose builtin `d3d12` is not D3DMetal's has none, and its slots are not
    /// read at all.
    ///
    /// With the payload deployed the decision fails closed: a slot counts as
    /// Wine's own only when it is, byte for byte, the original the store
    /// backed up when it deployed (``wineOriginals(libraryFolder:store:)``).
    /// Matching the store's forwarder instead would fail open: a payload
    /// copied in by hand
    /// (``GPTKImporter/holdsHandPlacedPayload(inLibraryFolder:usingStore:)``),
    /// a store holding another version than the one deployed, or no store at
    /// all would each read as Wine's own, and `d3d11=b` with `renderer=gl`
    /// would send the launcher into D3DMetal all the same.
    ///
    /// - Parameters:
    ///   - payloadDeployed: Whether the GPTK payload is deployed
    ///     (``GPTKImporter/isDeployed()``, the launch's `builtinD3D12IsD3DMetal`).
    ///   - libraryFolder: The runtime's library folder.
    ///   - store: The GPTK store holding the Wine originals.
    static func resolve(
        payloadDeployed: Bool,
        libraryFolder: URL = WhiskyWineInstaller.libraryFolder,
        store: URL = GPTKImporter.storeFolder
    ) -> RockstarD3DLayout {
        guard payloadDeployed else { return .builtin }
        let originals = wineOriginals(libraryFolder: libraryFolder, store: store)
        return resolve(d3d11IsForwarder: !originals.d3d11, dxgiIsForwarder: !originals.dxgi)
    }

    /// Whether the runtime's `d3d11.dll` and `dxgi.dll` are the Wine originals
    /// in the store's `originals/` folder, byte for byte. A missing slot or a
    /// missing backup is not.
    static func wineOriginals(libraryFolder: URL, store: URL) -> (d3d11: Bool, dxgi: Bool) {
        let peDir = libraryFolder.appending(path: "Wine").appending(path: "lib")
            .appending(path: "wine").appending(path: "x86_64-windows")
        let originals = store.appending(path: "originals")
        func isOriginal(_ name: String) -> Bool {
            let backup = originals.appending(path: name).path(percentEncoded: false)
            return FileManager.default.fileExists(atPath: backup)
                && FileManager.default.contentsEqual(
                    atPath: peDir.appending(path: name).path(percentEncoded: false), andPath: backup
                )
        }
        return (isOriginal("d3d11.dll"), isOriginal("dxgi.dll"))
    }

    /// Whether the runtime's `d3d11.dll` and `dxgi.dll` are the store's
    /// forwarders, for the diagnostics report; the layout does not go by it.
    ///
    /// A slot is when it holds the store's forwarder byte for byte. `dxgi`
    /// also is when it holds the DXGI driver version shim, which deploy puts
    /// in front of Apple's forwarder. A missing slot is not.
    static func forwarders(libraryFolder: URL, store: URL) -> (d3d11: Bool, dxgi: Bool) {
        let peDir = libraryFolder.appending(path: "Wine").appending(path: "lib")
            .appending(path: "wine").appending(path: "x86_64-windows")
        let storeLib = store.appending(path: "lib")
        func isForwarder(_ name: String) -> Bool {
            let slot = peDir.appending(path: name)
            return FileManager.default.fileExists(atPath: slot.path(percentEncoded: false))
                && GPTKImporter.isGPTKForwarder(slot, matching: storeLib)
        }
        let dxgiShim = FileManager.default.fileExists(
            atPath: peDir.appending(path: "dxgi.dll").path(percentEncoded: false)
        ) && GPTKImporter.isInstalled(GPTKImporter.dxgiVersionInterposer, inLibraryFolder: libraryFolder)
        return (isForwarder("d3d11.dll"), isForwarder("dxgi.dll") || dxgiShim)
    }

    /// What a launch that decides on the swap knows about the bottle, read in
    /// the order ``resolve(_:)`` checks it.
    ///
    /// Gathering stops at the first check that fails
    /// (`Wine.rockstarLayoutInputs`), so a field after it keeps its default
    /// and was not read: on a runtime without the payload, nothing but the
    /// payload's two marker files is.
    struct Inputs: Equatable {
        /// ``resolve(payloadDeployed:libraryFolder:store:)`` for the launch.
        var payloadLayout: RockstarD3DLayout
        /// The bottle's Wine Direct3D setting for the launcher.
        var enabled: Bool = true
        /// Wine's own `d3d11`, the file the `system32` copy is made from.
        var d3d11Source: WineD3DSource = .unavailable(.missingFile)
        /// Wine's own `dxgi`, which `Launcher.exe`'s `dxgi=n,b` has to find in
        /// `system32`: a DXVK launch only puts it there while it resolves.
        var dxgiSource: WineD3DSource = .unavailable(.missingFile)
        /// Whether the bottle scope asks for `d3d11` native first.
        var bottleUsesNativeD3D11: Bool = false
        /// Installed library games whose plan is DXVK, by name.
        var dxvkPlanGames: [String] = []
        /// Processes that ask for `d3d11` native first where no copy can go.
        var unservedConsumers: [String] = []
    }

    /// The layout a launch that decides on the swap gives the bottle.
    ///
    /// The checks run in a fixed order and the first that fails decides, so
    /// the reason a bottle is degraded is always the earliest one: without
    /// the payload the layout is ``builtin`` and nothing else matters; then
    /// the user's setting; then whether Wine's own files can be found; then
    /// whether anything in the bottle would lose DXVK to the swap. Only a
    /// bottle that passes all of them is ``swapped(source:)``, from either
    /// place Wine's `d3d11` can be: a `lib/wine` slot that is still Wine's
    /// own in a part-deployed runtime, or the store's backup.
    ///
    /// - Parameter inputs: What the launch read about the bottle.
    static func resolve(_ inputs: Inputs) -> RockstarD3DLayout {
        if inputs.payloadLayout == .builtin {
            return .builtin
        }
        guard inputs.enabled else { return .degraded(.disabledByUser) }
        for source in [inputs.d3d11Source, inputs.dxgiSource] {
            if case let .unavailable(reason) = source {
                return .degraded(.sourceUnavailable(reason.description))
            }
        }
        guard !inputs.bottleUsesNativeD3D11 else { return .degraded(.bottleUsesNativeD3D11) }
        guard inputs.dxvkPlanGames.isEmpty else { return .degraded(.dxvkPlanGames(inputs.dxvkPlanGames.sorted())) }
        guard inputs.unservedConsumers.isEmpty else {
            return .degraded(.unservedConsumers(inputs.unservedConsumers.sorted()))
        }
        guard let source = inputs.d3d11Source.url else { return .degraded(.sourceUnavailable("no d3d11")) }
        return .swapped(source: source)
    }

    /// The layout in a log line or a diagnostics report.
    var summary: String {
        switch self {
        case .builtin:
            "builtin (Wine's own d3d11, dxgi and d3d10core on the OpenGL renderer)"
        case .swapped:
            "swapped (system32 d3d11 is Wine's own, marker stripped; "
                + "Steam's and Social Club's Chromium load DXVK copies beside them)"
        case let .degraded(reason):
            "degraded (\(reason.name): \(reason.explanation); Launcher.exe stays on DXVK)"
        }
    }
}

extension RockstarD3DLayout.Reason {
    /// The reason's name in a log line.
    var name: String {
        switch self {
        case .gptkForwarders: "gptkForwarders"
        case .disabledByUser: "disabledByUser"
        case .sourceUnavailable: "sourceUnavailable"
        case .bottleUsesNativeD3D11: "bottleUsesNativeD3D11"
        case .dxvkPlanGames: "dxvkPlanGames"
        case .unservedConsumers: "unservedConsumers"
        case .swapFailed: "swapFailed"
        }
    }

    /// What the reason means, in a log line.
    var explanation: String {
        switch self {
        case .gptkForwarders:
            "the runtime's d3d11 or dxgi is not Wine's own"
        case .disabledByUser:
            "Wine Direct3D for the launcher is off in this bottle"
        case let .sourceUnavailable(why):
            "no Wine d3d11 or dxgi for this engine: \(why)"
        case .bottleUsesNativeD3D11:
            "the bottle asks for d3d11 native first"
        case let .dxvkPlanGames(names):
            "these games run on DXVK: \(names.joined(separator: ", "))"
        case let .unservedConsumers(names):
            "these programs need DXVK from system32: \(names.joined(separator: ", "))"
        case let .swapFailed(why):
            "the swap failed and DXVK was put back: \(why)"
        }
    }
}
