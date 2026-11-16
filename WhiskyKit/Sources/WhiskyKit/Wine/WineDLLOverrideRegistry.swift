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
        /// wined3d's settings for this executable only, beside its DLL
        /// overrides. Its values are settings, not DLLs: ``ownedValueNames``.
        case direct3D(String)

        var registryKey: String {
            switch self {
            case .bottle:
                #"HKCU\Software\Wine\DllOverrides"#
            case let .program(executable):
                // \\#( is a literal backslash then the interpolation; \#( alone
                // would swallow the path separator.
                #"HKCU\Software\Wine\AppDefaults\\#(executable)\DllOverrides"#
            case let .direct3D(executable):
                #"HKCU\Software\Wine\AppDefaults\\#(executable)\Direct3D"#
            }
        }
    }

    internal static let dllOverrideLogger = Logger(
        subsystem: "com.isaacmarovitz.WhiskyKit", category: "dll-overrides"
    )

    /// Writes each scope's `WINEDLLOVERRIDES`-syntax overrides into a bottle's
    /// registry: ``syncDLLOverrides(bottle:scopes:)`` outside of tests.
    typealias DLLOverrideWriter = @MainActor (
        _ bottle: Bottle, _ scopes: [(scope: DLLOverrideScope, overrides: String)]
    ) async throws -> Void

    /// Writes the DLL overrides at each scope, in one import.
    ///
    /// One import rather than a `reg` call per value: each of those is a whole
    /// wine process, and a launch syncing a bottle plus a launcher and its
    /// helpers spent twenty-odd of them before starting anything.
    ///
    /// Values another tool wrote are left alone: only names Whisky could have
    /// written are removed (``registryDocument(for:record:ownedValues:)``).
    ///
    /// - Parameters:
    ///   - bottle: The bottle whose prefix registry is written.
    ///   - scopes: Each scope and the `WINEDLLOVERRIDES`-syntax string it
    ///     should hold. An empty string takes back what Whisky wrote there.
    @MainActor
    static func syncDLLOverrides(
        bottle: Bottle, scopes: [(scope: DLLOverrideScope, overrides: String)]
    ) async throws {
        try await syncDLLOverrides(bottle: bottle, scopes: scopes) { document, bottle in
            try await importDLLOverrideDocument(document, bottle: bottle)
        }
    }

    /// The last sync started in each bottle, for the next one to wait on.
    @MainActor private static var syncTails: [URL: Task<Void, Never>] = [:]

    /// ``syncDLLOverrides(bottle:scopes:)`` with the import itself supplied, so
    /// tests can run it against a simulated registry.
    ///
    /// Syncs in one bottle run one at a time. Each builds its document from the
    /// names the record holds when it starts, so one that started during
    /// another's import missed that import's names: neither document removed
    /// them, and the record then forgot them, leaving overrides Whisky wrote
    /// that it would never take back.
    ///
    /// `currentValue` reads what a key of settings holds now, the bottle's
    /// `user.reg` when `nil`; tests pass their simulated registry.
    @MainActor
    internal static func syncDLLOverrides(
        bottle: Bottle, scopes: [(scope: DLLOverrideScope, overrides: String)],
        importer: @escaping RegistryImporter, currentValue: RegistryValueReader? = nil
    ) async throws {
        let key = bottle.url.standardizedFileURL
        let previous = syncTails[key]
        let reader = currentValue ?? { registryValue(bottleURL: bottle.url, key: $0, name: $1) }
        let sync = Task { @MainActor in
            await previous?.value
            try await syncDLLOverridesNow(bottle: bottle, scopes: scopes, importer: importer, currentValue: reader)
        }
        let tail = Task { @MainActor in _ = try? await sync.value }
        syncTails[key] = tail
        defer {
            if syncTails[key] == tail {
                syncTails[key] = nil
            }
        }
        try await sync.value
    }

    @MainActor
    private static func syncDLLOverridesNow(
        bottle: Bottle, scopes: [(scope: DLLOverrideScope, overrides: String)],
        importer: RegistryImporter, currentValue: RegistryValueReader
    ) async throws {
        let planned = scopes.filter { $0.scope.ownedValueNames == nil }
            .map { (key: $0.scope.registryKey, overrides: parseDLLOverrides($0.overrides)) }
        let snapshot = DLLOverrideRecord.load(from: bottle.url)
        let owned = ownedValueEdits(for: scopes, record: snapshot, current: currentValue)
        try await importer(registryDocument(for: planned, record: snapshot, ownedValues: owned), bottle)
        // Only after the import: a failed one leaves the old names recorded, so
        // the next launch still takes them back. Read again rather than saving
        // `snapshot`, so names saved some other way during the import (the
        // record is one file per bottle) are kept. Nothing suspends between
        // this load and the save.
        do {
            try DLLOverrideRecord.load(from: bottle.url).updated(with: planned).updated(with: owned)
                .save(to: bottle.url)
        } catch {
            dllOverrideLogger.error("Could not record the DLL overrides written: \(error.localizedDescription)")
        }
        dllOverrideLogger.debug("Synced DLL overrides for \(scopes.count) scope(s) in one import")
    }

    /// Runs `reg import` on a DLL override document in the bottle.
    @MainActor
    private static func importDLLOverrideDocument(_ document: String, bottle: Bottle) async throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "whisky-dll-overrides-\(UUID().uuidString).reg")
        // Wine detects a Unicode .reg by its BOM alone, and `.utf16LittleEndian`
        // writes none: the file parses as ANSI, matches no header, and imports
        // nothing while exiting 0. Written explicitly rather than via `.utf16`,
        // whose BOM follows platform endianness.
        try ("\u{FEFF}" + document).write(to: url, atomically: true, encoding: .utf16LittleEndian)
        defer { try? FileManager.default.removeItem(at: url) }

        // `reg import`, not `regedit`: regedit has no silent switch, so it puts up
        // the import confirmation and never exits.
        try await runWine(["reg", "import", url.path(percentEncoded: false)], bottle: bottle)
    }

    /// Moves this launch's DLL overrides from the environment into the registry.
    ///
    /// Registry, not `WINEDLLOVERRIDES`: the variable is inherited by every child,
    /// so a launcher's backend became every game's, and wine reads it before the
    /// registry, which left `AppDefaults` entries dead while it was set.
    ///
    /// Besides the bottle scope and the launched executable, every launch in a
    /// bottle with Steam writes Steam's own processes their launcher set, so
    /// `steam.exe` has its entry even when the Steam installer or Windows
    /// autostart starts it rather than Whisky.
    ///
    /// - Parameter applyToDescendants: Whether the overrides describe something
    ///   this process will *spawn*, as on `steam.exe -applaunch`. For a launcher
    ///   they go into the `AppDefaults` entries of `descendantExecutables`, and
    ///   the environment keeps none, so whichever process the launcher starts
    ///   (the client itself, when it was not running, or a game) reads its own
    ///   entry. For anything else the variable stays, since `AppDefaults` cannot
    ///   express overrides for an executable whose name is not known.
    /// - Parameter descendantExecutables: The executable names the overrides
    ///   belong to when they apply to descendants.
    /// - Parameter ownSettingsExecutables: Descendants that keep their own
    ///   settings, written ahead of the descendants' overrides.
    /// - Parameter descendantLaunchers: Launchers the descendants start on their
    ///   own, whose ``LauncherType/chainExecutables`` need entries ahead of time.
    /// - Parameter recommendedBackend: What `.recommended` resolves to for the
    ///   bottle; `nil` asks ``GraphicsBackendResolver``.
    /// - Parameter builtinD3D12IsD3DMetal: Whether the runtime's builtin `d3d12`
    ///   is D3DMetal's, passed on to every composition written here.
    /// - Parameter rockstarLayout: What Rockstar's `Launcher.exe` gets, when its
    ///   entries are written; `nil` reads the runtime (``RockstarD3DLayout``).
    /// - Parameter writer: What performs the registry write.
    @MainActor
    static func applyDLLOverrides(
        for url: URL,
        bottle: Bottle,
        wineEnvironment: inout [String: String],
        applyToDescendants: Bool,
        descendantExecutables: [String] = [],
        ownSettingsExecutables: [URL] = [],
        descendantLaunchers: [LauncherType] = [],
        recommendedBackend: GraphicsBackend? = nil,
        builtinD3D12IsD3DMetal: Bool = GPTKImporter.isDeployed(),
        rockstarLayout: RockstarD3DLayout? = nil,
        writer: DLLOverrideWriter = { try await syncDLLOverrides(bottle: $0, scopes: $1) }
    ) async throws {
        let resolveRockstarLayout = { rockstarLayout ?? .resolve(payloadDeployed: builtinD3D12IsD3DMetal) }
        let bottleOverrides = constructWineEnvironment(
            for: bottle, recommendedBackend: recommendedBackend, builtinD3D12IsD3DMetal: builtinD3D12IsD3DMetal
        )["WINEDLLOVERRIDES"] ?? ""
        var scopes = DLLOverrideScopes(bottle: bottleOverrides)
        let launcher = LauncherType.detect(from: url)
        let launcherSet = { (userOverrides: ProgramOverrides?) in
            launcherDLLOverrides(
                bottle: bottle, userOverrides: userOverrides,
                recommendedBackend: recommendedBackend, builtinD3D12IsD3DMetal: builtinD3D12IsD3DMetal
            )
        }

        // The launched executable and its helpers. A launcher's helper is
        // usually Chromium, which probes for an NVIDIA GPU on startup: answering
        // makes it load D3DMetal and take the helper down, and a dead helper is a
        // launcher that draws nothing. Games need nvapi64, because Streamline
        // asks it about the GPU before it will consider DLSS at all, so it is
        // disabled per helper rather than withheld from the bottle.
        //
        // The helpers are written on a Steam game launch too. The sync used to
        // *replace* each key it wrote, so leaving them out did not merely skip
        // them, it cleared any entry they already had and handed Chromium
        // nvapi64 again. The overrides on such a launch are the game's, so the
        // launcher and its helpers get the launcher's own set instead: the
        // bottle's set is not that (D3DMetal, for a bottle on Recommended), and
        // a helper restarting after a game launch would crash-loop on it (#276).
        var gamePlan: String?
        if applyToDescendants, let launcher {
            gamePlan = wineEnvironment.removeValue(forKey: "WINEDLLOVERRIDES") ?? ""
            let own = launcherSet(Program.persistedOverrides(for: url, bottleURL: bottle.url))
            scopes.add(launcher.helperExecutables, disablingNVAPI(in: own))
            scopes.add([url.lastPathComponent], own)
        } else if !applyToDescendants {
            let own = wineEnvironment.removeValue(forKey: "WINEDLLOVERRIDES") ?? ""
            // Rockstar's launcher gets the chain's entries ahead of `own`, per-program overrides too.
            addRockstarDirectLaunchScopes(url, to: &scopes, layout: resolveRockstarLayout, launcherSet: launcherSet)
            scopes.add(helperExecutables(for: url), disablingNVAPI(in: own))
            // The launched executable needs its own entry too: AppDefaults is per
            // executable and children do not inherit it.
            scopes.add([url.lastPathComponent], own)
        }

        // Steam's own processes, whatever this launch is. Something other than
        // Whisky may start the client: its installer when it finishes, Windows
        // autostart, or a cold `-applaunch`. Without an entry it would run on the
        // bottle's backend, which over D3DMetal crash-loops its helpers.
        let steamRoot = SteamLibrary.detectInstall(bottleURL: bottle.url)
        if launcher == .steam || steamRoot != nil {
            let steamExe = steamRoot?.appending(path: "steam.exe")
            let own = launcherSet(steamExe.flatMap { Program.persistedOverrides(for: $0, bottleURL: bottle.url) })
            scopes.add(LauncherType.steam.helperExecutables, disablingNVAPI(in: own))
            scopes.add(["steam.exe"], own)
        }

        // Chromium front ends (3DMark's) get the launcher set: among what a Steam
        // launch starts, and wherever one is installed, since Steam's own Play
        // button or a shortcut starts it without Whisky (#372).
        addFrontEndScopes(
            ownSettingsExecutables + frontEndExecutables(bottleURL: bottle.url, steamRoot: steamRoot),
            to: &scopes, bottle: bottle, recommendedBackend: recommendedBackend, launcherSet: launcherSet
        )

        // The game's plan, in the entries of the executables it runs as. After
        // Steam's own, which a game executable never displaces.
        if let gamePlan {
            for (executable, own) in ownSettingsDLLOverrides(
                for: ownSettingsExecutables, bottle: bottle,
                recommendedBackend: recommendedBackend, builtinD3D12IsD3DMetal: builtinD3D12IsD3DMetal
            ) {
                scopes.add([executable], own)
            }
            scopes.add(descendantExecutables, gamePlan)
        }

        if !chainExecutables(for: launcher, descendantLaunchers: descendantLaunchers, bottleURL: bottle.url).isEmpty {
            addRockstarChainScopes(to: &scopes, layout: resolveRockstarLayout, launcherSet: launcherSet)
        }
        releaseRockstarRenderer(in: &scopes, bottleURL: bottle.url)

        try await writer(bottle, scopes.entries)
    }

    /// The scopes one launch writes, each executable at most once: the first
    /// set given for an executable wins, compared without case as Wine does.
    struct DLLOverrideScopes {
        private(set) var entries: [(scope: DLLOverrideScope, overrides: String)]
        private var taken: Set<String> = []

        init(bottle overrides: String) {
            entries = [(scope: .bottle, overrides: overrides)]
        }

        mutating func add(_ executables: [String], _ overrides: String) {
            for executable in executables
                where Self.isKeySegment(executable) && taken.insert(executable.lowercased()).inserted {
                entries.append((scope: .program(executable), overrides: overrides))
            }
        }

        /// Adds a key of settings (``DLLOverrideScope/ownedValueNames``) once, and nothing else.
        mutating func add(settings scope: DLLOverrideScope, _ values: String) {
            guard scope.ownedValueNames != nil, !entries.contains(where: { $0.scope == scope }) else { return }
            entries.append((scope: scope, overrides: values))
        }

        /// Whether `executable` already has its set, compared without case.
        func contains(_ executable: String) -> Bool {
            taken.contains(executable.lowercased())
        }

        /// Whether the name can go into an `AppDefaults` key header. A macOS
        /// file name can hold a line break, which ends the header early in
        /// the `.reg` document: Wine drops it, and that program's values land
        /// in the key before it. A backslash would make a subkey. Neither can
        /// be a Windows image name, so no process would match the entry. Only
        /// control codes count, not format characters: a zero-width non-joiner
        /// is an ordinary part of Persian words, and a file name with one is a
        /// real program.
        static func isKeySegment(_ executable: String) -> Bool {
            !executable.isEmpty && !executable.contains("\\")
                && !executable.unicodeScalars.contains { $0.properties.generalCategory == .control }
        }
    }

    /// The DLL overrides a launcher's own processes run with: the bottle's set
    /// with the DXVK preset on top, and the user's own overrides for the
    /// launcher's executable on top of that.
    ///
    /// The resolver sends every launcher to DXVK (#252), because Chromium cannot
    /// draw on D3DMetal or DXMT. Pinned rather than resolved, so it holds for a
    /// bottle on any backend, and it never goes into the bottle scope: that one
    /// is the games'. A backend the user picked for the launcher's executable
    /// itself is kept, as a launch of it from the Programs tab would.
    ///
    /// - Parameters:
    ///   - bottle: The bottle whose set to start from.
    ///   - userOverrides: The user's persisted overrides for the launcher's
    ///     executable (its custom DLL overrides, say), if any.
    ///   - recommendedBackend: What `.recommended` resolves to for the bottle.
    ///   - builtinD3D12IsD3DMetal: Whether the runtime's builtin `d3d12` is D3DMetal's.
    @MainActor
    static func launcherDLLOverrides(
        bottle: Bottle,
        userOverrides: ProgramOverrides? = nil,
        recommendedBackend: GraphicsBackend? = nil,
        builtinD3D12IsD3DMetal: Bool = GPTKImporter.isDeployed()
    ) -> String {
        var pinned = userOverrides ?? ProgramOverrides()
        if pinned.graphicsBackend == nil || pinned.graphicsBackend == .recommended {
            pinned.graphicsBackend = .dxvk
        }
        return constructWineEnvironment(
            for: bottle, programOverrides: pinned,
            recommendedBackend: recommendedBackend, builtinD3D12IsD3DMetal: builtinD3D12IsD3DMetal
        )["WINEDLLOVERRIDES"] ?? ""
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
