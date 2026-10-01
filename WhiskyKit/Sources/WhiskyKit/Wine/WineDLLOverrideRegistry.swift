//
//  WineDLLOverrideRegistry.swift
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

public extension Wine {
    /// Where a set of DLL overrides lives in the prefix registry.
    enum DLLOverrideScope: Equatable, Sendable {
        /// The prefix default, used by any process without an entry of its own.
        case bottle
        /// This executable only. Children do not inherit it.
        case program(String)

        var registryKey: String {
            switch self {
            case .bottle:
                #"HKCU\Software\Wine\DllOverrides"#
            case let .program(executable):
                // \\#( is a literal backslash then the interpolation; \#( alone
                // would swallow the path separator.
                #"HKCU\Software\Wine\AppDefaults\\#(executable)\DllOverrides"#
            }
        }
    }

    private static let dllOverrideLogger = Logger(
        subsystem: "com.isaacmarovitz.WhiskyKit", category: "dll-overrides"
    )

    /// Writes each scope's `WINEDLLOVERRIDES`-syntax overrides into a bottle's
    /// registry: ``syncDLLOverrides(bottle:scopes:)`` outside of tests.
    typealias DLLOverrideWriter = @MainActor (
        _ bottle: Bottle, _ scopes: [(scope: DLLOverrideScope, overrides: String)]
    ) async throws -> Void

    /// Replaces the DLL overrides at each scope, in one import.
    ///
    /// One import rather than a `reg` call per value: each of those is a whole
    /// wine process, and a launch syncing a bottle plus a launcher and its
    /// helpers spent twenty-odd of them before starting anything.
    ///
    /// - Parameters:
    ///   - bottle: The bottle whose prefix registry is written.
    ///   - scopes: Each scope and the `WINEDLLOVERRIDES`-syntax string it
    ///     should hold. An empty string clears that scope.
    @MainActor
    static func syncDLLOverrides(
        bottle: Bottle, scopes: [(scope: DLLOverrideScope, overrides: String)]
    ) async throws {
        let document = registryDocument(
            for: scopes.map { (key: $0.scope.registryKey, overrides: parseDLLOverrides($0.overrides)) }
        )
        let url = FileManager.default.temporaryDirectory
            .appending(path: "whisky-dll-overrides-\(UUID().uuidString).reg")
        // Wine detects a Unicode .reg by its BOM alone, and `.utf16LittleEndian`
        // writes none — the file parses as ANSI, matches no header, and imports
        // nothing while exiting 0. Written explicitly rather than via `.utf16`,
        // whose BOM follows platform endianness.
        try ("\u{FEFF}" + document).write(to: url, atomically: true, encoding: .utf16LittleEndian)
        defer { try? FileManager.default.removeItem(at: url) }

        // `reg import`, not `regedit`: regedit has no silent switch, so it puts up
        // the import confirmation and never exits.
        try await runWine(["reg", "import", url.path(percentEncoded: false)], bottle: bottle)
        dllOverrideLogger.debug("Synced DLL overrides for \(scopes.count) scope(s) in one import")
    }

