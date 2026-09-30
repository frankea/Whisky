//
//  GPTKPayloadAuthenticityTests.swift
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

/// Runs `tool` and returns its exit status and standard output.
private func run(_ tool: String, _ arguments: [String]) -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(filePath: tool)
    process.arguments = arguments
    let stdout = Pipe()
    process.standardOutput = stdout
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
    } catch {
        return (-1, "")
    }
    let data = stdout.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(bytes: data, encoding: .utf8) ?? "")
}

/// Whether this machine has what ``makeHalfSignedUniversalBinary(in:)``
/// needs: `lipo`, `codesign`, and a `/bin/ls` with arm64e and x86_64 slices.
private let canBuildHalfSignedBinary: Bool = {
    guard FileManager.default.isExecutableFile(atPath: "/usr/bin/codesign") else { return false }
    let architectures = run("/usr/bin/lipo", ["-archs", "/bin/ls"]).output.split(whereSeparator: \.isWhitespace)
    return Set(architectures.map(String.init)).isSuperset(of: ["arm64e", "x86_64"])
}()

/// Builds the file the architecture check exists for: `/bin/ls` with its
/// Apple-signed arm64e slice kept and its x86_64 slice's signature stripped.
/// On Apple silicon the host's slice passes a check that looks at it alone,
/// while the slice Rosetta would load is unsigned. The signed slice is
/// returned on its own too, as the control.
private func makeHalfSignedUniversalBinary(in directory: URL) throws -> (universal: URL, signedSlice: URL) {
    let signed = directory.appending(path: "ls-arm64e").path(percentEncoded: false)
    let unsigned = directory.appending(path: "ls-x86_64").path(percentEncoded: false)
    let universal = directory.appending(path: "ls-half-signed").path(percentEncoded: false)
    let steps = [
        ["/usr/bin/lipo", "/bin/ls", "-thin", "arm64e", "-output", signed],
        ["/usr/bin/lipo", "/bin/ls", "-thin", "x86_64", "-output", unsigned],
        ["/usr/bin/codesign", "--remove-signature", unsigned],
        ["/usr/bin/lipo", "-create", signed, unsigned, "-output", universal]
    ]
    for step in steps {
        try #require(run(step[0], Array(step.dropFirst())).status == 0, "\(step.joined(separator: " ")) failed")
    }
    return (URL(filePath: universal), URL(filePath: signed))
}

/// Points the symlink at `link` somewhere else.
private func relink(_ link: URL, to destination: String) throws {
    try FileManager.default.removeItem(at: link)
    try FileManager.default.createSymbolicLink(
        atPath: link.path(percentEncoded: false), withDestinationPath: destination
    )
}

/// Moves `item` out of the payload, beside it, and leaves a link to it behind.
private func replaceWithLink(_ item: URL, outside libRoot: URL) throws {
    let elsewhere = libRoot.deletingLastPathComponent().appending(path: "elsewhere-\(item.lastPathComponent)")
    try FileManager.default.moveItem(at: item, to: elsewhere)
    try FileManager.default.createSymbolicLink(at: item, withDestinationURL: elsewhere)
}

/// A change in or around the sealed framework version, and the item the
/// layout check has to name for it, whether or not Apple's signature check
/// would notice it too.
enum GPTKLayoutTamper: String, CaseIterable, Sendable {
    /// A library beside `A`, which the loader searches before the sealed
    /// `Versions/A/Resources`.
    case plantedVersionsResources
    /// A second version folder, which codesign's strict mode accepts.
    case extraVersion
    /// `Current` pointing at another version.
    case redirectedCurrent
    /// The top-level `D3DMetal` link resolved into a file, as `cp -RL` leaves it.
    case resolvedTopLevelLink
    /// A top-level link that does not point at its namesake.
    case misdirectedTopLevelLink
    /// A library in the framework root.
    case plantedFrameworkRoot
    /// A folder beside the framework, searched when the loader path is the
    /// framework root.
    case plantedExternalResources
    /// The shared library as a link, which the import would copy as a link.
    case linkedSharedLibrary
    /// The framework as a link to a folder outside the payload.
    case linkedFramework
    /// `external/` itself as a link to a folder outside the payload.
    case linkedExternal
    /// The main executable as a link to a copy outside the payload. The
    /// signature check follows it, and the loader would resolve D3DMetal's
    /// rpaths beside that copy.
    case linkedMainExecutable
    /// `_CodeSignature` as a link out, which even strict mode accepts.
    case linkedCodeSignature
    /// A sealed file deeper down as a link out. The seal notices this one,
    /// but the layout check has to reach that far too.
    case linkedSealedFile

