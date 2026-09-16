//
//  GPTKImporterTests.swift
//  WhiskyKitTests
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
import Testing
@testable import WhiskyKit

@Suite("GPTKImporter Tests")
struct GPTKImporterTests {
    private let tempDir: URL

    init() throws {
        tempDir = try makeGPTKTempDir()
    }

    // MARK: - Locating

    @Test("Locates the payload from volume root, redist folder, and lib folder")
    func locateFromAllShapes() throws {
        let volume = tempDir.appending(path: "volume")
        let lib = volume.appending(path: "redist").appending(path: "lib")
        try makePayload(at: lib)

        #expect(GPTKImporter.locatePayload(under: volume) == lib)
        #expect(GPTKImporter.locatePayload(under: volume.appending(path: "redist")) == lib)
        #expect(GPTKImporter.locatePayload(under: lib) == lib)
    }

    @Test("Locate returns nil when nothing payload-shaped exists")
    func locateNothing() throws {
        #expect(GPTKImporter.locatePayload(under: tempDir) == nil)
    }

    // MARK: - Validation

    @Test("Validates a complete payload and reads its version")
    func validateComplete() throws {
        let lib = tempDir.appending(path: "lib")
        try makePayload(at: lib)

        let payload = try GPTKImporter.validatePayload(at: lib, isAppleSigned: { _ in true })

        #expect(payload.version == "4.0b2")
        #expect(payload.libRoot == lib)
    }

