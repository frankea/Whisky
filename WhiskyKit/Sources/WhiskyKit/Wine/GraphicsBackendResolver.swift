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
        resolution(
            for: launcher.map { DXVKSteering.launcher($0) }, macOSVersion: macOSVersion,
            runtimeInfo: runtimeInfo, d3dMetalInstalled: d3dMetalInstalled, dxmtRuntimeNative: dxmtRuntimeNative
        ).backend
    }

    /// Resolves the recommended graphics backend for what is being launched,
    /// with the reason for the pick.
    ///
    /// - Parameters:
    ///   - steering: Why the executable being launched needs DXVK, if it does
    ///     (``DXVKSteering/inspect(executable:)``). A steered executable always
    ///     resolves to DXVK: its window is drawn by Chromium, which cannot
    ///     render on D3DMetal or DXMT.
    ///   - macOSVersion: The macOS version to consider. Defaults to the running system.
    ///   - runtimeInfo: The runtime record to consider. Defaults to the installed
    ///     runtime's version plist.
    ///   - d3dMetalInstalled: Whether the D3DMetal payload exists on disk. Defaults
    ///     to checking the installed runtime.
    ///   - dxmtRuntimeNative: Whether the runtime's DXMT payload is the native
    ///     variant. Defaults to checking the installed runtime.
    /// - Returns: A concrete backend (never `.recommended`) and why it was picked.
    public static func resolution(
        for steering: DXVKSteering?,
        macOSVersion: MacOSVersion = .current,
        runtimeInfo: WhiskyWineVersion? = WhiskyWineInstaller.whiskyWineInfo(),
        d3dMetalInstalled: Bool = WhiskyWineInstaller.isD3DMetalInstalled(),
        dxmtRuntimeNative: Bool = Wine.isDXMTRuntimeNative()
    ) -> BackendResolution {
        // Launcher clients and Chromium front ends cannot render on D3DMetal or
        // DXMT: the CEF gpu process fails to create its window swapchain and
        // the window stays black, or never appears. DXVK is the one backend
        // their UIs render on, so they get it regardless of what else is
        // installed. What they start still resolves below.
        if let steering {
            return BackendResolution(backend: .dxvk, reason: .steered(steering))
        }
        if d3dMetalInstalled {
            return BackendResolution(backend: .d3dMetal, reason: .d3dMetal)
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
            return BackendResolution(backend: .dxmt, reason: .dxmt)
        }
        return BackendResolution(backend: .dxvk, reason: .dxvkFallback)
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

/// Why an executable needs DXVK whatever Recommended picks for the bottle's
/// games: its window is drawn by Chromium.
public enum DXVKSteering: Sendable, Equatable {
    /// A launcher client, which also gets its helpers and chain entries.
    case launcher(LauncherType)
    /// A program from the curated ``ChromiumFrontEnd`` table.
    case chromiumFrontEnd(ChromiumFrontEnd)
    /// An Electron or NW.js app, found by its files (``ChromiumRuntimeDetector``).
    /// `evidence` is the file beside it that identified it, such as
    /// `resources/app.asar`.
    case chromiumRuntime(kind: ChromiumRuntimeKind, evidence: String)

    /// Detects the steering for an executable: a launcher first, so every
    /// launcher keeps its own path, then the front-end table. String matching
    /// only, so it is safe in a view body. Electron and NW.js apps need their
    /// files read: ``inspect(executable:)``.
    public static func detect(executable url: URL) -> DXVKSteering? {
        if let launcher = LauncherType.detect(from: url) {
            return .launcher(launcher)
        }
        return ChromiumFrontEnd.match(url: url).map { .chromiumFrontEnd($0) }
    }

    /// The launcher's or front end's name, or the runtime's, as shown in the UI.
    public var displayName: String {
        switch self {
        case let .launcher(launcher):
            launcher.displayName
        case let .chromiumFrontEnd(frontEnd):
            frontEnd.displayName
        case let .chromiumRuntime(kind, _):
            kind.displayName
        }
    }

    /// The name a steered program is listed under: the launcher's or front
    /// end's, and an Electron or NW.js app's own, from its executable.
    public func listedName(executable url: URL) -> String {
        guard case .chromiumRuntime = self else { return displayName }
        return url.deletingPathExtension().lastPathComponent
    }

    /// Separate executables that share the steered executable's set, with the
    /// NVIDIA bridges disabled.
    public var helperExecutables: [String] {
        switch self {
        case let .launcher(launcher):
            launcher.helperExecutables
        case let .chromiumFrontEnd(frontEnd):
            frontEnd.helperExecutables
        case .chromiumRuntime:
            // Its Chromium children run as the same executable.
            []
        }
    }

    /// The evidence, for logs and diagnostics exports. Not localized.
    public var evidence: String {
        switch self {
        case let .launcher(launcher):
            "launcher: \(launcher.rawValue)"
        case let .chromiumFrontEnd(frontEnd):
            "Chromium front end: \(frontEnd.displayName)"
        case let .chromiumRuntime(kind, evidence):
            "\(kind.displayName) app: \(evidence)"
        }
    }
}

/// Why Recommended resolved to the backend it did.
public enum RecommendedReason: Sendable, Equatable {
    /// The executable's window is drawn by Chromium, so it runs on DXVK.
    case steered(DXVKSteering)
    /// The GPTK payload is installed.
    case d3dMetal
    /// The runtime bundles a native DXMT payload, and there is no GPTK.
    case dxmt
    /// Neither is available; DXVK ships with every runtime.
    case dxvkFallback

    /// A short, stable description for diagnostics exports. Not localized.
    public var exportName: String {
        switch self {
        case let .steered(steering):
            "steered to DXVK (\(steering.evidence))"
        case .d3dMetal:
            "D3DMetal payload installed"
        case .dxmt:
            "native DXMT payload, no D3DMetal"
        case .dxvkFallback:
            "DXVK fallback, no D3DMetal or DXMT"
        }
    }
}

/// The backend Recommended resolves to, and why.
public struct BackendResolution: Sendable, Equatable {
    /// The concrete backend, never `.recommended`.
    public let backend: GraphicsBackend
    /// Why it was picked.
    public let reason: RecommendedReason

    public init(backend: GraphicsBackend, reason: RecommendedReason) {
        self.backend = backend
        self.reason = reason
    }

    /// A localized explanation of the pick.
    ///
    /// - Parameter gamesBackend: What Recommended resolves to for the bottle's
    ///   games, which the programs a steered executable starts keep.
    public func rationale(gamesBackend: GraphicsBackend) -> String {
        guard case let .steered(steering) = reason else {
            return GraphicsBackendResolver.rationale()
        }
        let games = gamesBackend.displayName
        let text = switch steering {
        case .launcher:
            String(localized: "config.graphics.backend.recommended.launcher \(games)")
        case .chromiumFrontEnd:
            String(localized: "config.graphics.backend.recommended.frontEnd \(games)")
        case let .chromiumRuntime(.electron, evidence):
            String(localized: "config.graphics.backend.recommended.electron \(evidence)")
        case let .chromiumRuntime(.nwjs, evidence):
            String(localized: "config.graphics.backend.recommended.nwjs \(evidence)")
        }
        // DXVK and DXMT share d3d11 and d3d10core in system32, so the last
        // deploy wins for whatever the steered program starts by itself.
        guard gamesBackend == .dxmt else { return text }
        return text + " " + String(localized: "config.graphics.backend.recommended.dxmtCaveat")
    }
}
