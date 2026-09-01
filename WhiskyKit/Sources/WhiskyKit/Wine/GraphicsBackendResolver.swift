//
//  GraphicsBackendResolver.swift
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

/// Resolves the `.recommended` graphics backend to a concrete backend.
///
/// This is a caseless enum (static methods only) following the ``GPUDetection`` pattern.
/// The resolver centralises the heuristic so that future improvements (e.g., preferring
/// DXVK on specific GPU families) can be made without changing the data model or UI.
public enum GraphicsBackendResolver {
    /// Resolves the recommended graphics backend for the current system.
    ///
    /// D3DMetal is the best-supported path on macOS 15+ Apple Silicon, but only
    /// GPTK-based runtimes bundle its payload. Recommending it on a runtime
    /// without the payload makes launches silently fall back to wined3d, which
    /// cannot bring up D3D11 on current macOS — so the resolver only recommends
    /// backends that are actually installed: DXMT (native D3D11-to-Metal) when
    /// the runtime bundles it, otherwise DXVK, which ships with every runtime.
    ///
    /// - Parameters:
    ///   - launcher: The launcher this launch targets, if any. Launchers always
    ///     resolve to DXVK: their Chromium UIs cannot render on D3DMetal or DXMT.
    ///   - macOSVersion: The macOS version to consider. Defaults to the running system.
    ///   - runtimeInfo: The runtime record to consider. Defaults to the installed
    ///     runtime's version plist.
    ///   - d3dMetalInstalled: Whether the D3DMetal payload exists on disk. Defaults
    ///     to checking the installed runtime.
    ///   - dxmtRuntimeNative: Whether the runtime's DXMT payload is the native
    ///     variant. Defaults to checking the installed runtime.
    /// - Returns: A concrete ``GraphicsBackend`` (never `.recommended`).
    public static func resolve(
        for launcher: LauncherType? = nil,
        macOSVersion: MacOSVersion = .current,
        runtimeInfo: WhiskyWineVersion? = WhiskyWineInstaller.whiskyWineInfo(),
        d3dMetalInstalled: Bool = WhiskyWineInstaller.isD3DMetalInstalled(),
        dxmtRuntimeNative: Bool = Wine.isDXMTRuntimeNative()
    ) -> GraphicsBackend {
        // Launcher clients are Chromium and cannot render on D3DMetal or DXMT:
        // the CEF gpu process fails to create its window swapchain and the
        // client shows no window (or a black one). DXVK is the one backend
        // their UIs render on, so a launcher gets it regardless of what else
        // is installed. Games a launcher starts still resolve below.
        if launcher != nil {
            return .dxvk
        }
        if d3dMetalInstalled {
            return .d3dMetal
        }
        // The same gate the backend picker applies, not the version record
        // alone: a version-only check lets auto promise DXMT on a runtime
        // whose payload is missing or builtin-variant, which then throws
        // payloadMissing at launch after the picker refused the same choice.
        if WhiskyWineInstaller.backendAvailability(
            .dxmt,
            runtimeInfo: runtimeInfo,
            d3dMetalInstalled: d3dMetalInstalled,
            dxmtRuntimeNative: dxmtRuntimeNative
        ) {
            return .dxmt
        }
        return .dxvk
    }

    /// Returns a localized explanation for the recommended backend choice.
    ///
    /// Suitable for display in a detail label or tooltip next to the "Recommended" option.
    ///
    /// - Parameter macOSVersion: The macOS version to consider. Defaults to the running system.
    /// - Returns: A human-readable rationale string.
    public static func rationale(macOSVersion: MacOSVersion = .current) -> String {
        String(localized: "config.graphics.backend.recommended.rationale")
    }
}