    @Test("An unsigned shared library is rejected by the real signature check")
    func validateUnsignedPayload() throws {
        let lib = tempDir.appending(path: "lib")
        try makePayload(at: lib)

        #expect(throws: GPTKImportError.notAppleSigned("external/libd3dshared.dylib")) {
            try GPTKImporter.validatePayload(at: lib)
        }
    }

    @Test("The signature check covers the shared library and the framework, in that order")
    func validateChecksBothAppleBinaries() throws {
        let lib = tempDir.appending(path: "lib")
        try makePayload(at: lib)
        var checked: [String] = []

        _ = try GPTKImporter.validatePayload(at: lib, isAppleSigned: { url in
            checked.append(url.lastPathComponent)
            return true
        })

        #expect(checked == ["libd3dshared.dylib", "D3DMetal.framework"])
    }

    @Test("A framework that fails the signature check is named")
    func validateUnsignedFramework() throws {
        let lib = tempDir.appending(path: "lib")
        try makePayload(at: lib)

        #expect(throws: GPTKImportError.notAppleSigned("external/D3DMetal.framework")) {
            try GPTKImporter.validatePayload(at: lib, isAppleSigned: { url in
                url.lastPathComponent != "D3DMetal.framework"
            })
        }
    }

    @Test("Completeness and variant errors take precedence over the signature check")
    func validateSignatureCheckRunsLast() throws {
        let lib = tempDir.appending(path: "lib")
        try makePayload(at: lib, builtinForwarders: false)

        #expect(throws: GPTKImportError.forwarderNotBuiltin("d3d10.dll")) {
            try GPTKImporter.validatePayload(at: lib)
        }
    }

    @Test("The Apple signature check accepts a system binary and refuses a plain file")
    func appleSignatureCheck() throws {
        let plain = tempDir.appending(path: "plain.dylib")
        try Data("not a code object".utf8).write(to: plain)

        #expect(GPTKImporter.isAppleSigned(URL(filePath: "/bin/ls")))
        #expect(!GPTKImporter.isAppleSigned(plain))
        #expect(!GPTKImporter.isAppleSigned(tempDir.appending(path: "missing.dylib")))
    }

    @Test("Missing forwarders are reported by name")
    func validateMissingForwarder() throws {
        let lib = tempDir.appending(path: "lib")
        try makePayload(at: lib, omitting: ["d3d12.dll"])

        #expect(throws: GPTKImportError.payloadIncomplete(missing: ["wine/x86_64-windows/d3d12.dll"])) {
            try GPTKImporter.validatePayload(at: lib)
        }
    }

    @Test("A native-marked forwarder is rejected")
    func validateNativeForwarder() throws {
        let lib = tempDir.appending(path: "lib")
        try makePayload(at: lib, builtinForwarders: false)

        #expect(throws: GPTKImportError.forwarderNotBuiltin("d3d10.dll")) {
            try GPTKImporter.validatePayload(at: lib)
        }
    }

    @Test("A forwarder too short to hold the marker is rejected")
    func validateTruncatedForwarder() throws {
        let lib = tempDir.appending(path: "lib")
        try makePayload(at: lib)
        let peDir = lib.appending(path: "wine").appending(path: "x86_64-windows")
        try Data([0x4D, 0x5A, 0x00]).write(to: peDir.appending(path: "d3d12.dll"))

        #expect(throws: GPTKImportError.forwarderNotBuiltin("d3d12.dll")) {
            try GPTKImporter.validatePayload(at: lib)
        }
    }

    @Test("A missing framework is reported")
    func validateMissingFramework() throws {
        let lib = tempDir.appending(path: "lib")
        try makePayload(at: lib, omitting: ["D3DMetal.framework"])

        #expect(throws: GPTKImportError.payloadIncomplete(missing: ["external/D3DMetal.framework"])) {
            try GPTKImporter.validatePayload(at: lib)
        }
    }

    @Test("An unreadable framework version is rejected")
    func validateUnreadableVersion() throws {
        let lib = tempDir.appending(path: "lib")
        try makePayload(at: lib, version: nil)

        #expect(throws: GPTKImportError.versionUnreadable) {
            try GPTKImporter.validatePayload(at: lib)
        }
    }

    // MARK: - Import

    @Test("Import copies the payload, normalizes symlinks, and records the version")
    func importPayload() throws {
        let lib = tempDir.appending(path: "lib")
        let store = tempDir.appending(path: "store")
        try makePayload(at: lib)
        let payload = try GPTKImporter.validatePayload(at: lib, isAppleSigned: { _ in true })

        let record = try GPTKImporter.importPayload(payload, intoStore: store)

        #expect(record.gptkVersion == "4.0b2")
        #expect(GPTKImporter.storedRecord(inStore: store)?.gptkVersion == "4.0b2")

        let link = store.appending(path: "lib").appending(path: "wine")
            .appending(path: "x86_64-unix").appending(path: "dxgi.so")
        let destination = try FileManager.default.destinationOfSymbolicLink(
            atPath: link.path(percentEncoded: false)
        )
        #expect(destination == GPTKImporter.unixLinkDestination)
    }

    @Test("Import rebuilds unix entries as symlinks even when the source resolved them into files")
    func importNormalizesResolvedUnixEntries() throws {
        let lib = tempDir.appending(path: "lib")
        let store = tempDir.appending(path: "store")
        try makePayload(at: lib, unixEntriesAsFiles: true)
        let payload = try GPTKImporter.validatePayload(at: lib, isAppleSigned: { _ in true })

        try GPTKImporter.importPayload(payload, intoStore: store)

        let link = store.appending(path: "lib").appending(path: "wine")
            .appending(path: "x86_64-unix").appending(path: "d3d11.so")
        let destination = try FileManager.default.destinationOfSymbolicLink(
            atPath: link.path(percentEncoded: false)
        )
        #expect(destination == GPTKImporter.unixLinkDestination)
    }

    @Test("Stored record is nil without a store or with a gutted payload")
    func storedRecordAbsent() throws {
        let store = tempDir.appending(path: "store")
        #expect(GPTKImporter.storedRecord(inStore: store) == nil)

        let lib = tempDir.appending(path: "lib")
        try makePayload(at: lib)
        let payload = try GPTKImporter.validatePayload(at: lib, isAppleSigned: { _ in true })
        try GPTKImporter.importPayload(payload, intoStore: store)
        try FileManager.default.removeItem(
            at: store.appending(path: "lib").appending(path: "external")
        )

        #expect(GPTKImporter.storedRecord(inStore: store) == nil)
    }
}
