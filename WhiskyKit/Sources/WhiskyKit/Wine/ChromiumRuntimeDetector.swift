//
//  ChromiumRuntimeDetector.swift
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

/// The Chromium runtime an app is built on, when its files say so.
public enum ChromiumRuntimeKind: String, Sendable, Equatable {
    /// An Electron app: the RSI Launcher's layout, Discord's, and RPG Maker MZ
    /// games packaged with Electron.
    case electron
    /// An NW.js app, the runtime RPG Maker MV and MZ games ship with.
    case nwjs

    /// The runtime's name, as shown in the UI. Not localized.
    public var displayName: String {
        switch self {
        case .electron:
            "Electron"
        case .nwjs:
            "NW.js"
        }
    }
}

/// Finds Electron and NW.js executables by their files and imports (#372).
///
/// Every window such an executable opens is drawn by Chromium, games built on
/// it included, so DXVK is right for all of them and a false match costs
/// nothing. CEF is not matched: a game can ship CEF for an overlay, and DXVK
/// has no Direct3D 12 on macOS, so CEF only gets a suggestion
/// (``suggestsCEF(for:)``).
///
/// An executable `E` in folder `F` is an Electron app when `F` holds
/// `resources/app.asar` (or `resources/app/package.json`), `icudtl.dat`, and
/// `v8_context_snapshot.bin` or `snapshot_blob.bin`, and `E` imports
/// `ffmpeg.dll`. Electron 45 delay-loads it, so both import tables count. It
/// is an NW.js app when `F` holds `nw.dll` and `icudtl.dat` and `E` imports
/// `nw.dll` or `nw_elf.dll`. Either way `E` must not import a graphics DLL
/// normally: Chromium delay-loads Direct3D, so a normal import means `E` is
/// something else. Siblings such as `Uninstall X.exe` and `elevate.exe` do not
/// import `ffmpeg.dll`, so they are not matched.
///
/// Results are cached for the process, keyed on the executable's path, size
/// and modification date and its folder's modification date, so an update
/// reclassifies it. A miss whose deciding files sit a folder down is not
/// cached (``Outcome/isFinal``).
public enum ChromiumRuntimeDetector {
    /// Folders with more entries are not read: a Downloads or Desktop folder.
    public static let maxFolderEntries = 2_000

    /// DLLs whose normal import means the executable draws with a graphics API itself.
    static let graphicsImports: Set<String> = [
        "d3d9.dll", "d3d11.dll", "d3d12.dll", "dxgi.dll", "vulkan-1.dll", "opengl32.dll"
    ]

    /// The runtime steering for an executable the launcher list and the
    /// front-end table do not know, read from disk the first time and cached.
    ///
    /// Not for a view body: a first look lists the executable's folder and
    /// reads its import tables. ``DXVKSteering/inspect(executable:)`` puts the
    /// launcher list and the table first.
    ///
    /// - Parameter url: The executable.
    /// - Returns: `.chromiumRuntime` with the file that identified it, or `nil`.
    public static func detect(executable url: URL) -> DXVKSteering? {
        guard DXVKSteering.detect(executable: url) == nil, !isUnderWindowsFolder(url),
              let key = CacheKey(url)
        else { return nil }
        if let cached = cache.result(for: key) {
            return cached
        }
        let outcome = evaluate(executable: url)
        if outcome.isFinal {
            cache.store(outcome.steering, for: key)
        }
        return outcome.steering
    }

    /// Whether to offer DXVK for a program that ships CEF: `libcef.dll` sits
    /// beside it, it imports `libcef.dll` itself, and it imports no graphics
    /// DLL normally. Only feeds a suggestion; nothing is steered by it.
    public static func suggestsCEF(for url: URL) -> Bool {
        guard ChromiumFrontEnd.shipsCEF(beside: url), let imports = imports(of: url) else { return false }
        return imports.allImports.contains("libcef.dll") && drawsOnlyThroughChromium(imports)
    }

    // MARK: - Rule

