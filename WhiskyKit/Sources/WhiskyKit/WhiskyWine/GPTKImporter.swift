//
//  GPTKImporter.swift
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

/// Errors thrown while importing or deploying a GPTK payload.
public enum GPTKImportError: LocalizedError, Equatable {
    /// No `redist/lib`-shaped payload was found under the given location.
    case payloadNotFound
    /// The payload is missing required files (names are payload-relative paths).
    case payloadIncomplete(missing: [String])
    /// A forwarder DLL is not the winebuild builtin variant Apple ships — the
    /// source is not a real GPTK payload (or is damaged).
    case forwarderNotBuiltin(String)
    /// The D3DMetal framework's version could not be read.
    case versionUnreadable
    /// No imported payload exists in the store to deploy or remove.
    case storeEmpty

    public var errorDescription: String? {
        switch self {
        case .payloadNotFound:
            String(localized: "gptk.error.payloadNotFound")
        case let .payloadIncomplete(missing):
            String(localized: "gptk.error.payloadIncomplete") + " " + missing.joined(separator: ", ")
        case let .forwarderNotBuiltin(name):
            String(localized: "gptk.error.forwarderNotBuiltin") + " " + name
        case .versionUnreadable:
            String(localized: "gptk.error.versionUnreadable")
        case .storeEmpty:
            String(localized: "gptk.error.storeEmpty")
        }
    }
}

/// A located and validated GPTK payload (Apple's `redist/lib` layout).
public struct GPTKPayload: Equatable, Sendable {
    /// The folder containing `external/` and `wine/`.
    public let libRoot: URL
    /// The D3DMetal framework version, e.g. `"4.0b2"`.
    public let version: String
}

/// What the store holds after a successful import.
public struct GPTKStoreRecord: Codable, Equatable, Sendable {
    /// The imported D3DMetal framework version, e.g. `"4.0b2"`.
    public let gptkVersion: String
    /// When the payload was imported.
    public let importedAt: Date
}

