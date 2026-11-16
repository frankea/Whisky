//
//  WineD3DSource.swift
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

/// Where Wine's own 64-bit copy of a Direct3D DLL can be read from right now.
///
/// Wine ships its own `d3d10core`, `d3d11` and `dxgi` (wined3d) as builtins in
/// `lib/wine/x86_64-windows`. Importing GPTK replaces the `d3d11` and `dxgi`
/// builtins there with Apple's D3DMetal forwarders (the `dxgi` slot may hold
/// the driver-version interposer in front of Apple's DLL instead) and moves
/// Wine's copies into the store's `originals/` folder. Anything that needs
/// Wine's own implementation, such as a clean `dxgi.dll` beside DXVK's `d3d11`,
/// has to know which of the two places holds it.
///
/// The store outlives the engine, so `originals/` can hold DLLs from an engine
/// that is no longer installed. Those are never returned: a Wine 10 `dxgi`
/// placed next to a Wine 11 `d3d11` breaks in ways that only show at runtime.
/// When the current engine's copy cannot be found, the answer is
/// ``unavailable(_:)`` and callers leave the prefix as it is.
///
/// Only the 64-bit tree is resolved: GPTK forwards nothing in
/// `i386-windows`, so the 32-bit builtins are always Wine's own.
enum WineD3DSource: Equatable, Sendable {
    /// Wine's copy is the builtin in the runtime's `lib/wine/x86_64-windows`.
    case libWine(URL)
    /// Wine's copy was moved into the GPTK store's `originals/` folder by a
    /// deploy against the engine that is installed now.
    case originals(URL)
    /// Wine's copy cannot be located safely.
    case unavailable(Reason)

    /// Why no source could be resolved.
    enum Reason: Equatable, Sendable {
        /// The file the rules point at does not exist.
        case missingFile
        /// `originals/` was stamped for a different engine than the one
        /// installed, or one of the two version records cannot be read.
        case staleOriginals(found: String?, expected: String?)
        /// The file does not carry winebuild's builtin marker, so it is not
        /// Wine's own build of the DLL: a native PE someone put there, or a
        /// file too short to be a DLL at all.
        case notBuiltinMarked
        /// The runtime holds a GPTK payload copied in by hand rather than
        /// deployed from the store, and the store holds no current backup to
        /// fall back on. Its `lib/wine` slots are Apple's, not Wine's.
        case handPlacedPayload
        /// The DLL is not one this resolver knows how to place.
        case unsupportedDLL(String)
    }

    /// The resolved file, or `nil` when the source is ``unavailable(_:)``.
    var url: URL? {
        switch self {
        case let .libWine(url), let .originals(url):
            url
        case .unavailable:
            nil
        }
    }

    /// The DLLs whose `lib/wine` slot a GPTK deploy takes over.
    private static let gptkReplacedDLLs: Set<String> = ["d3d11.dll", "dxgi.dll"]

    /// The DLLs GPTK never replaces, so `lib/wine` always holds Wine's own.
    private static let wineOnlyDLLs: Set<String> = ["d3d10core.dll"]

