//
//  GPTKImporter+Deployment.swift
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

/// Which runtime the backed-up Wine originals were taken from. The store now
/// outlives the runtime, so a backup can outlive the engine it came from, and
/// restoring a Wine 10 builtin into a Wine 11 tree breaks it silently.
struct GPTKOriginalsRecord: Codable, Equatable, Sendable {
    let runtimeVersion: String
}

/// Runtime capability gating and deployment of the stored payload into the
/// Wine tree (Apple's documented layout).
extension GPTKImporter {
    // MARK: - Runtime capability

    /// Whether the installed runtime's Wine build can execute GPTK payloads.
    ///
    /// Advertised by `gptkCapable` in the runtime's version plist; absent means
    /// no. This is a build property (exception-unwind support), not something
    /// the payload or the app can add.
    public static func isRuntimeGPTKCapable() -> Bool {
        WhiskyWineInstaller.whiskyWineInfo()?.gptkCapable == true
    }

    // MARK: - Deployment

    /// Whether the payload is deployed into the runtime tree.
    public static func isDeployed() -> Bool {
        isDeployed(inLibraryFolder: WhiskyWineInstaller.libraryFolder)
    }

    /// Testable seam for ``isDeployed()``: the unix bridge for dxgi and the
    /// shared dylib both present in the Wine tree.
    static func isDeployed(inLibraryFolder folder: URL) -> Bool {
        let lib = folder.appending(path: "Wine").appending(path: "lib")
        let bridge = lib.appending(path: "wine").appending(path: "x86_64-unix").appending(path: "dxgi.so")
        let dylib = lib.appending(path: "external").appending(path: "libd3dshared.dylib")
        let fileManager = FileManager.default
        return fileManager.fileExists(atPath: bridge.path(percentEncoded: false)) &&
            fileManager.fileExists(atPath: dylib.path(percentEncoded: false))
    }

    /// Deploys the stored payload into the runtime tree per Apple's documented
    /// layout: forwarders replace the Wine builtins (originals are backed up in
    /// the store), the unix bridges and `external/` are added alongside.
    ///
    /// Callers gate this on ``isRuntimeGPTKCapable()`` — deploying to an
    /// incapable runtime turns every D3DMetal launch into a crash.
    public static func deployStoredPayload() throws {
        try deploy(fromStore: storeFolder, intoLibraryFolder: WhiskyWineInstaller.libraryFolder)
    }

    /// Deploys the stored payload if there is one and the runtime can execute
    /// it, reporting whether it deployed.
    ///
    /// The store survives a runtime install but the deployed copy does not, so
    /// every install has to re-evaluate. Idempotent and safe to call anywhere.
    @discardableResult
    public static func deployStoredPayloadIfCapable() -> Bool {
        guard storedRecord() != nil, isRuntimeGPTKCapable() else { return false }
        do {
            try deployStoredPayload()
            return true
        } catch {
            logger.error("Deploying the stored GPTK payload failed: \(error.localizedDescription)")
            return false
        }
    }

    /// The runtime version under `folder`, or `nil` if none is readable.
    static func runtimeVersionStamp(inLibraryFolder folder: URL) -> String? {
        let plist = folder.appending(path: "WhiskyWineVersion").appendingPathExtension("plist")
        guard let info = WhiskyWineInstaller.whiskyWineInfo(at: plist) else { return nil }
        return "\(info.version.major).\(info.version.minor).\(info.version.patch)"
    }

    static func originalsRecordURL(inStore store: URL) -> URL {
        store.appending(path: "originals").appending(path: "OriginalsVersion.plist")
    }

    static func originalsRecord(inStore store: URL) -> GPTKOriginalsRecord? {
        guard let data = try? Data(contentsOf: originalsRecordURL(inStore: store)) else { return nil }
        return try? PropertyListDecoder().decode(GPTKOriginalsRecord.self, from: data)
    }

    /// Readies the `originals/` folder for a deploy against `folder`, dropping
    /// backups left by a previous engine: restoring those would put that
    /// engine's DLLs into this one's tree. The stamp is written before the first
    /// backup so an interrupted deploy still leaves originals remove will
    /// recognise and restore.
    private static func prepareOriginals(inStore store: URL, forLibraryFolder folder: URL) throws {
        let fileManager = FileManager.default
        let originals = store.appending(path: "originals")
        let runtimeStamp = runtimeVersionStamp(inLibraryFolder: folder)

        if originalsRecord(inStore: store)?.runtimeVersion != runtimeStamp {
            try? fileManager.removeItem(at: originals)
        }
        try fileManager.createDirectory(at: originals, withIntermediateDirectories: true)

        guard let runtimeStamp else { return }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        try encoder.encode(GPTKOriginalsRecord(runtimeVersion: runtimeStamp))
            .write(to: originalsRecordURL(inStore: store))
    }