    var offendingItem: String {
        switch self {
        case .plantedVersionsResources: "external/D3DMetal.framework/Versions/Resources"
        case .extraVersion: "external/D3DMetal.framework/Versions/B"
        case .redirectedCurrent: "external/D3DMetal.framework/Versions/Current"
        case .resolvedTopLevelLink: "external/D3DMetal.framework/D3DMetal"
        case .misdirectedTopLevelLink: "external/D3DMetal.framework/Resources"
        case .plantedFrameworkRoot: "external/D3DMetal.framework/libmetalirconverter.dylib"
        case .plantedExternalResources: "external/Resources"
        case .linkedSharedLibrary: "external/libd3dshared.dylib"
        case .linkedFramework: "external/D3DMetal.framework"
        case .linkedExternal: "external"
        case .linkedMainExecutable: "external/D3DMetal.framework/Versions/A/D3DMetal"
        case .linkedCodeSignature: "external/D3DMetal.framework/Versions/A/_CodeSignature"
        case .linkedSealedFile: "external/D3DMetal.framework/Versions/A/Resources/Info.plist"
        }
    }

    func apply(toPayload libRoot: URL) throws {
        let fileManager = FileManager.default
        let external = libRoot.appending(path: "external")
        let framework = external.appending(path: "D3DMetal.framework")
        let versions = framework.appending(path: "Versions")
        let sealed = versions.appending(path: "A")
        let library = Data("planted library".utf8)
        let libraryName = "libmetalirconverter.dylib"
        switch self {
        case .plantedVersionsResources:
            let folder = versions.appending(path: "Resources")
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try library.write(to: folder.appending(path: libraryName))
        case .extraVersion:
            try fileManager.copyItem(at: sealed, to: versions.appending(path: "B"))
        case .redirectedCurrent:
            try relink(versions.appending(path: "Current"), to: "B")
        case .resolvedTopLevelLink:
            try fileManager.removeItem(at: framework.appending(path: "D3DMetal"))
            try library.write(to: framework.appending(path: "D3DMetal"))
        case .misdirectedTopLevelLink:
            try relink(framework.appending(path: "Resources"), to: "../Resources")
        case .plantedFrameworkRoot:
            try library.write(to: framework.appending(path: libraryName))
        case .plantedExternalResources:
            let folder = external.appending(path: "Resources")
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try library.write(to: folder.appending(path: libraryName))
        case .linkedCodeSignature:
            let signature = sealed.appending(path: "_CodeSignature")
            try fileManager.createDirectory(at: signature, withIntermediateDirectories: true)
            try replaceWithLink(signature, outside: libRoot)
        case .linkedSharedLibrary, .linkedFramework, .linkedExternal, .linkedMainExecutable, .linkedSealedFile:
            // The item to move out is the one the check has to name.
            try replaceWithLink(libRoot.appending(path: offendingItem), outside: libRoot)
        }
    }
}

@Suite("GPTK payload authenticity")
struct GPTKPayloadAuthenticityTests {
    private let tempDir: URL

    init() throws {
        tempDir = try makeGPTKTempDir()
    }

    // MARK: - Signature

