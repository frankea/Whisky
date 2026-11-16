//
//  DiagnosticExporter+Rockstar.swift
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

import CryptoKit
import Foundation

/// What a bottle's `system32` holds under one of the names the Rockstar
/// Games Launcher's Direct3D comes from.
enum System32DLLKind: Equatable {
    /// No file.
    case missing
    /// A file Wine marks as its own, which the loader passes over for the
    /// builtin in `lib/wine`.
    case builtinPlaceholder
    /// The installed DXVK's file, byte for byte.
    case dxvkPayload
    /// Wine's own copy for the installed engine with the builtin marker
    /// stripped, as a DXVK launch puts `dxgi` there and the Rockstar swap
    /// puts `d3d11` there.
    case wineStripped
    /// Any other file, by the first eight hex digits of its SHA-256.
    case nativeOther(String)

    var summary: String {
        switch self {
        case .missing: "missing"
        case .builtinPlaceholder: "builtin placeholder"
        case .dxvkPayload: "DXVK payload"
        case .wineStripped: "Wine's own, marker stripped (current engine)"
        case let .nativeOther(digest): "native other (\(digest))"
        }
    }
}

/// What a file the Rockstar swap recorded as one of its DXVK copies holds now.
enum RockstarD3DCopyKind: Equatable {
    /// What the record says Whisky wrote.
    case recorded
    /// The installed DXVK's file, though not what the record says: an older
    /// copy refreshed since, or one the record lost.
    case dxvkPayload
    /// Anything else, by the first eight hex digits of its SHA-256.
    case changed(String)
    /// No file.
    case missing

    var summary: String {
        switch self {
        case .recorded: "Whisky's copy"
        case .dxvkPayload: "DXVK payload (unrecorded)"
        case let .changed(digest): "changed (\(digest))"
        case .missing: "missing"
        }
    }
}

extension DiagnosticExporter {
    /// The `system32` DLLs `Launcher.exe` draws through.
    static let rockstarSystem32DLLs = ["d3d11.dll", "dxgi.dll", "d3d10core.dll"]

