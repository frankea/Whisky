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
/// the same way. The layout is decided by what those two slots hold.
public enum RockstarD3DLayout: Equatable, Sendable {
    /// Wine's own builtins are in the runtime: `Launcher.exe` loads them, on
    /// the OpenGL renderer.
    case builtin
    /// Wine's own builtins cannot be reached, so `Launcher.exe` keeps the DXVK
    /// set it had before, with NVIDIA's bridges off. It still cannot draw, but
    /// nothing gets worse for it, and nothing Whisky wrote for the builtin
    /// layout is left behind.
    ///
    /// Putting Wine's own DLLs into the prefix for `Launcher.exe` would fix
    /// this case too; that will be a layout of its own, not a change to this one.
    case degraded(Reason)

    /// Why the builtin layout cannot be used.
    public enum Reason: String, Equatable, Sendable {
        /// The runtime's `d3d11.dll` or `dxgi.dll` is Apple's forwarder into
        /// D3DMetal, or the shim Whisky puts in front of one.
        case gptkForwarders
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
    /// - Parameters:
    ///   - payloadDeployed: Whether the GPTK payload is deployed
    ///     (``GPTKImporter/isDeployed()``, the launch's `builtinD3D12IsD3DMetal`).
    ///   - libraryFolder: The runtime's library folder.
    ///   - store: The GPTK store the forwarders are compared against.
    static func resolve(
        payloadDeployed: Bool,
        libraryFolder: URL = WhiskyWineInstaller.libraryFolder,
        store: URL = GPTKImporter.storeFolder
    ) -> RockstarD3DLayout {
        guard payloadDeployed else { return .builtin }
        let slots = forwarders(libraryFolder: libraryFolder, store: store)
        return resolve(d3d11IsForwarder: slots.d3d11, dxgiIsForwarder: slots.dxgi)
    }

    /// Whether the runtime's `d3d11.dll` and `dxgi.dll` lead to D3DMetal.
    ///
    /// A slot does when it holds the store's forwarder byte for byte. `dxgi`
    /// also does when it holds the DXGI driver version shim, which deploy puts
    /// in front of Apple's forwarder. A missing slot leads nowhere.
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

    /// The layout in a log line or a diagnostics report.
    var summary: String {
        switch self {
        case .builtin:
            "builtin (Wine's own d3d11, dxgi and d3d10core on the OpenGL renderer)"
        case let .degraded(reason):
            "degraded (\(reason.rawValue): the runtime's d3d11 or dxgi is D3DMetal's; Launcher.exe stays on DXVK)"
        }
    }
}
