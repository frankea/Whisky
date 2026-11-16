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
    /// Any other file, by the first eight hex digits of its SHA-256.
    case nativeOther(String)

    var summary: String {
        switch self {
        case .missing: "missing"
        case .builtinPlaceholder: "builtin placeholder"
        case .dxvkPayload: "DXVK payload"
        case let .nativeOther(digest): "native other (\(digest))"
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
    @MainActor
    static func generateRockstarLayoutSection(
        bottle: Bottle,
        options: ExportOptions,
        libraryFolder: URL = WhiskyWineInstaller.libraryFolder,
        store: URL = GPTKImporter.storeFolder,
        dxvkFolder: URL = Wine.dxvkFolder,
        payloadDeployed: Bool = GPTKImporter.isDeployed()
    ) -> String {
        guard Wine.rockstarInstalled(bottleURL: bottle.url) else { return "" }
        let layout = RockstarD3DLayout.resolve(
            payloadDeployed: payloadDeployed, libraryFolder: libraryFolder, store: store
        )
        let slots = RockstarD3DLayout.forwarders(libraryFolder: libraryFolder, store: store)

        var section = "### Rockstar Launcher Layout\n\n"
        section += "- **Layout:** \(layout.summary)\n"
        section += "- **Runtime d3d11.dll is a GPTK forwarder:** \(slots.d3d11 ? "yes" : "no")\n"
        section += "- **Runtime dxgi.dll is a GPTK forwarder:** \(slots.dxgi ? "yes" : "no")\n"
        let system32 = bottle.url.appending(path: "drive_c/windows/system32")
        for dll in rockstarSystem32DLLs {
            let kind = classifySystem32DLL(system32.appending(path: dll), dxvkFolder: dxvkFolder)
            section += "- **system32 \(dll):** \(kind.summary)\n"
        }
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
        // only a game configuration's counts there.
        let gameConfig = bottle.settings.gameConfigEnvironment(forExecutable: "Launcher.exe")
        let d3dConfig = gameConfig["WINE_D3D_CONFIG"] ?? Wine.constructWineEnvironment(for: bottle)["WINE_D3D_CONFIG"]
        section += "- **WINEDLLOVERRIDES set for Launcher.exe:** "
        section += gameConfig["WINEDLLOVERRIDES"] == nil ? "no\n" : "yes (game configuration)\n"
        section += "- **WINE_D3D_CONFIG set for Launcher.exe:** \(d3dConfig == nil ? "no" : "yes")\n"
        section += "\n"
        return section
    }

    /// What `url` holds, by Wine's marker and against the installed DXVK.
    static func classifySystem32DLL(_ url: URL, dxvkFolder: URL) -> System32DLLKind {
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
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return .nativeOther(String(digest.prefix(8)))
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
