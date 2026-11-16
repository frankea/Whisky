//
//  Wine+DXVKDeployment.swift
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
    /// Whether a launch deploys DXVK's files into the prefix.
    ///
    /// The one condition behind the launch-time copy and the settings
    /// diagnostics that report whether a launcher gets DXVK, so the two cannot
    /// disagree.
    ///
    /// - Parameters:
    ///   - effectiveBackend: The launch's backend after program overrides and
    ///     `.recommended` resolution.
    ///   - legacyProgramDXVK: The program's legacy DXVK flag, honored only
    ///     without a program backend override.
    ///   - launcherCarriesDescendantPlan: A launcher started to carry a game's
    ///     plan; it still runs on DXVK.
    ///   - autoEnableDXVK: The bottle's "auto-enable DXVK for launchers" setting.
    ///   - detectedLauncher: The launcher the bottle's settings were tuned for.
    /// - Returns: `true` when DXVK's DLLs are copied in before the program starts.
    static func deploysDXVK(
        effectiveBackend: GraphicsBackend,
        legacyProgramDXVK: Bool,
        launcherCarriesDescendantPlan: Bool,
        autoEnableDXVK: Bool,
        detectedLauncher: LauncherType?
    ) -> Bool {
        effectiveBackend == .dxvk
            || legacyProgramDXVK
            || launcherCarriesDescendantPlan
            || (autoEnableDXVK && detectedLauncher?.requiresDXVK == true)
    }

    /// Copies DXVK in when the launch needs it, then places or takes back
    /// DXMT's trio beside the game's executables.
    ///
    /// DXVK is needed for the effective backend, the legacy program-level flag
    /// (honored only without a backend override, mirroring
    /// `applyProgramOverrides`), or launcher auto-enable. A launcher that only
    /// carries a game's plan still runs, and its helpers keep restarting, on
    /// DXVK: its files stay in place, and are copied after a DXMT plan's, so
    /// the launcher keeps working when the two share a file. DXMT's
    /// `winemetal.dll`, which DXVK does not ship, stays in `system32`.
    ///
    /// The game then finds DXMT's trio in its own folder, which Wine's loader
    /// searches before `system32` (#378). Any other plan takes back the copies
    /// Whisky placed there, so they cannot take over from that plan's layer.
    /// Starting Steam also takes back the copies of library games whose plan
    /// moved off DXMT since, which Play in Steam's own window would otherwise load.
    ///
    /// - Parameters:
    ///   - bottle: The bottle the launch runs in.
    ///   - effectiveBackend: The launch's backend after overrides and `.recommended` resolution.
    ///   - programOverrides: The launch's program overrides, for the legacy DXVK flag.
    ///   - launcherCarriesDescendantPlan: A launcher started to carry a game's plan.
    ///   - gameExecutables: The game's executables, or the launched executable itself.
    ///   - steamGamesBackend: When Steam is what starts, what `.recommended` resolves to for
    ///     its library games, whose plans decide which copies stay; `nil` for anything else.
    ///   - dxvkFolder: The DXVK payload.
    ///   - dxmtFolder: The DXMT payload.
    ///   - rockstar: The launch, for the Rockstar Games Launcher's Direct3D in
    ///     `system32` (``deployDXVK(bottle:from:rockstar:ops:)``); `nil`
    ///     deploys DXVK exactly as it was deployed before the swap existed.
    ///     Only read when the launch deploys DXVK: a launch on DXMT has
    ///     already put DXMT's `d3d11` into `system32`, and nothing here may
    ///     write over it.
    /// - Returns: The layout the launch decided for Rockstar's `Launcher.exe`,
    ///   or `nil` when it decided none and the DLL override step resolves it.
    /// - Throws: An error if DXVK's files cannot be copied. The game folders never throw.
    @MainActor
    @discardableResult
    static func deployLauncherAndGameLayers(
        bottle: Bottle, effectiveBackend: GraphicsBackend, programOverrides: ProgramOverrides?,
        launcherCarriesDescendantPlan: Bool, gameExecutables: [URL], steamGamesBackend: GraphicsBackend? = nil,
        dxvkFolder: URL = Wine.dxvkFolder, dxmtFolder: URL = Wine.dxmtFolder, rockstar: RockstarD3DLaunch? = nil
    ) throws -> RockstarD3DLayout? {
        let legacyProgramDXVK = programOverrides?.graphicsBackend == nil && programOverrides?.dxvk == true
        let shouldEnableDXVK = deploysDXVK(
            effectiveBackend: effectiveBackend, legacyProgramDXVK: legacyProgramDXVK,
            launcherCarriesDescendantPlan: launcherCarriesDescendantPlan,
            autoEnableDXVK: bottle.settings.autoEnableDXVK, detectedLauncher: bottle.settings.detectedLauncher
        )
        var rockstarLayout: RockstarD3DLayout?
        if shouldEnableDXVK {
            if let rockstar {
                rockstarLayout = try deployDXVK(bottle: bottle, from: dxvkFolder, rockstar: rockstar)
            } else {
                try enableDXVK(bottle: bottle, from: dxvkFolder)
            }
        }

        if let steamGamesBackend {
            SteamLauncher.retractStaleDXMTGameFolders(
                bottle: bottle, recommendedBackend: steamGamesBackend, payloadRoot: dxmtFolder
            )
        }

        reconcileDXMTGameFolders(
            DXMTGameFolderAction(
                effectiveBackend: effectiveBackend, launcherCarriesDescendantPlan: launcherCarriesDescendantPlan
            ),
            executables: gameExecutables, bottleURL: bottle.url, payloadRoot: dxmtFolder
        )
        return rockstarLayout
    }
}

extension BottleSettings {
    /// Whether launching `launcher` in this bottle gets DXVK, by the same
    /// condition the launch itself uses.
    ///
    /// The bottle's backend applies (no program override). Set to Recommended,
    /// it resolves for the launcher, which always means DXVK; otherwise DXVK
    /// still arrives through the launcher auto-enable when this bottle's
    /// detected launcher requires it.
    ///
    /// - Parameter launcher: The launcher being launched.
    /// - Returns: `true` when the launch deploys DXVK.
    public func deploysDXVK(whenLaunching launcher: LauncherType) -> Bool {
        // A launcher resolves before any runtime check, so the runtime
        // arguments are passed as constants instead of reading the disk on
        // every view update.
        let effectiveBackend = graphicsBackend == .recommended
            ? GraphicsBackendResolver.resolve(
                for: launcher,
                runtimeInfo: nil,
                d3dMetalInstalled: false,
                dxmtRuntimeNative: false
            )
            : graphicsBackend
        return Wine.deploysDXVK(
            effectiveBackend: effectiveBackend,
            legacyProgramDXVK: false,
            launcherCarriesDescendantPlan: false,
            autoEnableDXVK: autoEnableDXVK,
            detectedLauncher: detectedLauncher
        )
    }
}