    @Test(
        "A universal file with an unsigned slice fails even when its other slice is Apple's",
        .enabled(if: canBuildHalfSignedBinary, "needs lipo, codesign, and a /bin/ls with arm64e and x86_64 slices")
    )
    func refusesUnsignedSlice() throws {
        let binary = try makeHalfSignedUniversalBinary(in: tempDir)

        #expect(GPTKImporter.isAppleSigned(binary.signedSlice, identifier: "com.apple.ls"))
        #expect(!GPTKImporter.isAppleSigned(binary.universal, identifier: "com.apple.ls"))
    }

    // MARK: - Layout

    @Test("An item Apple's signature does not cover is refused by name", arguments: GPTKLayoutTamper.allCases)
    func refusesUnsealedItem(_ tamper: GPTKLayoutTamper) throws {
        let lib = tempDir.appending(path: "lib")
        try makePayload(at: lib)
        try tamper.apply(toPayload: lib)

        #expect(throws: GPTKImportError.unsealedItem(tamper.offendingItem)) {
            try GPTKImporter.validatePayload(at: lib, isAppleSigned: { _, _ in true })
        }
    }

    @Test("Apple's layouts pass: a link with nothing behind it, a link through Versions/A, and Finder metadata")
    func acceptsAppleLayouts() throws {
        let lib = tempDir.appending(path: "lib")
        try makePayload(at: lib)
        let external = lib.appending(path: "external")
        let framework = external.appending(path: "D3DMetal.framework")
        // GPTK 2.0 ships a Headers link with nothing behind it.
        try FileManager.default.createSymbolicLink(
            atPath: framework.appending(path: "Headers").path(percentEncoded: false),
            withDestinationPath: "Versions/Current/Headers"
        )
        try relink(framework.appending(path: "Resources"), to: "Versions/A/Resources")
        // Inside the sealed version, real folders and files at any depth.
        let sealed = framework.appending(path: "Versions").appending(path: "A")
        let signature = sealed.appending(path: "_CodeSignature")
        try FileManager.default.createDirectory(at: signature, withIntermediateDirectories: true)
        try Data().write(to: signature.appending(path: "CodeResources"))
        let folders = [
            external, framework, framework.appending(path: "Versions"), sealed, sealed.appending(path: "Resources")
        ]
        for folder in folders {
            try Data().write(to: folder.appending(path: ".DS_Store"))
        }

        #expect(GPTKImporter.unsealedItem(inExternal: external) == nil)
        #expect(try GPTKImporter.validatePayload(at: lib, isAppleSigned: { _, _ in true }).version == "4.0b2")
    }

    @Test("A folder the check cannot list is refused, since the loader can still reach into it")
    func refusesUnlistableFolder() throws {
        let lib = tempDir.appending(path: "lib")
        try makePayload(at: lib)
        let external = lib.appending(path: "external")
        let versions = external.appending(path: "D3DMetal.framework").appending(path: "Versions")
            .path(percentEncoded: false)
        // Search permission without read: items stay reachable by name, but
        // the folder cannot be listed.
        try FileManager.default.setAttributes([.posixPermissions: 0o311], ofItemAtPath: versions)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: versions)
        }

        #expect(GPTKImporter.unsealedItem(inExternal: external) == "external/D3DMetal.framework/Versions")
    }

    // MARK: - Import

    @Test("Import validates the copy it staged in the store, and records that copy's version")
    func importRevalidatesStagedCopy() throws {
        let lib = tempDir.appending(path: "lib")
        let store = tempDir.appending(path: "store")
        try makePayload(at: lib)
        let payload = try GPTKImporter.validatePayload(at: lib, isAppleSigned: { _, _ in true })
        // The source moves on after validation; the record has to describe
        // what was copied, not what was validated.
        let plist: [String: Any] = ["CFBundleShortVersionString": "4.0b3"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(
            to: lib.appending(path: "external").appending(path: "D3DMetal.framework").appending(path: "Versions")
                .appending(path: "A").appending(path: "Resources").appending(path: "Info.plist")
        )
        var checked: [String] = []

        try GPTKImporter.importPayload(payload, intoStore: store, revalidatingWith: { url, _ in
            checked.append(url.path(percentEncoded: false))
            return true
        })

        let staging = store.appending(path: "lib.staging")
        let stagedCode = GPTKImporter.appleSignedCode.map {
            staging.appending(path: "external").appending(path: $0.name).path(percentEncoded: false)
        }
        #expect(checked == stagedCode)
        #expect(!FileManager.default.fileExists(atPath: staging.path(percentEncoded: false)))
        #expect(GPTKImporter.storedRecord(inStore: store)?.gptkVersion == "4.0b3")
    }

    @Test("A source changed after validation is refused at import, and the store keeps its payload")
    func importRefusesSourceChangedAfterValidation() throws {
        let store = tempDir.appending(path: "store")
        let first = tempDir.appending(path: "first")
        try makePayload(at: first, version: "4.0b1")
        let firstPayload = try GPTKImporter.validatePayload(at: first, isAppleSigned: { _, _ in true })
        try GPTKImporter.importPayload(firstPayload, intoStore: store, revalidatingWith: { _, _ in true })

        let second = tempDir.appending(path: "second")
        try makePayload(at: second)
        let payload = try GPTKImporter.validatePayload(at: second, isAppleSigned: { _, _ in true })
        let tamper = GPTKLayoutTamper.plantedVersionsResources
        try tamper.apply(toPayload: second)

        #expect(throws: GPTKImportError.unsealedItem(tamper.offendingItem)) {
            try GPTKImporter.importPayload(payload, intoStore: store, revalidatingWith: { _, _ in true })
        }
        #expect(GPTKImporter.storedRecord(inStore: store)?.gptkVersion == "4.0b1")
        for leftover in ["lib.staging", "lib/external/D3DMetal.framework/Versions/Resources"] {
            let path = store.appending(path: leftover).path(percentEncoded: false)
            #expect(!FileManager.default.fileExists(atPath: path))
        }
    }

    @Test("Importing through a link copies the folder it points to, so the store keeps no link to the source")
    func importResolvesLinkedPayload() throws {
        let lib = tempDir.appending(path: "lib")
        let link = tempDir.appending(path: "linked-lib")
        let store = tempDir.appending(path: "store")
        try makePayload(at: lib)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: lib)
        let payload = try GPTKImporter.validatePayload(at: link, isAppleSigned: { _, _ in true })

        try GPTKImporter.importPayload(payload, intoStore: store, revalidatingWith: { _, _ in true })

        let storeLib = store.appending(path: "lib").path(percentEncoded: false)
        let type = try FileManager.default.attributesOfItem(atPath: storeLib)[.type] as? FileAttributeType
        #expect(type == .typeDirectory)
        #expect(GPTKImporter.storedRecord(inStore: store)?.gptkVersion == "4.0b2")
    }

    @Test("A copy that fails part way leaves no staged folder behind")
    func importCleansUpFailedCopy() throws {
        let lib = tempDir.appending(path: "lib")
        let store = tempDir.appending(path: "store")
        try makePayload(at: lib)
        let payload = try GPTKImporter.validatePayload(at: lib, isAppleSigned: { _, _ in true })
        let unreadable = lib.appending(path: "wine").appending(path: "x86_64-windows")
            .appending(path: "dxgi.dll").path(percentEncoded: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadable)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: unreadable)
        }

        #expect(throws: (any Error).self) {
            try GPTKImporter.importPayload(payload, intoStore: store, revalidatingWith: { _, _ in true })
        }
        let staging = store.appending(path: "lib.staging").path(percentEncoded: false)
        #expect(!FileManager.default.fileExists(atPath: staging))
    }

    // MARK: - Identity

    @Test("Another Apple-signed binary cannot stand in for the payload's code")
    func refusesOtherAppleIdentity() {
        let appleBinary = URL(filePath: "/bin/ls")

        #expect(GPTKImporter.isAppleSigned(appleBinary, identifier: "com.apple.ls"))
        for code in GPTKImporter.appleSignedCode {
            #expect(!GPTKImporter.isAppleSigned(appleBinary, identifier: code.identifier))
        }
    }
}