    /// Testable seam for ``deployStoredPayload()``.
    static func deploy(fromStore store: URL, intoLibraryFolder folder: URL) throws {
        guard storedRecord(inStore: store) != nil else {
            throw GPTKImportError.storeEmpty
        }
        let fileManager = FileManager.default
        let storeLib = store.appending(path: "lib")
        let wineLib = folder.appending(path: "Wine").appending(path: "lib")
        let peDir = wineLib.appending(path: "wine").appending(path: "x86_64-windows")
        let unixDir = wineLib.appending(path: "wine").appending(path: "x86_64-unix")
        let originals = store.appending(path: "originals")
        try prepareOriginals(inStore: store, forLibraryFolder: folder)

        for name in forwarderDLLNames {
            let target = peDir.appending(path: name)
            let backup = originals.appending(path: name)
            // Back up whatever Wine shipped, once; a redeploy over an existing
            // GPTK forwarder must not overwrite the original with Apple's copy.
            if fileManager.fileExists(atPath: target.path(percentEncoded: false)) {
                if !fileManager.fileExists(atPath: backup.path(percentEncoded: false)),
                   !isGPTKForwarder(target, matching: storeLib) {
                    try fileManager.moveItem(at: target, to: backup)
                } else {
                    try fileManager.removeItem(at: target)
                }
            }
            try fileManager.copyItem(
                at: storeLib.appending(path: "wine").appending(path: "x86_64-windows").appending(path: name),
                to: target
            )
        }

        try fileManager.createDirectory(at: unixDir, withIntermediateDirectories: true)
        for name in unixLibraryNames {
            let link = unixDir.appending(path: name)
            try? fileManager.removeItem(at: link)
            try fileManager.createSymbolicLink(
                atPath: link.path(percentEncoded: false),
                withDestinationPath: unixLinkDestination
            )
        }

        let externalDest = wineLib.appending(path: "external")
        if fileManager.fileExists(atPath: externalDest.path(percentEncoded: false)) {
            try fileManager.removeItem(at: externalDest)
        }
        try fileManager.copyItem(at: storeLib.appending(path: "external"), to: externalDest)
        // Apple's payload is in place now, which is the only moment the bridge
        // can be installed: it forwards into the payload's own shared dylib and
        // has nothing to bind to before this point.
        try installMetalFXBridge(intoLibraryFolder: folder, usingStore: store)
        logger.info("Deployed GPTK payload into the runtime tree")
    }

    /// Whether `dll` is byte-identical to the store's forwarder of the same
    /// name, so deploy never mistakes an already-deployed Apple DLL for a Wine
    /// original worth backing up and remove only deletes what it put there.
    private static func isGPTKForwarder(_ dll: URL, matching storeLib: URL) -> Bool {
        let storeDLL = storeLib.appending(path: "wine").appending(path: "x86_64-windows")
            .appending(path: dll.lastPathComponent)
        return FileManager.default.contentsEqual(
            atPath: dll.path(percentEncoded: false),
            andPath: storeDLL.path(percentEncoded: false)
        )
    }

    /// Removes the payload from the runtime tree and restores the backed-up
    /// Wine originals.
    public static func removeDeployedPayload() throws {
        try remove(fromLibraryFolder: WhiskyWineInstaller.libraryFolder, usingStore: storeFolder)
    }

    /// Testable seam for ``removeDeployedPayload()``.
    static func remove(fromLibraryFolder folder: URL, usingStore store: URL) throws {
        let fileManager = FileManager.default
        let wineLib = folder.appending(path: "Wine").appending(path: "lib")
        let peDir = wineLib.appending(path: "wine").appending(path: "x86_64-windows")
        let unixDir = wineLib.appending(path: "wine").appending(path: "x86_64-unix")
        let originals = store.appending(path: "originals")
        let storeLib = store.appending(path: "lib")

        let originalsAreCurrent = originalsRecord(inStore: store)?.runtimeVersion
            == runtimeVersionStamp(inLibraryFolder: folder)

        removeMetalFXBridge(fromLibraryFolder: folder, usingStore: store)

        for name in forwarderDLLNames {
            let backup = originals.appending(path: name)
            let hasBackup = fileManager.fileExists(atPath: backup.path(percentEncoded: false))

            // Backups from a replaced engine: drop them and leave the tree,
            // which this store never deployed into, untouched.
            guard originalsAreCurrent else {
                if hasBackup { try fileManager.removeItem(at: backup) }
                continue
            }

            // An interrupted deploy leaves some names still holding Wine's own
            // DLL, never backed up; deleting one loses a builtin with nothing
            // to put back. Only what byte-matches the store came from here.
            let deployed = peDir.appending(path: name)
            if fileManager.fileExists(atPath: deployed.path(percentEncoded: false)) {
                guard isGPTKForwarder(deployed, matching: storeLib) else { continue }
                try fileManager.removeItem(at: deployed)
            }
            if hasBackup {
                try fileManager.moveItem(at: backup, to: deployed)
            }
        }

        // removeItem operates on the link itself, so this also clears a
        // dangling symlink that fileExists (which follows links) would miss.
        for name in unixLibraryNames {
            try? fileManager.removeItem(at: unixDir.appending(path: name))
        }

        let external = wineLib.appending(path: "external")
        if fileManager.fileExists(atPath: external.path(percentEncoded: false)) {
            try fileManager.removeItem(at: external)
        }
        logger.info("Removed GPTK payload from the runtime tree")
    }
}