    /// Resolves where Wine's own copy of `dllName` lives for the installed
    /// engine.
    ///
    /// - `d3d10core` always comes from `lib/wine`: GPTK ships no replacement.
    /// - `d3d11` and `dxgi` come from `lib/wine` while that slot still holds
    ///   Wine's builtin. A missing slot there is reported as missing, not
    ///   looked for elsewhere: with no payload in the tree, `originals/` has
    ///   no business holding Wine's copy.
    /// - They come from `originals/` instead, and only when its stamp names
    ///   the engine that is installed now, once the slot is GPTK's: a payload
    ///   is deployed, the slot byte-matches the store's forwarder (as it does
    ///   part way through a deploy), or the slot holds a builtin-marked DLL
    ///   that does not import `wined3d.dll` (see ``importsWined3d(_:)``).
    /// - Whatever is returned carries winebuild's builtin marker. That rules
    ///   out a native DLL that happens to sit at the expected path, but not
    ///   Apple's forwarders: winebuild built those too, so they carry the
    ///   same marker. Telling them from Wine's own `d3d11` and `dxgi` is the
    ///   `wined3d.dll` import's job, which is why a slot that lacks it never
    ///   resolves to ``libWine(_:)``.
    ///
    /// - Parameters:
    ///   - dllName: The DLL's file name, `"dxgi.dll"` or `"dxgi"`. Case is
    ///     ignored.
    ///   - libraryFolder: The runtime's `Libraries` folder.
    ///   - store: The GPTK store folder.
    /// - Returns: The source, or ``unavailable(_:)`` with the reason.
    static func resolve(
        _ dllName: String,
        libraryFolder: URL = WhiskyWineInstaller.libraryFolder,
        store: URL = GPTKImporter.storeFolder
    ) -> WineD3DSource {
        var name = dllName.lowercased()
        if !name.hasSuffix(".dll") {
            name += ".dll"
        }
        let libWine = libraryFolder.appending(path: "Wine").appending(path: "lib")
            .appending(path: "wine").appending(path: "x86_64-windows").appending(path: name)

        if wineOnlyDLLs.contains(name) {
            return checked(.libWine(libWine))
        }
        guard gptkReplacedDLLs.contains(name) else {
            return .unavailable(.unsupportedDLL(name))
        }

        let payloadDeployed = GPTKImporter.isDeployed(inLibraryFolder: libraryFolder)
        let slotIsStoreForwarder = GPTKImporter.isGPTKForwarder(libWine, matching: store.appending(path: "lib"))
        if !payloadDeployed, !slotIsStoreForwarder {
            let fromLibWine = checked(.libWine(libWine))
            guard case .libWine = fromLibWine else {
                return fromLibWine
            }
            if importsWined3d(libWine) {
                return fromLibWine
            }
            // A builtin-marked slot that is not wined3d's build is Apple's
            // forwarder outliving its payload: a removal that found only
            // stale backups leaves the forwarders and deletes the bridges, and
            // a later import of another GPTK build stops them byte-matching
            // the store. Wine's copy, if anywhere, is in originals/.
        }

        let fromOriginals = resolveOriginal(name, libraryFolder: libraryFolder, store: store)
        if case .unavailable = fromOriginals,
           GPTKImporter.holdsHandPlacedPayload(inLibraryFolder: libraryFolder, usingStore: store) {
            return .unavailable(.handPlacedPayload)
        }
        return fromOriginals
    }

    /// The store's backup of `name`, provided `originals/` was stamped for the
    /// engine under `libraryFolder`. The stamp is the same record a deploy
    /// writes before its first backup and a removal checks before restoring.
    private static func resolveOriginal(_ name: String, libraryFolder: URL, store: URL) -> WineD3DSource {
        let original = store.appending(path: "originals").appending(path: name)
        guard exists(original) else {
            return .unavailable(.missingFile)
        }
        let found = GPTKImporter.originalsRecord(inStore: store)?.runtimeVersion
        let expected = GPTKImporter.runtimeVersionStamp(inLibraryFolder: libraryFolder)
        guard let found, let expected, found == expected else {
            return .unavailable(.staleOriginals(found: found, expected: expected))
        }
        return checked(.originals(original))
    }

    /// Passes `source` through only when its file exists and carries the
    /// builtin marker.
    private static func checked(_ source: WineD3DSource) -> WineD3DSource {
        guard let url = source.url else {
            return source
        }
        guard exists(url) else {
            return .unavailable(.missingFile)
        }
        guard Wine.carriesBuiltinMarker(url) else {
            return .unavailable(.notBuiltinMarked)
        }
        return source
    }

    /// Whether the DLL at `url` imports `wined3d.dll`, which Wine's own
    /// `d3d11` and `dxgi` always do: both are thin layers over wined3d.
    /// Apple's forwarders hand everything to D3DMetal's unix side and never
    /// name it, though they carry the same builtin marker. The DLL name sits
    /// in the import directory as plain ASCII, so a byte search finds it
    /// without parsing the PE. `d3d10core` imports `d3d11`, not wined3d,
    /// which is one reason this is only asked of the GPTK-replaced slots.
    static func importsWined3d(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return false }
        return data.range(of: wined3dImportName) != nil
    }

    /// The import name winebuild writes for wined3d, lower case as Wine's
    /// makefiles spell it.
    private static let wined3dImportName = Data("wined3d.dll".utf8)

    private static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }
}

extension WineD3DSource.Reason: CustomStringConvertible {
    /// A log-friendly sentence, without Swift's `Optional(...)` wrapping.
    var description: String {
        switch self {
        case .missingFile:
            "the file is missing"
        case let .staleOriginals(found, expected):
            "originals are stamped for \(found ?? "no engine"), the installed engine is \(expected ?? "unknown")"
        case .notBuiltinMarked:
            "the file does not carry the Wine builtin marker"
        case .handPlacedPayload:
            "a hand-placed GPTK payload with no current backup"
        case let .unsupportedDLL(name):
            "\(name) is not resolved"
        }
    }
}