    /// Moves this launch's DLL overrides from the environment into the registry.
    ///
    /// Registry, not `WINEDLLOVERRIDES`: the variable is inherited by every child,
    /// so a launcher's backend became every game's, and wine reads it before the
    /// registry, which left `AppDefaults` entries dead while it was set.
    ///
    /// - Parameter applyToDescendants: When the overrides describe something this
    ///   process will *spawn*, `AppDefaults` cannot express it — that is keyed on
    ///   an executable whose name is not known here — so the variable stays.
    /// - Parameter recommendedBackend: What `.recommended` resolves to for the
    ///   bottle; `nil` asks ``GraphicsBackendResolver``.
    /// - Parameter builtinD3D12IsD3DMetal: Whether the runtime's builtin `d3d12`
    ///   is D3DMetal's, passed on to every composition written here.
    /// - Parameter writer: What performs the registry write.
    @MainActor
    static func applyDLLOverrides(
        for url: URL,
        bottle: Bottle,
        wineEnvironment: inout [String: String],
        applyToDescendants: Bool,
        recommendedBackend: GraphicsBackend? = nil,
        builtinD3D12IsD3DMetal: Bool = GPTKImporter.isDeployed(),
        writer: DLLOverrideWriter = { try await syncDLLOverrides(bottle: $0, scopes: $1) }
    ) async throws {
        let bottleOverrides = constructWineEnvironment(
            for: bottle, recommendedBackend: recommendedBackend, builtinD3D12IsD3DMetal: builtinD3D12IsD3DMetal
        )["WINEDLLOVERRIDES"] ?? ""
        var scopes: [(scope: DLLOverrideScope, overrides: String)] = [
            (scope: .bottle, overrides: bottleOverrides)
        ]
        let launcher = LauncherType.detect(from: url)
        // What a launcher draws with no matter what the bottle's games use: the
        // bottle's set with DXVK on top, the backend the resolver steers every
        // launcher to.
        let steeredLauncherOverrides = launcherDLLOverrides(
            bottle: bottle, recommendedBackend: recommendedBackend, builtinD3D12IsD3DMetal: builtinD3D12IsD3DMetal
        )

        // The helper entries are written either way. A launcher's helper is
        // usually Chromium, which probes for an NVIDIA GPU on startup: answering
        // makes it load D3DMetal and take the helper down, and a dead helper is a
        // launcher that draws nothing. Games need nvapi64, because Streamline
        // asks it about the GPU before it will consider DLSS at all, so it is
        // disabled per helper rather than withheld from the bottle.
        //
        // Outside the `applyToDescendants` branch on purpose. A Steam game launch
        // sets that flag, and this sync *replaces* each key it writes, so leaving
        // the helpers out did not merely skip them, it cleared any entry they
        // already had and handed Chromium nvapi64 again. The overrides on such a
        // launch are the game's, so the helpers get the launcher's own set
        // instead. The bottle's set is not that: the bottle stays on its own
        // backend (D3DMetal, for one left on Recommended), and a helper that
        // restarts after a game launch rewrote its entry from it would load
        // D3DMetal and crash-loop (#276).
        let helperOverrides = applyToDescendants
            ? steeredLauncherOverrides
            : (wineEnvironment["WINEDLLOVERRIDES"] ?? "")
        for executable in helperExecutables(for: url) {
            scopes.append((
                scope: .program(executable),
                overrides: disablingNVAPI(in: helperOverrides)
            ))
        }

        if applyToDescendants {
            // The launcher keeps its own entry too, so a game launch never
            // leaves it without DXVK. The game's set stays in the environment.
            if launcher != nil {
                scopes.append((scope: .program(url.lastPathComponent), overrides: steeredLauncherOverrides))
            }
        } else {
            let programOverrides = wineEnvironment.removeValue(forKey: "WINEDLLOVERRIDES") ?? ""
            // The launched executable needs its own entry too: AppDefaults is per
            // executable and children do not inherit it.
            scopes.append((scope: .program(url.lastPathComponent), overrides: programOverrides))
        }

        let taken = Set(scopes.compactMap { entry -> String? in
            guard case let .program(executable) = entry.scope else { return nil }
            return executable.lowercased()
        })
        for executable in chainExecutables(for: launcher, bottleURL: bottle.url)
            where !taken.contains(executable.lowercased()) {
            scopes.append((scope: .program(executable), overrides: disablingD3D12(in: steeredLauncherOverrides)))
        }

        try await writer(bottle, scopes)
    }

    /// The DLL overrides a launcher's own processes run with: the bottle's set
    /// with the DXVK preset on top.
    ///
    /// The resolver sends every launcher to DXVK (#252), because Chromium cannot
    /// draw on D3DMetal or DXMT. Pinned rather than resolved, so it holds for a
    /// bottle on any backend, and it never goes into the bottle scope: that one
    /// is the games'.
    @MainActor
    static func launcherDLLOverrides(
        bottle: Bottle,
        recommendedBackend: GraphicsBackend? = nil,
        builtinD3D12IsD3DMetal: Bool = GPTKImporter.isDeployed()
    ) -> String {
        var pinned = ProgramOverrides()
        pinned.graphicsBackend = .dxvk
        return constructWineEnvironment(
            for: bottle, programOverrides: pinned,
            recommendedBackend: recommendedBackend, builtinD3D12IsD3DMetal: builtinD3D12IsD3DMetal
        )["WINEDLLOVERRIDES"] ?? ""
    }

    /// The launcher executables a launch of `launcher` should write entries for
    /// ahead of time, because something other than Whisky starts them.
    ///
    /// Rockstar's chain rides along with Steam launches as well as Rockstar's
    /// own, since a Rockstar title bought on Steam starts it inside the Steam
    /// session. Only once the Rockstar Games Launcher is installed in the
    /// bottle: `AppDefaults` is keyed on the file name alone, and `Launcher.exe`
    /// is a common one, so a bottle without Rockstar's gets no such entry.
    static func chainExecutables(for launcher: LauncherType?, bottleURL: URL) -> [String] {
        guard launcher == .steam || launcher == .rockstar, rockstarInstalled(bottleURL: bottleURL) else {
            return []
        }
        return LauncherType.rockstar.chainExecutables
    }

