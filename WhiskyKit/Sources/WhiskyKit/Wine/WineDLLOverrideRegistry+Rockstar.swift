//
//  WineDLLOverrideRegistry+Rockstar.swift
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
    private static let rockstarLogger = Logger(
        subsystem: "com.isaacmarovitz.WhiskyKit", category: "dll-overrides"
    )

    /// The launcher executables a launch should write entries for ahead of
    /// time, because something other than Whisky starts them.
    ///
    /// Rockstar's chain, when the game being launched is a Rockstar title,
    /// whether or not Rockstar's launcher is installed yet: the first run of
    /// one installs the launcher and starts it in the same session. Otherwise
    /// it rides along with Steam and Rockstar launches only once the launcher
    /// is installed in the bottle.
    ///
    /// `AppDefaults` is keyed on the file name alone, so the entry is the same
    /// for any `Launcher.exe` in the bottle. Once Rockstar's launcher is there,
    /// another program by that name gets the Rockstar layout until its own
    /// launch from Whisky writes its own entry (and loses it again at the next
    /// Steam launch). A game's own `Launcher.exe` keeps the game's plan during
    /// that game's Steam launch, since game executables are written first.
    static func chainExecutables(
        for launcher: LauncherType?, descendantLaunchers: [LauncherType] = [], bottleURL: URL
    ) -> [String] {
        let rockstarSession = descendantLaunchers.contains(.rockstar)
            || ((launcher == .steam || launcher == .rockstar) && rockstarInstalled(bottleURL: bottleURL))
        return rockstarSession ? LauncherType.rockstar.chainExecutables : []
    }

    /// Whether the bottle has a `Rockstar Games` folder in either Program Files.
    static func rockstarInstalled(bottleURL: URL) -> Bool {
        let driveC = bottleURL.appending(path: "drive_c")
        return ["Program Files", "Program Files (x86)"].contains { programFiles in
            let folder = driveC.appending(path: programFiles).appending(path: "Rockstar Games")
            return FileManager.default.fileExists(atPath: folder.path(percentEncoded: false))
        }
    }

    /// Whether `url` is the Rockstar Games Launcher's own `Launcher.exe`, as
    /// opposed to another program by that name, which keeps the entry a
    /// launch of it writes for itself.
    static func isRockstarLauncher(_ url: URL) -> Bool {
        url.lastPathComponent.lowercased() == "launcher.exe"
            && url.path(percentEncoded: false).lowercased().contains("rockstar games/launcher")
            && LauncherType.detect(from: url) == .rockstar
    }

    /// Writes Rockstar's chain (``LauncherType/chainRoles``) each the entry
    /// its role needs, unless every one of them already has an entry.
    ///
    /// `Launcher.exe` gets its `Direct3D` key alongside, and only while its
    /// entry is the one written here: a game's own `Launcher.exe`, whose plan
    /// a Steam launch writes first, keeps the game's renderer as well. On the
    /// builtin layout that key asks for wined3d's OpenGL renderer, without
    /// which the launcher dies at "Initializing group 1"; on any other it asks
    /// for nothing, which takes back a renderer Whisky wrote earlier.
    ///
    /// - Parameters:
    ///   - scopes: The launch's scopes, where the first set for an executable wins.
    ///   - layout: What `Launcher.exe` can be given.
    ///   - launcherSet: Composes the launcher set from the user's own overrides
    ///     for the executable:
    ///     ``launcherDLLOverrides(bottle:userOverrides:recommendedBackend:builtinD3D12IsD3DMetal:)``.
    @MainActor
    static func addRockstarChainScopes(
        to scopes: inout DLLOverrideScopes,
        layout: @autoclosure () -> RockstarD3DLayout,
        launcherSet: (ProgramOverrides?) -> String
    ) {
        let chain = LauncherType.rockstar.chainRoles
        guard chain.contains(where: { !scopes.contains($0.executable) }) else { return }
        let layout = layout()
        let base = launcherSet(nil)
        for (executable, role) in chain {
            let ownsEntry = !scopes.contains(executable)
            scopes.add([executable], rockstarChainOverrides(role: role, layout: layout, launcherSet: base))
            guard role == .wineDirect3D else { continue }
            guard ownsEntry else {
                rockstarLogger.info("\(executable, privacy: .public) keeps this launch's own plan")
                continue
            }
            scopes.add(.direct3D(executable), layout == .builtin ? "renderer=gl" : "")
            rockstarLogger.info("\(executable, privacy: .public): Rockstar layout \(layout.summary, privacy: .public)")
        }
    }

    /// The DLL overrides one of Rockstar's chain runs with.
    ///
    /// `Launcher.exe` on the builtin layout gets the launcher set with Wine's
    /// own `d3d10core`, `d3d11` and `dxgi` pinned to builtin. Builtin, not
    /// `n,b`: DXVK's files stay in `system32` for everything else, and Wine
    /// loads its builtin even when a launch names the file there by full path.
    /// `d3d12` stays off (#276), and NVIDIA's bridges too: `nvapi64` took the
    /// launcher down with an access violation right after sign-in.
    ///
    /// Anything else gets the launcher set, the DXVK preset, with `d3d12` and
    /// the NVIDIA bridges off: `SocialClubHelper.exe`, which is Chromium and
    /// probes for an NVIDIA GPU the way Steam's helper does, and `Launcher.exe`
    /// on a degraded layout, where Wine's own DLLs cannot be reached.
    ///
    /// - Parameters:
    ///   - role: What the executable draws with.
    ///   - layout: What `Launcher.exe` can be given.
    ///   - launcherSet: The launcher set, in `WINEDLLOVERRIDES` syntax.
    static func rockstarChainOverrides(
        role: LauncherChainRole, layout: RockstarD3DLayout, launcherSet: String
    ) -> String {
        guard role == .wineDirect3D, layout == .builtin else {
            return disablingNVAPI(in: disablingD3D12(in: launcherSet))
        }
        var parsed = parseDLLOverrides(launcherSet)
        for dll in ["d3d10core", "d3d11", "dxgi"] {
            parsed[dll] = "b"
        }
        for dll in ["d3d12", "nvapi", "nvapi64", "nvngx"] {
            parsed[dll] = ""
        }
        return parsed.keys.sorted().map { "\($0)=\(parsed[$0] ?? "")" }.joined(separator: ";")
    }
}
