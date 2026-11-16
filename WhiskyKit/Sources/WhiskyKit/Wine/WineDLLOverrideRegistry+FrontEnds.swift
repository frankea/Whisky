//
//  WineDLLOverrideRegistry+FrontEnds.swift
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

extension Wine {
    /// The helpers that must share `url`'s DLL overrides: a launcher's, or a
    /// Chromium front end's from the table.
    ///
    /// Detected from the executable, not the bottle's recorded launcher: they
    /// need the entry because of how wine resolves `AppDefaults`, not because
    /// the user enabled launcher fixes.
    static func helperExecutables(for url: URL) -> [String] {
        DXVKSteering.detect(executable: url)?.helperExecutables ?? []
    }

    /// Gives each ``ChromiumFrontEnd`` among `executables`, and each Electron
    /// or NW.js app (``ChromiumRuntimeDetector``), the launcher set, in its own
    /// `AppDefaults` entry, when Recommended should steer it.
    ///
    /// Only where the front end's own choice, its override or else the
    /// bottle's backend, is Recommended or DXVK, and the bottle's games run on
    /// something other than DXVK: there the window stays black without it. That
    /// is the choice a launch of it from the Programs tab steers on, so a
    /// program-level Recommended in a bottle set to D3DMetal gets DXVK whichever
    /// way the front end starts. A front end whose choice is another backend
    /// keeps it: `ownSettingsDLLOverrides` writes that on a Steam launch, and a
    /// launch of it from the Programs tab writes it as the launched executable.
    /// Executables that are not front ends are left to the caller.
    ///
    /// - Parameters:
    ///   - executables: Candidates, read only when the games are not on DXVK,
    ///     since the ahead-of-time ones cost a `fileExists` each.
    ///   - scopes: The launch's scopes, where the first set for an executable wins.
    ///   - bottle: The bottle being launched in.
    ///   - recommendedBackend: What `.recommended` resolves to for the bottle's
    ///     games; `nil` asks ``GraphicsBackendResolver``.
    ///   - launcherSet: Composes the launcher set from the user's own overrides
    ///     for the executable:
    ///     ``launcherDLLOverrides(bottle:userOverrides:recommendedBackend:builtinD3D12IsD3DMetal:)``.
    @MainActor
    static func addFrontEndScopes(
        _ executables: @autoclosure () -> [URL],
        to scopes: inout DLLOverrideScopes,
        bottle: Bottle,
        recommendedBackend: GraphicsBackend?,
        launcherSet: (ProgramOverrides?) -> String
    ) {
        let gamesBackend = bottle.settings.graphicsBackend == .recommended
            ? recommendedBackend ?? GraphicsBackendResolver.resolve()
            : bottle.settings.graphicsBackend
        guard gamesBackend != .dxvk else { return }
        for url in executables() {
            guard let steering = frontEndSteering(for: url) else { continue }
            let persisted = Program.persistedOverrides(for: url, bottleURL: bottle.url)
            guard frontEndWantsDXVK(choice: persisted?.graphicsBackend ?? bottle.settings.graphicsBackend)
            else { continue }
            let own = launcherSet(persisted)
            scopes.add(steering.helperExecutables, disablingNVAPI(in: own))
            // nvapi stays reachable on the front end's own entry, the layout
            // measured working with a manual DXVK override on 3DMark.exe.
            scopes.add([url.lastPathComponent], own)
        }
    }

    /// Why `url` is steered as a front end: a row of the table, or an Electron
    /// or NW.js app found by its files. A launcher is not one; its entry is
    /// written as a launcher's.
    static func frontEndSteering(for url: URL) -> DXVKSteering? {
        let steering = DXVKSteering.inspect(executable: url)
        switch steering {
        case .chromiumFrontEnd, .chromiumRuntime:
            return steering
        case .launcher, nil:
            return nil
        }
    }

    /// Whether a front end's choice, its own override or else the bottle's
    /// backend, leaves it to Recommended's DXVK: Recommended, or DXVK itself.
    /// An explicit D3DMetal, DXMT or WineD3D choice is the user's.
    static func frontEndWantsDXVK(choice: GraphicsBackend) -> Bool {
        switch choice {
        case .recommended, .dxvk:
            true
        case .d3dMetal, .dxmt, .wined3d:
            false
        }
    }

    /// The table's front ends installed in a bottle, found at their known
    /// install locations with one `fileExists` each and no folder walk.
    ///
    /// - Parameters:
    ///   - bottleURL: The bottle to look in.
    ///   - steamRoot: The bottle's Steam install, whose libraries are checked
    ///     too; `nil` when it has none.
    static func frontEndExecutables(bottleURL: URL, steamRoot: URL?) -> [URL] {
        let libraries = steamRoot.map { SteamLibrary.libraryRoots(steamRoot: $0, bottleURL: bottleURL) } ?? []
        return ChromiumFrontEnd.all.flatMap {
            $0.installedExecutables(bottleURL: bottleURL, steamLibraries: libraries)
        }
    }
}
