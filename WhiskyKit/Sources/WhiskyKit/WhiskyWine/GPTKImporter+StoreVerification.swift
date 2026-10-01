//
//  GPTKImporter+StoreVerification.swift
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

/// The outcome of checking the stored payload, kept in the store beside it
/// with a fingerprint of the store contents that were checked.
struct GPTKStoreStamp: Codable, Equatable, Sendable {
    /// ``GPTKImporter/storeFingerprint(inStore:)`` when the check ran.
    let fingerprint: String
    /// Why the check failed, or `nil` when it passed.
    let failure: String?
}

/// Whether the stored payload passes the checks an import applies.
public enum GPTKStoreVerdict: Equatable, Sendable {
    case verified
    case failed(reason: String)
}

/// Checks a stored payload that no import has vouched for.
///
/// Imports validate the staged copy before it becomes the store, but stores
/// imported before those checks existed were never looked at, and a deploy
/// copies whatever the store holds. So before the store is deployed, it goes
/// through ``validatePayload(at:isAppleSigned:)`` once, and the result is
/// recorded against a fingerprint of the store: the check runs again only when
/// the store changes. A store that fails is not deployed, and a copy of it
/// that an earlier deploy left in the runtime is taken back out.
///
/// The stamp only saves repeating the work. Anyone who can change the store
/// can change the stamp too, so it is not what keeps a payload out; the
/// checks at import are.
extension GPTKImporter {
    /// Checks the stored payload unless it was already checked as it is now,
    /// and takes a failing store's deployment out of the runtime.
    ///
    /// Takes about as long as an import's checks the first time and a walk of
    /// the store's few dozen entries afterwards; keep it off the main actor.
    ///
    /// - Returns: the verdict, or `nil` when there is no stored payload.
    @discardableResult
    public static func verifyStoredPayload() -> GPTKStoreVerdict? {
        verifyStoredPayload(
            inStore: storeFolder,
            libraryFolder: WhiskyWineInstaller.libraryFolder,
            isAppleSigned: isAppleSigned(_:identifier:)
        )
    }

    /// Testable seam for ``verifyStoredPayload()``.
    ///
    /// Only a deployment of this store is taken out. A payload copied into the
    /// runtime by hand is not the importer's, and is left as it is.
    @discardableResult
    static func verifyStoredPayload(
        inStore store: URL,
        libraryFolder folder: URL,
        isAppleSigned: (_ code: URL, _ identifier: String) -> Bool
    ) -> GPTKStoreVerdict? {
        let verdict = storeVerdict(inStore: store, isAppleSigned: isAppleSigned)
        guard case .failed = verdict, isStorePayloadDeployed(inLibraryFolder: folder, usingStore: store) else {
            return verdict
        }
        do {
            try remove(fromLibraryFolder: folder, usingStore: store)
            logger.info("Took the stored GPTK payload, which failed its checks, out of the runtime")
        } catch {
            logger.error("Taking the unverified GPTK payload out failed: \(error.localizedDescription)")
        }
        return verdict
    }

    /// The stored payload's verdict, from the stamp when it matches the store
    /// and from ``validatePayload(at:isAppleSigned:)`` otherwise, which then
    /// stamps the store. `nil` when there is no stored payload.
    static func storeVerdict(
        inStore store: URL,
        isAppleSigned: (_ code: URL, _ identifier: String) -> Bool
    ) -> GPTKStoreVerdict? {
        guard storedRecord(inStore: store) != nil, let fingerprint = storeFingerprint(inStore: store) else {
            return nil
        }
        if let stamp = storeStamp(inStore: store), stamp.fingerprint == fingerprint {
            return verdict(of: stamp)
        }

        let stamp: GPTKStoreStamp
        do {
            _ = try validatePayload(at: store.appending(path: "lib"), isAppleSigned: isAppleSigned)
            stamp = GPTKStoreStamp(fingerprint: fingerprint, failure: nil)
            logger.info("The stored GPTK payload passed its checks")
        } catch {
            stamp = GPTKStoreStamp(fingerprint: fingerprint, failure: error.localizedDescription)
            logger.error("The stored GPTK payload failed its checks: \(error.localizedDescription, privacy: .public)")
        }
        writeStoreStamp(stamp, inStore: store)
        return verdict(of: stamp)
    }

    /// Why the stored payload failed its last check, or `nil` when it passed,
    /// has not been checked as it is now, or there is none. Reads the stamp
    /// only, so it never runs the checks.
    static func storeVerificationFailure(inStore store: URL) -> String? {
        guard storedRecord(inStore: store) != nil,
              let stamp = storeStamp(inStore: store),
              stamp.fingerprint == storeFingerprint(inStore: store)
        else { return nil }
        return stamp.failure
    }

    /// Records that the store, as it is now, passed the checks. For an import,
    /// which has just validated exactly what it moved into the store.
    static func stampStoreVerified(inStore store: URL) {
        guard let fingerprint = storeFingerprint(inStore: store) else { return }
        writeStoreStamp(GPTKStoreStamp(fingerprint: fingerprint, failure: nil), inStore: store)
    }

    // MARK: - Fingerprint

    /// A digest of the store's record and of every entry under its `lib`:
    /// path, type, size, modification time and, for a link, its destination.
    /// A reimport changes the record, and touching the payload changes an
    /// entry. Deploying only reads `lib` and writes beside it, so it does not
    /// change the digest. `nil` when the store has no readable record or `lib`.
    static func storeFingerprint(inStore store: URL) -> String? {
        let fileManager = FileManager.default
        let lib = store.appending(path: "lib")
        let libPath = lib.path(percentEncoded: false)
        guard let record = try? Data(contentsOf: recordURL(inStore: store)),
              let entries = try? fileManager.subpathsOfDirectory(atPath: libPath)
        else { return nil }

        var hasher = SHA256()
        hasher.update(data: record)
        for entry in entries.sorted() {
            let path = lib.appending(path: entry).path(percentEncoded: false)
            let attributes = (try? fileManager.attributesOfItem(atPath: path)) ?? [:]
            let type = (attributes[.type] as? FileAttributeType)?.rawValue ?? "?"
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
            let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate ?? 0
            let link = type == FileAttributeType.typeSymbolicLink.rawValue
                ? (try? fileManager.destinationOfSymbolicLink(atPath: path)) ?? "" : ""
            hasher.update(data: Data("\(entry)\u{0}\(type)\u{0}\(size)\u{0}\(modified)\u{0}\(link)\n".utf8))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Stamp

    static func storeStampURL(inStore store: URL) -> URL {
        store.appending(path: "D3DMetalVerification.plist")
    }

    static func storeStamp(inStore store: URL) -> GPTKStoreStamp? {
        guard let data = try? Data(contentsOf: storeStampURL(inStore: store)) else { return nil }
        return try? PropertyListDecoder().decode(GPTKStoreStamp.self, from: data)
    }

    /// Without a stamp the check only runs again next time, so a failed write
    /// is logged and otherwise ignored.
    private static func writeStoreStamp(_ stamp: GPTKStoreStamp, inStore store: URL) {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        do {
            try encoder.encode(stamp).write(to: storeStampURL(inStore: store), options: .atomic)
        } catch {
            logger.error("Recording the GPTK store check failed: \(error.localizedDescription)")
        }
    }

    private static func verdict(of stamp: GPTKStoreStamp) -> GPTKStoreVerdict {
        stamp.failure.map { .failed(reason: $0) } ?? .verified
    }
}