/// Imports Apple's Game Porting Toolkit evaluation environment so the
/// D3DMetal backend can become real.
///
/// The user supplies the payload (nothing of Apple's is redistributed): the
/// evaluation-environment disk image's `redist/lib` tree, containing
/// `external/` (D3DMetal.framework + `libd3dshared.dylib`), six builtin-marked
/// PE forwarder DLLs, and six unix-side names that all resolve to
/// `libd3dshared.dylib`.
///
/// Importing copies the payload verbatim into a pristine store (`D3DMetal/`,
/// a sibling of `Libraries/`), surviving runtime reinstalls. Deployment, placing
/// the payload into the Wine tree the way Apple documents, is a separate,
/// gated step: the payload's DLLs are C++ with exception handling, and a Wine
/// build without personality-routine support for builtin modules kills every
/// process that runs D3DMetal code. Only runtimes that advertise
/// `gptkCapable` in their version plist get the payload deployed.
public enum GPTKImporter {
    static let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "GPTKImporter")

    /// The D3D forwarders Apple ships, and the only ones deployed. GPTK 4 has
    /// no d3d9 forwarder.
    static let forwarderDLLNames = ["d3d10.dll", "d3d11.dll", "d3d12.dll", "dxgi.dll"]

    /// Apple's NVIDIA bridges. `nvngx-on-metalfx` is deployed, under its export
    /// name, because it is the only route to MetalFX, see
    /// ``installMetalFXBridge(intoLibraryFolder:usingStore:)``.
    ///
    /// `nvapi64` is deployed too, and kept away from launcher helpers per
    /// executable rather than withheld from everything. Chromium probes for an
    /// NVIDIA GPU and answering makes it load D3DMetal, which takes Steam's
    /// helper process down, so that risk is real; withholding the DLL is just
    /// not the only way out of it, and it costs DLSS everywhere. See
    /// ``installNVAPIBridge(intoLibraryFolder:usingStore:)`` for why the DLL has
    /// to be there, and `Wine.disablingNVAPI(in:)` for the half that keeps
    /// Chromium out of it.
    static let nvidiaBridgeDLLNames = ["nvapi64.dll", "nvngx-on-metalfx.dll"]

    /// Apple's NVAPI, deployed under the name it ships as; wine's own `nvapi64`
    /// is a placeholder that exports nothing, so this replaces it.
    static let nvapiBridgeName = "nvapi64.dll"
    /// Its unix half, sharing the payload's dylib like every other bridge.
    static let nvapiBridgeUnixName = "nvapi64.so"

    /// Enough bytes to hold the winebuild marker at offset 0x40.
    static let builtinMarkerMinimumLength = 0x50

    /// The unix-side bridge names; each is a symlink to
    /// `../../external/libd3dshared.dylib`, whose `@loader_path` rpath then
    /// finds the framework beside it.
    static let unixLibraryNames = ["d3d10.so", "d3d11.so", "d3d12.so", "dxgi.so"]

    /// The symlink target for every unix bridge name, relative to
    /// `wine/x86_64-unix/`.
    static let unixLinkDestination = "../../external/libd3dshared.dylib"

    /// The pristine payload store: `D3DMetal/`, a sibling of `Libraries/`.
    ///
    /// Outside `Libraries/` because ``WhiskyWineInstaller/install(from:)``
    /// removes that whole folder before untarring, which would destroy the
    /// store and its `originals/` backups on every engine update.
    public static var storeFolder: URL {
        storeFolder(inApplicationFolder: WhiskyWineInstaller.applicationFolder)
    }

    /// Testable seam for ``storeFolder``.
    static func storeFolder(inApplicationFolder folder: URL) -> URL {
        folder.appending(path: "D3DMetal")
    }

    // MARK: - Locating

    /// Finds Apple's `lib` payload root at or under `url`.
    ///
    /// Accepts the `lib` folder itself, a `redist` folder, or a mounted
    /// evaluation-environment volume root.
    public static func locatePayload(under url: URL) -> URL? {
        let candidates = [
            url,
            url.appending(path: "lib"),
            url.appending(path: "redist").appending(path: "lib")
        ]
        return candidates.first(where: isPayloadRoot)
    }

    /// A payload root has the shared dylib and at least one forwarder in
    /// Apple's layout. Full completeness is ``validatePayload(at:)``'s job.
    static func isPayloadRoot(_ url: URL) -> Bool {
        let fileManager = FileManager.default
        let dylib = url.appending(path: "external").appending(path: "libd3dshared.dylib")
        let dxgi = url.appending(path: "wine").appending(path: "x86_64-windows").appending(path: "dxgi.dll")
        return fileManager.fileExists(atPath: dylib.path(percentEncoded: false)) &&
            fileManager.fileExists(atPath: dxgi.path(percentEncoded: false))
    }

    /// Whether `url` is readable and long enough for the marker check.
    static func canHoldBuiltinMarker(_ url: URL) -> Bool {
        let path = url.path(percentEncoded: false)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? Int
        else { return false }
        return size >= builtinMarkerMinimumLength
    }

    // MARK: - Validation

    /// Validates completeness and authenticity of the payload at `libRoot` and
    /// reads its version.
    ///
    /// - Throws: ``GPTKImportError`` when files are missing, a forwarder is not
    ///   the builtin variant, or the version is unreadable.
    public static func validatePayload(at libRoot: URL) throws -> GPTKPayload {
        let fileManager = FileManager.default
        let peDir = libRoot.appending(path: "wine").appending(path: "x86_64-windows")
        let external = libRoot.appending(path: "external")

        var missing: [String] = []
        for name in forwarderDLLNames
            where !fileManager.fileExists(atPath: peDir.appending(path: name).path(percentEncoded: false)) {
            missing.append("wine/x86_64-windows/\(name)")
        }
        for path in ["libd3dshared.dylib", "D3DMetal.framework"]
            where !fileManager.fileExists(atPath: external.appending(path: path).path(percentEncoded: false)) {
            missing.append("external/\(path)")
        }
        guard missing.isEmpty else {
            throw GPTKImportError.payloadIncomplete(missing: missing)
        }

        // Apple's forwarders are winebuild builtins; a native-marked file here
        // means this is not a GPTK payload (or a corrupted one). The inverse of
        // the DXMT gate, which requires native PEs. isNativePE fails closed to
        // false for a file too short to hold the marker, and false is the
        // passing answer here, so check the length or a 3-byte DLL validates.
        for name in forwarderDLLNames {
            let dll = peDir.appending(path: name)
            guard canHoldBuiltinMarker(dll), (try? Wine.isNativePE(dll)) == false else {
                throw GPTKImportError.forwarderNotBuiltin(name)
            }
        }

        guard let version = frameworkVersion(inExternal: external) else {
            throw GPTKImportError.versionUnreadable
        }
        return GPTKPayload(libRoot: libRoot, version: version)
    }

    /// Reads `CFBundleShortVersionString` from the framework's Info.plist,
    /// looking in the versioned bundle layout first and the flat layout second.
    static func frameworkVersion(inExternal external: URL) -> String? {
        let framework = external.appending(path: "D3DMetal.framework")
        let candidates = [
            framework.appending(path: "Versions").appending(path: "A")
                .appending(path: "Resources").appending(path: "Info.plist"),
            framework.appending(path: "Resources").appending(path: "Info.plist")
        ]
        for plist in candidates {
            guard let data = try? Data(contentsOf: plist),
                  let dict = try? PropertyListSerialization.propertyList(
                      from: data, format: nil
                  ) as? [String: Any],
                  let version = dict["CFBundleShortVersionString"] as? String,
                  !version.isEmpty
            else { continue }
            return version
        }
        return nil
    }

    // MARK: - Import

    /// Copies a validated payload into the store and records its version.
    ///
    /// Reimporting replaces the previous store contents. The six unix bridge
    /// names are recreated as symlinks regardless of what the source held: a
    /// copy pipeline that resolved them into file duplicates would break the
    /// dylib's `@loader_path` rpath, which must land in `external/` to find
    /// the framework.
    @discardableResult
    public static func importPayload(_ payload: GPTKPayload) throws -> GPTKStoreRecord {
        try importPayload(payload, intoStore: storeFolder)
    }

    /// Testable seam for ``importPayload(_:)``.
    @discardableResult
    static func importPayload(_ payload: GPTKPayload, intoStore store: URL) throws -> GPTKStoreRecord {
        let fileManager = FileManager.default
        let libDest = store.appending(path: "lib")

        try fileManager.createDirectory(at: store, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: libDest.path(percentEncoded: false)) {
            try fileManager.removeItem(at: libDest)
        }
        try fileManager.copyItem(at: payload.libRoot, to: libDest)

        let unixDir = libDest.appending(path: "wine").appending(path: "x86_64-unix")
        try fileManager.createDirectory(at: unixDir, withIntermediateDirectories: true)
        for name in unixLibraryNames {
            let link = unixDir.appending(path: name)
            try? fileManager.removeItem(at: link)
            try fileManager.createSymbolicLink(
                atPath: link.path(percentEncoded: false),
                withDestinationPath: unixLinkDestination
            )
        }

        let record = GPTKStoreRecord(gptkVersion: payload.version, importedAt: Date())
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        try encoder.encode(record).write(to: recordURL(inStore: store))
        logger.info("Imported GPTK payload \(record.gptkVersion, privacy: .public) into store")
        return record
    }

    /// The stored payload's record, or `nil` when the store is absent or its
    /// payload is incomplete.
    public static func storedRecord() -> GPTKStoreRecord? {
        storedRecord(inStore: storeFolder)
    }

    /// Testable seam for ``storedRecord()``.
    static func storedRecord(inStore store: URL) -> GPTKStoreRecord? {
        guard let data = try? Data(contentsOf: recordURL(inStore: store)),
              let record = try? PropertyListDecoder().decode(GPTKStoreRecord.self, from: data),
              isPayloadRoot(store.appending(path: "lib"))
        else { return nil }
        return record
    }

    /// Deletes the store, payload and record together.
    public static func removeStore() throws {
        let store = storeFolder
        guard FileManager.default.fileExists(atPath: store.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: store)
    }

    private static func recordURL(inStore store: URL) -> URL {
        store.appending(path: "D3DMetalVersion.plist")
    }
}
