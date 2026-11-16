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
    /// that game's Steam launch, since game executables are written first. The
    /// renderer flips with the entry: a launch that writes `Launcher.exe` some
    /// other set takes back the one Whisky wrote (``releaseRockstarRenderer(in:bottleURL:)``).
    static func chainExecutables(
        for launcher: LauncherType?, descendantLaunchers: [LauncherType] = [], bottleURL: URL
    ) -> [String] {
        let rockstarSession = descendantLaunchers.contains(.rockstar)
            || ((launcher == .steam || launcher == .rockstar) && rockstarInstalled(bottleURL: bottleURL))
        return rockstarSession ? LauncherType.rockstar.chainExecutables : []
    }

    /// Whether the bottle has a `Rockstar Games` folder in either Program
    /// Files with something of Rockstar's in it.
    ///
    /// The Rockstar swap (#382) creates `Rockstar Games\Social Club` itself,
    /// with DXVK's `d3d11.dll` and `d3d10core.dll` in it, ahead of the
    /// launcher's first start. A folder holding nothing but that, or nothing
    /// at all, is not Rockstar's: counted as an install, one first run that
    /// never got as far as installing the launcher would keep every later
    /// Steam start swapped and writing Rockstar's chain, and the teardown
    /// once Rockstar's uninstaller has removed its own files could never
    /// come, since Whisky's copies would be what kept the folder there.
    static func rockstarInstalled(bottleURL: URL) -> Bool {
        let driveC = bottleURL.appending(path: "drive_c")
        return ["Program Files", "Program Files (x86)"].contains { programFiles in
            let folder = driveC.appending(path: programFiles).appending(path: "Rockstar Games")
            return FileManager.default.fileExists(atPath: folder.path(percentEncoded: false))
                && !holdsNothingOfRockstars(folder)
        }
    }

    /// Whether `rockstarGames` holds nothing but Finder's `.DS_Store` and a
    /// `Social Club` folder holding nothing but that and the swap's copies.
    private static func holdsNothingOfRockstars(_ rockstarGames: URL) -> Bool {
        func entries(_ url: URL) -> [String]? {
            (try? FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false)))?
                .filter { $0 != ".DS_Store" }
        }
        guard let names = entries(rockstarGames) else { return false }
        return names.allSatisfy { name in
            name.lowercased() == "social club"
                && entries(rockstarGames.appending(path: name))?.allSatisfy(rockstarD3DCopyDLLs.contains) == true
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

    /// Rockstar's chain for a launch of Rockstar's own `Launcher.exe` from the
    /// Programs tab, written ahead of the launch's generic set so that set
    /// does not displace it. Any other executable gets nothing here.
    @MainActor
    static func addRockstarDirectLaunchScopes(
        _ url: URL, to scopes: inout DLLOverrideScopes,
        layout: () -> RockstarD3DLayout, launcherSet: (ProgramOverrides?) -> String
    ) {
        guard isRockstarLauncher(url) else { return }
        addRockstarChainScopes(to: &scopes, layout: layout, launcherSet: launcherSet)
        dllOverrideLogger.info("Rockstar's Launcher.exe gets the chain's set, not this launch's own")
    }

    /// Writes Rockstar's chain (``LauncherType/chainRoles``) each the entry
    /// its role needs, unless every one of them already has an entry.
    ///
    /// `Launcher.exe` gets its `Direct3D` key alongside, and only while its
    /// entry is the one written here: a game's own `Launcher.exe`, whose plan
    /// a Steam launch writes first, keeps the game's renderer as well. On the
    /// builtin and swapped layouts, where `Launcher.exe` draws on wined3d,
    /// that key asks for wined3d's OpenGL renderer, without which the launcher
    /// dies at "Initializing group 1"; on a degraded one it asks for nothing,
    /// which takes back a renderer Whisky wrote earlier.
    ///
    /// Every role starts from the launcher set without the user's own
    /// overrides, a launch of Rockstar's launcher from the Programs tab
    /// included: its per-program DLL overrides and a `WINEDLLOVERRIDES` in its
    /// environment are not written for it. The Direct3D DLLs, `d3d12` and the
    /// NVIDIA bridges are what decide whether it draws at all.
    ///
    /// - Parameters:
    ///   - scopes: The launch's scopes, where the first set for an executable wins.
    ///   - layout: Resolves what `Launcher.exe` can be given; only called when
    ///     an entry is written, since it may read the runtime.
    ///   - launcherSet: Composes the launcher set from the user's own overrides
    ///     for the executable:
    ///     ``launcherDLLOverrides(bottle:userOverrides:recommendedBackend:builtinD3D12IsD3DMetal:)``.
    @MainActor
    static func addRockstarChainScopes(
        to scopes: inout DLLOverrideScopes,
        layout: () -> RockstarD3DLayout,
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
                dllOverrideLogger.info("\(executable, privacy: .public) keeps this launch's own plan")
                continue
            }
            scopes.add(settings: .direct3D(executable), layout.usesWineDirect3D ? "renderer=gl" : "")
            dllOverrideLogger.info(
                "\(executable, privacy: .public): Rockstar layout \(layout.summary, privacy: .public)"
            )
        }
    }

    /// Asks for no renderer in `Launcher.exe`'s `Direct3D` key when this
    /// launch writes `Launcher.exe` a set of its own but not that key.
    ///
    /// The key is keyed on the file name alone, like the entry beside it. A
    /// launch that gives the entry to another program by that name (a game's
    /// own `Launcher.exe` in its Steam launch, or another `launcher.exe` from
    /// the Programs tab) would otherwise leave the `renderer=gl` Rockstar's
    /// chain wrote, and that program would be on wined3d's OpenGL renderer
    /// whenever it uses wined3d. The ownership rules take back only a renderer
    /// Whisky recorded writing and the registry still holds; one the user set
    /// stays (``ownedValueEdit(key:name:wanted:recorded:current:)``).
    ///
    /// Only while the record holds a renderer, so a bottle Whisky never wrote
    /// one into gets no `Direct3D` scope at all.
    static func releaseRockstarRenderer(in scopes: inout DLLOverrideScopes, bottleURL: URL) {
        let executable = "Launcher.exe"
        let direct3D = DLLOverrideScope.direct3D(executable)
        guard scopes.contains(executable),
              !scopes.entries.contains(where: { $0.scope == direct3D }),
              DLLOverrideRecord.load(from: bottleURL).ownedValue("renderer", in: direct3D.registryKey) != nil
        else { return }
        scopes.add(settings: direct3D, "")
        dllOverrideLogger.info("Launcher.exe is not Rockstar's in this launch: taking back its renderer")
    }

    /// The DLL overrides one of Rockstar's chain runs with.
    ///
    /// `Launcher.exe` on the builtin layout gets the launcher set with Wine's
    /// own `d3d10core`, `d3d11` and `dxgi` pinned to builtin. Builtin, not
    /// `n,b`: DXVK's files stay in `system32` for everything else, and Wine
    /// loads its builtin even when a launch names the file there by full path.
    ///
    /// On the swapped layout the runtime's `d3d11` and `dxgi` are GPTK's
    /// forwarders, and Wine's own sit in `system32` as native copies with the
    /// marker stripped, so `Launcher.exe` asks for those two native first,
    /// `n,b`. `d3d10core` stays builtin: `system32` keeps DXVK's, and the
    /// runtime's is Wine's own, since GPTK never replaces it.
    ///
    /// On both, `d3d12` stays off (#276), and NVIDIA's bridges too: `nvapi64`
    /// took the launcher down with an access violation right after sign-in.
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
        guard role == .wineDirect3D, layout.usesWineDirect3D else {
            return disablingNVAPI(in: disablingD3D12(in: launcherSet))
        }
        var parsed = parseDLLOverrides(launcherSet)
        let fromSystem32 = layout != .builtin
        parsed["d3d10core"] = "b"
        for dll in ["d3d11", "dxgi"] {
            parsed[dll] = fromSystem32 ? "n,b" : "b"
        }
        for dll in ["d3d12", "nvapi", "nvapi64", "nvngx"] {
            parsed[dll] = ""
        }
        return parsed.keys.sorted().map { "\($0)=\(parsed[$0] ?? "")" }.joined(separator: ";")
    }
}
