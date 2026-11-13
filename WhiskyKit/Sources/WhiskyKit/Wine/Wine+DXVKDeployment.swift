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