    /// The Rockstar Games Launcher's Direct3D layout, for a bottle with
    /// Rockstar installed; empty for any other.
    ///
    /// A launcher stuck at "Initializing" is a layout problem far more often
    /// than anything in its log (#382), and what decides the layout is spread
    /// over the runtime, the prefix and the registry. This puts it in one
    /// place: the layout a launch resolves, what the runtime's slots hold,
    /// what `system32` holds, the `AppDefaults` entries the chain reads, and
    /// whether an environment variable would outvote those entries.
    ///
    /// - Parameters:
    ///   - bottle: The bottle the report is for.
    ///   - options: Registry data is scrubbed like a log line unless sensitive
    ///     details were asked for.
    ///   - libraryFolder: The runtime's library folder.
    ///   - store: The GPTK store.
    ///   - dxvkFolder: The installed DXVK, `system32`'s files are compared against.
    ///   - payloadDeployed: Whether the GPTK payload is deployed.
    ///   - recommendedBackend: What `.recommended` resolves to for the bottle's
    ///     games, for the swap's consumer scan.
    @MainActor
    static func generateRockstarLayoutSection(
        bottle: Bottle,
        options: ExportOptions,
        libraryFolder: URL = WhiskyWineInstaller.libraryFolder,
        store: URL = GPTKImporter.storeFolder,
        dxvkFolder: URL = Wine.dxvkFolder,
        payloadDeployed: Bool = GPTKImporter.isDeployed(),
        recommendedBackend: GraphicsBackend = GraphicsBackendResolver.resolve()
    ) -> String {
        // A record outlives Rockstar's folder, and its copies are what is left to explain.
        guard Wine.rockstarInstalled(bottleURL: bottle.url) || RockstarD3DLayoutRecord.exists(in: bottle.url)
        else { return "" }
        let runtime = RockstarD3DRuntime(libraryFolder: libraryFolder, store: store)
        // The layout the runtime alone gives, which a launch that does not decide on the swap goes by.
        let layout = RockstarD3DLayout.resolve(
            payloadDeployed: payloadDeployed, libraryFolder: libraryFolder, store: store
        )
        let slots = RockstarD3DLayout.forwarders(libraryFolder: libraryFolder, store: store)
        let originals = RockstarD3DLayout.wineOriginals(libraryFolder: libraryFolder, store: store)

        var section = "### Rockstar Launcher Layout\n\n"
        section += "- **Layout:** \(layout.summary)\n"
        section += "- **GPTK payload deployed:** \(payloadDeployed ? "yes" : "no")\n"
        section += "- **Runtime d3d11.dll is a GPTK forwarder:** \(slots.d3d11 ? "yes" : "no")\n"
        section += "- **Runtime dxgi.dll is a GPTK forwarder:** \(slots.dxgi ? "yes" : "no")\n"
        // What the layout goes by while the payload is deployed: a hand-placed
        // payload is no forwarder of the store's, and not Wine's original either.
        section += "- **Runtime d3d11.dll is the stored Wine original:** \(originals.d3d11 ? "yes" : "no")\n"
        section += "- **Runtime dxgi.dll is the stored Wine original:** \(originals.dxgi ? "yes" : "no")\n"
        section += rockstarSwapLines(
            bottle: bottle, dxvkFolder: dxvkFolder,
            launch: RockstarD3DLaunch(
                url: bottle.url, launcher: nil, descendantLaunchers: [], recommendedBackend: recommendedBackend,
                payloadDeployed: payloadDeployed, runtime: runtime
            )
        )
        for executable in LauncherType.rockstar.chainExecutables {
            for scope in [Wine.DLLOverrideScope.program(executable), .direct3D(executable)] {
                let values = appDefaultsValues(bottleURL: bottle.url, key: scope.registryKey)
                let label = scope.registryKey.components(separatedBy: #"\"#).suffix(2).joined(separator: #"\"#)
                let shown = options.includeSensitiveDetails ? values : Redactor.redactLogText(values)
                section += "- **AppDefaults \(label):** \(shown)\n"
            }
        }
        // Either variable outvotes the registry. Whisky composes the bottle's
        // WINEDLLOVERRIDES itself and moves it into the registry at launch, so
        // only a game configuration's or the program's own counts there.
        let sources: [(name: String, environment: [String: String])] = [
            ("program settings", rockstarLauncherProgramEnvironment(bottleURL: bottle.url)),
            ("game configuration", bottle.settings.gameConfigEnvironment(forExecutable: "Launcher.exe")),
            ("bottle", Wine.constructWineEnvironment(for: bottle).filter { $0.key == "WINE_D3D_CONFIG" })
        ]
        for variable in ["WINEDLLOVERRIDES", "WINE_D3D_CONFIG"] {
            let setBy = sources.filter { $0.environment[variable] != nil }.map(\.name)
            section += "- **\(variable) set for Launcher.exe:** "
            section += setBy.isEmpty ? "no\n" : "yes (\(setBy.joined(separator: ", ")))\n"
        }
        section += "\n"
        return section
    }

    /// The environment variables in the program settings of Rockstar's
    /// `Launcher.exe`, in either Program Files, which a launch of it from the
    /// Programs tab adds to its environment.
    static func rockstarLauncherProgramEnvironment(bottleURL: URL) -> [String: String] {
        let driveC = bottleURL.appending(path: "drive_c")
        var environment: [String: String] = [:]
        for programFiles in ["Program Files", "Program Files (x86)"] {
            let url = driveC.appending(path: programFiles).appending(path: "Rockstar Games/Launcher/Launcher.exe")
            let locations = Program.settingsLocations(for: url, bottleURL: bottleURL, legacyName: url.lastPathComponent)
            for settingsURL in [locations.identity, locations.legacy] {
                guard let settings = try? ProgramSettings.decodeIfPresent(from: settingsURL) else { continue }
                environment.merge(settings.environment) { current, _ in current }
                break
            }
        }
        return environment
    }

    /// What `url` holds, by Wine's marker and against the installed DXVK and,
    /// when given, Wine's own copy of the DLL for the installed engine.
    static func classifySystem32DLL(_ url: URL, dxvkFolder: URL, wineSource: URL? = nil) -> System32DLLKind {
        guard let data = FileManager.default.contents(atPath: url.path(percentEncoded: false)) else {
            return .missing
        }
        let stub = data.dropFirst(0x40)
        if VCRedistDetector.wineSignatures.contains(where: { stub.starts(with: $0) }) {
            return .builtinPlaceholder
        }
        let dxvk = dxvkFolder.appending(path: "x64").appending(path: url.lastPathComponent)
        if FileManager.default.contents(atPath: dxvk.path(percentEncoded: false)) == data {
            return .dxvkPayload
        }
        if let wineSource, Wine.isStrippedCopy(url, of: wineSource) {
            return .wineStripped
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return .nativeOther(String(digest.prefix(8)))
    }

    /// What one of the swap's recorded copies holds now, against the record
    /// and the installed DXVK.
    static func classifyRockstarCopy(_ url: URL, recorded: String, dxvkFolder: URL) -> RockstarD3DCopyKind {
        guard let hash = RockstarD3DLayoutRecord.sha256(of: url) else { return .missing }
        if hash == recorded {
            return .recorded
        }
        let payload = dxvkFolder.appending(path: "x64").appending(path: url.lastPathComponent)
        if RockstarD3DLayoutRecord.sha256(of: payload) == hash {
            return .dxvkPayload
        }
        return .changed(String(hash.prefix(8)))
    }

    /// The swap's part of the section: the setting, the layout the last
    /// launch decided and the one a launch would decide now, Wine's sources,
    /// the record against the bottle, and the consumers the scan finds.
    @MainActor
    static func rockstarSwapLines(bottle: Bottle, dxvkFolder: URL, launch: RockstarD3DLaunch) -> String {
        let runtime = launch.runtime
        let record = RockstarD3DLayoutRecord.load(from: bottle.url)
        let (inputs, scan) = Wine.rockstarLayoutInputs(
            bottle: bottle, launch: launch, dxvkFolder: dxvkFolder, record: record
        )
        var lines = ""
        let system32 = bottle.url.appending(path: "drive_c/windows/system32")
        for dll in rockstarSystem32DLLs {
            let wineSource = WineD3DSource.resolve(dll, libraryFolder: runtime.libraryFolder, store: runtime.store)
            let kind = classifySystem32DLL(
                system32.appending(path: dll), dxvkFolder: dxvkFolder, wineSource: wineSource.url
            )
            lines += "- **system32 \(dll):** \(kind.summary)\n"
        }
        lines += "- **Wine Direct3D swap setting:** \(bottle.settings.rockstarWineD3D ? "on" : "off")\n"
        lines += "- **Layout at the last launch:** \(bottle.rockstarD3DLayout?.summary ?? "no launch this session")\n"
        // A launch decides on the swap only in a bottle that is Rockstar's; in
        // any other, the next one that keeps the layout takes it back.
        let now = launch.engages(bottle)
            ? RockstarD3DLayout.resolve(inputs).summary : "teardown (Rockstar is not installed)"
        lines += "- **Layout now:** \(now)\n"
        for dll in ["d3d11.dll", "dxgi.dll"] {
            let source = WineD3DSource.resolve(dll, libraryFolder: runtime.libraryFolder, store: runtime.store)
            lines += "- **\(dll.dropLast(4)) source:** \(describe(source))\n"
        }
        lines += rockstarRecordLines(record, bottle: bottle, dxvkFolder: dxvkFolder, runtime: runtime)
        let folders = scan.copyFolders.map(\.key)
        lines += "- **Copy folders:** \(folders.isEmpty ? "none" : folders.joined(separator: ", "))\n"
        lines += "- **Unserved consumers:** \(scan.unserved.isEmpty ? "none" : scan.unserved.joined(separator: ", "))\n"
        let games = scan.dxvkPlanGames
        lines += "- **DXVK-plan games:** \(games.isEmpty ? "none" : games.joined(separator: ", "))\n"
        return lines
    }

    /// The swap record's lines, checked against the bottle and the runtime.
    static func rockstarRecordLines(
        _ record: RockstarD3DLayoutRecord?, bottle: Bottle, dxvkFolder: URL, runtime: RockstarD3DRuntime
    ) -> String {
        guard let record else {
            return RockstarD3DLayoutRecord.exists(in: bottle.url)
                ? "- **Swap record:** unreadable\n" : "- **Swap record:** none\n"
        }
        let driveC = Wine.rockstarDriveC(bottle.url)
        let installed = GPTKImporter.runtimeVersionStamp(inLibraryFolder: runtime.libraryFolder)
        let source = WineD3DSource.resolve("d3d11.dll", libraryFolder: runtime.libraryFolder, store: runtime.store)
        let currentSource = source.url.flatMap(RockstarD3DLayoutRecord.sha256(of:))
        let system32 = RockstarD3DLayoutRecord.sha256(of: driveC.appending(path: "windows/system32/d3d11.dll"))
        var lines = "- **Swap record:** version \(record.version)\n"
        let engine = record.engineStamp == installed ? "matches" : "differs (installed \(installed ?? "unknown"))"
        lines += "- **Swap record engine:** \(record.engineStamp), \(engine)\n"
        let sourceMatch = record.sourceSHA256 == currentSource ? "matches" : "differs"
        lines += "- **Swap record d3d11 source:** \(record.sourceSHA256.prefix(8)), \(sourceMatch)\n"
        if let recorded = record.system32D3D11 {
            let match = recorded == system32 ? "the current file matches" : "the current file differs"
            lines += "- **Swap record system32 d3d11:** \(recorded.prefix(8)), \(match)\n"
        } else {
            lines += "- **Swap record system32 d3d11:** not recorded (interrupted swap)\n"
        }
        for (key, hash) in record.copies.sorted(by: { $0.key < $1.key }) {
            let kind = classifyRockstarCopy(driveC.appending(path: key), recorded: hash, dxvkFolder: dxvkFolder)
            lines += "  - \(key): \(kind.summary)\n"
        }
        for key in record.createdFolders {
            let state = Wine.rockstarIsDirectory(driveC.appending(path: key)) ? "exists" : "gone"
            lines += "- **Swap record created folder:** \(key) (\(state))\n"
        }
        return lines
    }

    /// Where a Wine source points, by the last folders of its path, or why there is none.
    private static func describe(_ source: WineD3DSource) -> String {
        switch source {
        case let .libWine(url):
            "lib/wine (\(url.pathComponents.suffix(2).joined(separator: "/")))"
        case let .originals(url):
            "GPTK originals (\(url.pathComponents.suffix(2).joined(separator: "/")))"
        case let .unavailable(reason):
            "unavailable: \(reason.description)"
        }
    }

    /// The values under `key`, as `name=data` pairs sorted by name, or `none`.
    static func appDefaultsValues(bottleURL: URL, key: String) -> String {
        let values = WineRegistryFile.rawValues(bottleURL: bottleURL, key: key) ?? [:]
        guard !values.isEmpty else { return "none" }
        return values.keys.sorted { $0.lowercased() < $1.lowercased() }
            .map { "\($0)=\(values[$0] ?? "")" }
            .joined(separator: ", ")
    }
}