    /// The rule itself, uncached.
    ///
    /// - Parameters:
    ///   - url: The executable.
    ///   - followSquirrel: Whether a Squirrel stub (`Update.exe` beside it,
    ///     the app in an `app-x.y.z` folder) is classified by the app it starts,
    ///     which runs under the same name and so reads the same entry.
    static func classify(executable url: URL, followSquirrel: Bool = true) -> DXVKSteering? {
        evaluate(executable: url, followSquirrel: followSquirrel).steering
    }

    /// A result of the rule, and whether the cache can keep it.
    struct Outcome: Equatable {
        var steering: DXVKSteering?
        /// Whether no file can change the result without changing the
        /// ``CacheKey``. A match is final. A miss is not when the files that
        /// decide it are a folder down, where the executable's folder keeps
        /// its date: the app's code in `resources` beside Chromium's ICU data,
        /// or a Squirrel app in its `app-x.y.z` folder. An install that is
        /// still extracting then gets another look on the next scan.
        var isFinal: Bool
    }

    /// ``classify(executable:followSquirrel:)``, with whether its result can be cached.
    static func evaluate(executable url: URL, followSquirrel: Bool = true) -> Outcome {
        let folder = url.deletingLastPathComponent()
        guard let names = entryNames(in: folder) else { return Outcome(steering: nil, isFinal: true) }
        let appCodeIsAFolderDown = names["icudtl.dat"] != nil && names["resources"] != nil
        let missIsFinal = !appCodeIsAFolderDown && names["update.exe"] == nil
        var imports: PEFile.ImportTable??
        func readImports() -> PEFile.ImportTable? {
            if let imports { return imports }
            let read = Self.imports(of: url)
            imports = .some(read)
            return read
        }

        if let marker = electronMarker(in: folder, names: names), let table = readImports(),
           drawsOnlyThroughChromium(table), table.allImports.contains("ffmpeg.dll") {
            return Outcome(steering: .chromiumRuntime(kind: .electron, evidence: marker), isFinal: true)
        }
        if let marker = nwjsMarker(names: names), let table = readImports(), drawsOnlyThroughChromium(table),
           !table.allImports.isDisjoint(with: ["nw.dll", "nw_elf.dll"]) {
            return Outcome(steering: .chromiumRuntime(kind: .nwjs, evidence: marker), isFinal: true)
        }
        let miss = Outcome(steering: nil, isFinal: missIsFinal)
        guard followSquirrel, let app = squirrelApp(for: url, names: names) else { return miss }
        guard case let .chromiumRuntime(kind, evidence)? = classify(executable: app, followSquirrel: false)
        else { return miss }
        let appFolder = app.deletingLastPathComponent().lastPathComponent
        return Outcome(steering: .chromiumRuntime(kind: kind, evidence: "\(appFolder)/\(evidence)"), isFinal: true)
    }

    /// No graphics DLL among the normal imports. The delay-load table is not
    /// read here: Chromium delay-loads `d3d11.dll`, `d3d12.dll` and `dxgi.dll`.
    static func drawsOnlyThroughChromium(_ imports: PEFile.ImportTable) -> Bool {
        imports.normalImports.isDisjoint(with: graphicsImports)
    }

    /// The Electron app's code, `resources/app.asar` or
    /// `resources/app/package.json`, when the folder also holds Chromium's
    /// ICU data and V8 snapshot.
    private static func electronMarker(in folder: URL, names: [String: String]) -> String? {
        guard names["icudtl.dat"] != nil,
              names["v8_context_snapshot.bin"] != nil || names["snapshot_blob.bin"] != nil,
              let resources = names["resources"]
        else { return nil }
        let fileManager = FileManager.default
        for relative in ["app.asar", "app/package.json"] {
            let path = folder.appending(path: resources).appending(path: relative).path(percentEncoded: false)
            if fileManager.fileExists(atPath: path) {
                return "\(resources)/\(relative)"
            }
        }
        return nil
    }