    /// Whether the bottle has a `Rockstar Games` folder in either Program Files.
    static func rockstarInstalled(bottleURL: URL) -> Bool {
        let driveC = bottleURL.appending(path: "drive_c")
        return ["Program Files", "Program Files (x86)"].contains { programFiles in
            let folder = driveC.appending(path: programFiles).appending(path: "Rockstar Games")
            return FileManager.default.fileExists(atPath: folder.path(percentEncoded: false))
        }
    }

    /// Renders a `.reg` leaving each key holding exactly `overrides`.
    ///
    /// `[-Key]` then `[Key]` is a replace, since `.reg` runs in order. That is
    /// what prunes stale values without reading the key back first.
    static func registryDocument(for scopes: [(key: String, overrides: [String: String])]) -> String {
        var lines = ["Windows Registry Editor Version 5.00", ""]
        for scope in scopes {
            lines.append("[-\(scope.key)]")
            lines.append("")
            let renderable = scope.overrides
                .filter { isRenderable(dll: $0.key, mode: $0.value) }
                .sorted { $0.key < $1.key }
            guard !renderable.isEmpty else { continue }
            lines.append("[\(scope.key)]")
            for (dll, mode) in renderable {
                lines.append("\"\(dll)\"=\"\(mode)\"")
            }
            lines.append("")
        }
        return lines.joined(separator: "\r\n")
    }

    /// Whether an override can be rendered without corrupting the document.
    ///
    /// Custom overrides are user-typed, and a quote or backslash in a name would
    /// terminate the value early and take every later scope down with it. A DLL
    /// name is a filename and a mode is a list of known words, so anything
    /// outside these sets could not have loaded regardless — dropping it costs
    /// nothing and contains the blast radius to the one bad entry.
    static func isRenderable(dll: String, mode: String) -> Bool {
        let name = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._-+")
        let modes = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz,")
        guard !dll.isEmpty else { return false }
        return dll.lowercased().unicodeScalars.allSatisfy(name.contains)
            && mode.lowercased().unicodeScalars.allSatisfy(modes.contains)
    }

    /// The launcher helpers that must share `url`'s DLL overrides.
    ///
    /// Detected from the executable, not the bottle's recorded launcher: they
    /// need the entry because of how wine resolves `AppDefaults`, not because
    /// the user enabled launcher fixes.
    static func helperExecutables(for url: URL) -> [String] {
        LauncherType.detect(from: url)?.helperExecutables ?? []
    }

    /// Adds `nvapi64=`, `nvapi=`, and `nvngx=` to an override string, keeping whatever else it holds.
    ///
    /// - Parameter overrides: A `WINEDLLOVERRIDES`-syntax string, possibly empty.
    /// - Returns: The same string with NVIDIA bridges disabled.
    static func disablingNVAPI(in overrides: String) -> String {
        var parsed = parseDLLOverrides(overrides)
        parsed["nvapi64"] = ""
        parsed["nvapi"] = ""
        parsed["nvngx"] = ""
        return parsed.keys.sorted().map { "\($0)=\(parsed[$0] ?? "")" }.joined(separator: ";")
    }

    /// Adds `d3d12=` to an override string, keeping whatever else it holds.
    ///
    /// - Parameter overrides: A `WINEDLLOVERRIDES`-syntax string, possibly empty.
    /// - Returns: The same string with `d3d12` disabled.
    static func disablingD3D12(in overrides: String) -> String {
        var parsed = parseDLLOverrides(overrides)
        parsed["d3d12"] = ""
        return parsed.keys.sorted().map { "\($0)=\(parsed[$0] ?? "")" }.joined(separator: ";")
    }

    /// Parses a `WINEDLLOVERRIDES` string into DLL name to load-order pairs.
    ///
    /// The registry takes the same syntax, so values pass through unchanged.
    /// `dll=` is kept: an empty value is how a DLL is disabled in both forms.
    static func parseDLLOverrides(_ overrides: String) -> [String: String] {
        var result: [String: String] = [:]
        for clause in overrides.split(separator: ";") {
            let parts = clause.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let name = parts.first else { continue }
            let dll = name.trimmingCharacters(in: .whitespaces)
            guard !dll.isEmpty else { continue }
            result[dll] = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
        }
        return result
    }
}
