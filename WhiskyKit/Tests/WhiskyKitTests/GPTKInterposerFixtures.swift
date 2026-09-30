//
//  GPTKInterposerFixtures.swift
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
@testable import WhiskyKit

/// Stores, runtime trees and bottles for the interposer policy suites, all
/// under one scratch directory per test case.
struct GPTKInterposerFixture {
    /// The build the interposers were validated on, which the fixtures use
    /// wherever a payload has to qualify.
    static let validatedVersion = "4.0b2"

    let tempDir: URL

    init() throws {
        tempDir = try makeGPTKTempDir()
    }

    func peDir(of runtime: URL) -> URL {
        runtime.appending(path: "Wine").appending(path: "lib").appending(path: "wine")
            .appending(path: "x86_64-windows")
    }

    func unixDir(of runtime: URL) -> URL {
        runtime.appending(path: "Wine").appending(path: "lib").appending(path: "wine")
            .appending(path: "x86_64-unix")
    }

    func external(of runtime: URL) -> URL {
        runtime.appending(path: "Wine").appending(path: "lib").appending(path: "external")
    }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// Whether `url` is a symbolic link, dangling or not.
    func isLink(_ url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path(percentEncoded: false))) != nil
    }

    /// A store holding a payload of `version`, with both interposed slots
    /// shaped so the export rename can walk them.
    ///
    /// Imported without validation: that is not what is under test, and it
    /// checks things these fixtures cannot provide.
    func makeStore(version: String) throws -> URL {
        let lib = tempDir.appending(path: "payload")
        let store = tempDir.appending(path: "store")
        try makePayload(at: lib, version: version)
        try GPTKImporter.importPayload(GPTKPayload(libRoot: lib, version: version), intoStore: store)
        for interposer in GPTKImporter.interposers {
            try makeStoreSlotRenameable(inStore: store, slotName: interposer.slotName)
        }
        return store
    }

    /// A runtime tree, carrying both interposers unless told otherwise.
    func makeRuntimeTree(shippingInterposers: Bool = true) throws -> URL {
        let runtime = tempDir.appending(path: "Libraries")
        try makeRuntime(at: runtime)
        if shippingInterposers {
            try makeShims(in: runtime)
        }
        return runtime
    }

    func makeShims(in runtime: URL) throws {
        for interposer in GPTKImporter.interposers {
            try makeInterposerShim(interposer, at: runtime, marker: "\(interposer.label) shim")
        }
    }

    /// Copies Apple's files into the tree by hand, the way the GPTK readme
    /// describes and the importer never sees: forwarders over the builtins,
    /// the unix bridges beside them, and `external/`.
    func overlayPayloadByHand(version: String, into runtime: URL) throws {
        let fileManager = FileManager.default
        for name in GPTKImporter.forwarderDLLNames {
            let target = peDir(of: runtime).appending(path: name)
            try? fileManager.removeItem(at: target)
            var dll = fakePEWithExportName(name)
            dll.append(Data("placed by hand".utf8))
            try dll.write(to: target)
        }
        for name in GPTKImporter.unixLibraryNames {
            try fileManager.createSymbolicLink(
                atPath: unixDir(of: runtime).appending(path: name).path(percentEncoded: false),
                withDestinationPath: GPTKImporter.unixLinkDestination
            )
        }
        let payload = tempDir.appending(path: "by-hand")
        try makePayload(at: payload, version: version)
        try fileManager.copyItem(at: payload.appending(path: "external"), to: external(of: runtime))
    }

    func setFrameworkVersion(_ version: String, inExternal external: URL) throws {
        let plist: [String: Any] = ["CFBundleShortVersionString": version]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(
            to: external.appending(path: "D3DMetal.framework").appending(path: "Versions")
                .appending(path: "A").appending(path: "Resources").appending(path: "Info.plist")
        )
    }

    /// Makes the swap the way releases before the version check did: over
    /// whatever payload the runtime holds, whatever its version.
    func installIgnoringVersion(_ interposer: GPTKInterposer, into runtime: URL) throws {
        let version = GPTKImporter.deployedPayloadVersion(inLibraryFolder: runtime)
        try setFrameworkVersion(Self.validatedVersion, inExternal: external(of: runtime))
        try GPTKImporter.install(interposer, intoLibraryFolder: runtime)
        if let version {
            try setFrameworkVersion(version, inExternal: external(of: runtime))
        }
    }

    /// What a deploy from before the version check left behind: the store's
    /// payload with both interposers in front of it, relabelled as `version`.
    func makePreGateDeploy(version: String) throws -> (store: URL, runtime: URL) {
        let store = try makeStore(version: Self.validatedVersion)
        let runtime = try makeRuntimeTree()
        try GPTKImporter.deploy(fromStore: store, intoLibraryFolder: runtime)
        try setFrameworkVersion(version, inExternal: store.appending(path: "lib").appending(path: "external"))
        try setFrameworkVersion(version, inExternal: external(of: runtime))
        return (store, runtime)
    }

    func makeBottle() throws -> URL {
        let bottle = tempDir.appending(path: "bottle")
        try FileManager.default.createDirectory(
            at: bottle.appending(path: "drive_c").appending(path: "windows").appending(path: "system32"),
            withIntermediateDirectories: true
        )
        return bottle
    }

    func placeholder(in bottle: URL) -> URL {
        bottle.appending(path: "drive_c").appending(path: "windows").appending(path: "system32")
            .appending(path: GPTKImporter.videoProcessorInterposer.renamedName)
    }
}