    /// `nw.dll`, when the folder also holds Chromium's ICU data.
    private static func nwjsMarker(names: [String: String]) -> String? {
        guard names["icudtl.dat"] != nil else { return nil }
        return names["nw.dll"]
    }

    /// The app a Squirrel stub starts: the newest `app-x.y.z` folder beside
    /// `Update.exe` that holds an executable of the stub's name.
    private static func squirrelApp(for url: URL, names: [String: String]) -> URL? {
        guard names["update.exe"] != nil else { return nil }
        let folder = url.deletingLastPathComponent()
        let fileManager = FileManager.default
        return names
            .filter { $0.key.hasPrefix("app-") }
            .map(\.value)
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            .lazy
            .map { folder.appending(path: $0).appending(path: url.lastPathComponent) }
            .first { fileManager.fileExists(atPath: $0.path(percentEncoded: false)) }
    }

    /// The folder's entries, keyed by their lowercased names, as Windows
    /// compares them; `nil` when it cannot be read or has more than
    /// ``maxFolderEntries``.
    private static func entryNames(in folder: URL) -> [String: String]? {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)),
              entries.count <= maxFolderEntries
        else { return nil }
        return Dictionary(entries.map { ($0.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
    }

    private static func imports(of url: URL) -> PEFile.ImportTable? {
        (try? PEFile(url: url))?.importTable()
    }

    /// Whether the executable is part of Windows itself, under `drive_c/windows`.
    static func isUnderWindowsFolder(_ url: URL) -> Bool {
        let components = url.standardizedFileURL.pathComponents.map { $0.lowercased() }
        return zip(components, components.dropFirst()).contains { $0 == "drive_c" && $1 == "windows" }
    }

    // MARK: - Cache

    private static let cache = ResultCache()

    /// What a cached result was computed from.
    struct CacheKey: Hashable {
        let path: String
        let size: UInt64
        let modified: Date
        let folderModified: Date?

        init?(_ url: URL) {
            let fileManager = FileManager.default
            let path = url.standardizedFileURL.path(percentEncoded: false)
            guard let attributes = try? fileManager.attributesOfItem(atPath: path),
                  attributes[.type] as? FileAttributeType == .typeRegular,
                  let size = attributes[.size] as? NSNumber,
                  let modified = attributes[.modificationDate] as? Date
            else { return nil }
            self.path = path
            self.size = size.uint64Value
            self.modified = modified
            self.folderModified = (try? fileManager.attributesOfItem(
                atPath: url.standardizedFileURL.deletingLastPathComponent().path(percentEncoded: false)
            ))?[.modificationDate] as? Date
        }
    }

    /// The last result per executable, valid while its key matches.
    private final class ResultCache: @unchecked Sendable {
        /// Entries kept before the cache starts over.
        private static let capacity = 4_096
        private let lock = NSLock()
        private var entries: [String: (key: CacheKey, result: DXVKSteering?)] = [:]

        /// The cached result: `.some(nil)` for an executable known not to match.
        func result(for key: CacheKey) -> DXVKSteering?? {
            lock.lock()
            defer { lock.unlock() }
            guard let entry = entries[key.path], entry.key == key else { return nil }
            return .some(entry.result)
        }

        func store(_ result: DXVKSteering?, for key: CacheKey) {
            lock.lock()
            defer { lock.unlock() }
            if entries.count >= Self.capacity, entries[key.path] == nil {
                entries.removeAll(keepingCapacity: true)
            }
            entries[key.path] = (key, result)
        }
    }
}

public extension DXVKSteering {
    /// The steering for an executable, reading its files when the name alone
    /// does not decide: a launcher first, then the front-end table, then an
    /// Electron or NW.js app (``ChromiumRuntimeDetector``).
    ///
    /// Not for a view body, which reads ``Program/dxvkSteering`` instead: a
    /// first look at an unknown executable lists its folder.
    static func inspect(executable url: URL) -> DXVKSteering? {
        detect(executable: url) ?? ChromiumRuntimeDetector.detect(executable: url)
    }
}
