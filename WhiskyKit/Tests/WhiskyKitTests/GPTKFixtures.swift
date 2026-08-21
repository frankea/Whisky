//
//  GPTKFixtures.swift
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

/// Builds a fake PE: 0x40 bytes of stub, then either winebuild's marker
/// (Apple's forwarders and Wine's builtins carry it) or filler (a native PE).
func fakePE(builtin: Bool) -> Data {
    var data = Data(count: 0x40)
    data.append(builtin ? Data("Wine builtin DLL".utf8) : Data(count: 16))
    data.append(Data(count: 16))
    return data
}

/// Assembles Apple's `redist/lib` payload layout under `libRoot`.
func makePayload(
    at libRoot: URL,
    version: String? = "4.0b2",
    builtinForwarders: Bool = true,
    omitting: Set<String> = [],
    unixEntriesAsFiles: Bool = false
) throws {
    let fileManager = FileManager.default
    let peDir = libRoot.appending(path: "wine").appending(path: "x86_64-windows")
    let unixDir = libRoot.appending(path: "wine").appending(path: "x86_64-unix")
    let external = libRoot.appending(path: "external")
    try fileManager.createDirectory(at: peDir, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: unixDir, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: external, withIntermediateDirectories: true)

    for name in GPTKImporter.forwarderDLLNames where !omitting.contains(name) {
        try fakePE(builtin: builtinForwarders).write(to: peDir.appending(path: name))
    }

    if !omitting.contains("libd3dshared.dylib") {
        try Data("fake dylib".utf8).write(to: external.appending(path: "libd3dshared.dylib"))
    }

    if !omitting.contains("D3DMetal.framework") {
        let resources = external.appending(path: "D3DMetal.framework")
            .appending(path: "Versions").appending(path: "A").appending(path: "Resources")
        try fileManager.createDirectory(at: resources, withIntermediateDirectories: true)
        if let version {
            let plist: [String: Any] = ["CFBundleShortVersionString": version]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: resources.appending(path: "Info.plist"))
        }
    }

    for name in GPTKImporter.unixLibraryNames where !omitting.contains(name) {
        let entry = unixDir.appending(path: name)
        if unixEntriesAsFiles {
            try Data("resolved copy".utf8).write(to: entry)
        } else {
            try fileManager.createSymbolicLink(
                atPath: entry.path(percentEncoded: false),
                withDestinationPath: GPTKImporter.unixLinkDestination
            )
        }
    }
}

/// Assembles a minimal Wine runtime tree with builtin-marked d3d DLLs.
func makeRuntime(at libraryFolder: URL, marker: String = "wine original") throws {
    let fileManager = FileManager.default
    let wineLib = libraryFolder.appending(path: "Wine").appending(path: "lib")
    let peDir = wineLib.appending(path: "wine").appending(path: "x86_64-windows")
    let unixDir = wineLib.appending(path: "wine").appending(path: "x86_64-unix")
    try fileManager.createDirectory(at: peDir, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: unixDir, withIntermediateDirectories: true)
    for name in ["d3d10.dll", "d3d11.dll", "d3d12.dll", "dxgi.dll"] {
        var wineBuiltin = fakePE(builtin: true)
        wineBuiltin.append(Data(marker.utf8))
        try wineBuiltin.write(to: peDir.appending(path: name))
    }
}

/// Writes the runtime version plist deploy stamps its backups against.
func writeRuntimeVersion(at libraryFolder: URL, _ major: Int, _ minor: Int, _ patch: Int) throws {
    let plist: [String: Any] = ["version": ["major": major, "minor": minor, "patch": patch]]
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try data.write(
        to: libraryFolder.appending(path: "WhiskyWineVersion").appendingPathExtension("plist")
    )
}

/// Gzip-tars a minimal `Libraries` tree the way the runtime archive ships.
func makeLibrariesTarball(in directory: URL) throws -> URL {
    let source = directory.appending(path: "Libraries")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try Data("marker".utf8).write(to: source.appending(path: "marker.txt"))

    let tarball = directory.appending(path: "archive.tar.gz")
    let tar = Process()
    tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
    tar.currentDirectoryURL = directory
    tar.arguments = ["-czf", tarball.path(percentEncoded: false), "Libraries"]
    try tar.run()
    tar.waitUntilExit()
    return tarball
}

/// A fresh scratch directory for one GPTK test case.
func makeGPTKTempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "gptk_tests_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Hand-builds what an interrupted same-version deploy leaves behind, and
/// returns the runtime's PE directory: `d3d10.dll` swapped with its original
/// backed up, `d3d12.dll` backed up before its forwarder was copied in, and
/// `d3d11.dll` never reached, so still Wine's own with no backup.
@discardableResult
func makePartialDeploy(store: URL, runtime: URL, runtimeVersion: String) throws -> URL {
    let fileManager = FileManager.default
    let peDir = runtime.appending(path: "Wine").appending(path: "lib")
        .appending(path: "wine").appending(path: "x86_64-windows")
    let storePE = store.appending(path: "lib")
        .appending(path: "wine").appending(path: "x86_64-windows")
    let originals = store.appending(path: "originals")
    try fileManager.createDirectory(at: originals, withIntermediateDirectories: true)

    let encoder = PropertyListEncoder()
    encoder.outputFormat = .xml
    try encoder.encode(GPTKOriginalsRecord(runtimeVersion: runtimeVersion))
        .write(to: GPTKImporter.originalsRecordURL(inStore: store))

    for name in ["d3d10.dll", "d3d12.dll"] {
        try fileManager.moveItem(at: peDir.appending(path: name), to: originals.appending(path: name))
    }
    try fileManager.copyItem(
        at: storePE.appending(path: "d3d10.dll"), to: peDir.appending(path: "d3d10.dll")
    )
    return peDir
}

/// Adds Apple's MetalFX bridge to a store's payload.
///
/// ``makePayload(at:version:builtinForwarders:omitting:unixEntriesAsFiles:)``
/// leaves it out so a payload without one, which is what every GPTK before it
/// shipped, stays the default the deployment tests see.
@discardableResult
func makeStoreMetalFXBridge(inStore store: URL, marker: String = "metalfx bridge") throws -> URL {
    let dll = store.appending(path: "lib").appending(path: "wine")
        .appending(path: "x86_64-windows").appending(path: GPTKImporter.metalFXBridgeSourceName)
    var data = fakePE(builtin: true)
    data.append(Data(marker.utf8))
    try data.write(to: dll)
    return dll
}

/// A store holding a freshly imported payload, under `tempDir`.
func makeImportedStore(in tempDir: URL) throws -> URL {
    let lib = tempDir.appending(path: "payload")
    let store = tempDir.appending(path: "store")
    try makePayload(at: lib)
    try GPTKImporter.importPayload(GPTKImporter.validatePayload(at: lib), intoStore: store)
    return store
}
