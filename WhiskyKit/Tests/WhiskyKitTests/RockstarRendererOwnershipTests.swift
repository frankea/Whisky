//
//  RockstarRendererOwnershipTests.swift
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

/// wined3d's `renderer` for Rockstar's `Launcher.exe`, a value Whisky owns
/// only while it is the one that wrote it (#382), run against the simulated
/// registry the DLL override preservation suite uses.
@Suite("Rockstar renderer ownership")
@MainActor
final class RockstarRendererOwnershipTests {
    private let tempRoot: URL
    private let registry = SimulatedRegistry()
    private let direct3DKey = Wine.DLLOverrideScope.direct3D("Launcher.exe").registryKey

    init() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "rockstar_renderer_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func makeBottle() throws -> Bottle {
        let bottleURL = tempRoot.appending(path: "Bottle")
        try FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)
        return Bottle(bottleUrl: bottleURL)
    }

    /// Syncs Rockstar's `Launcher.exe` with `renderer` asked for (`nil` asks
    /// for none), reading the simulated registry as a launch reads `user.reg`.
    /// Returns the document imported.
    @discardableResult
    private func syncLauncher(_ bottle: Bottle, renderer: String?) async throws -> String {
        var documents: [String] = []
        try await Wine.syncDLLOverrides(
            bottle: bottle,
            scopes: [
                (scope: .program("Launcher.exe"), overrides: "d3d11=b;dxgi=b"),
                (scope: .direct3D("Launcher.exe"), overrides: renderer.map { "renderer=\($0)" } ?? "")
            ],
            importer: { document, _ in
                documents.append(document)
                self.registry.apply(document)
            },
            currentValue: { key, name in self.registry.values(key)[name.lowercased()] }
        )
        return documents.joined()
    }

    /// The lines of `document` inside `key`'s section.
    private func section(_ key: String, in document: String) -> [String] {
        let lines = document.components(separatedBy: "\r\n")
        guard let start = lines.firstIndex(of: "[\(key)]") else { return [] }
        return Array(lines[(start + 1)...].prefix { !$0.isEmpty })
    }

    private func recordedRenderer(_ bottle: Bottle) -> String? {
        DLLOverrideRecord.load(from: bottle.url).ownedValue("renderer", in: direct3DKey)
    }

    @Test("The renderer goes into the Direct3D key in the same import, with no DLL names taken out of it")
    func rendererGoesIntoItsOwnKey() async throws {
        let bottle = try makeBottle()

        let document = try await syncLauncher(bottle, renderer: "gl")

        #expect(section(direct3DKey, in: document) == [#""renderer"="gl""#])
        #expect(registry.values(direct3DKey) == ["renderer": "gl"])
        #expect(registry.values(Wine.DLLOverrideScope.program("Launcher.exe").registryKey)["d3d11"] == "b")
        #expect(recordedRenderer(bottle) == "gl")
        // The DLL name record never learns the Direct3D key.
        #expect(DLLOverrideRecord.load(from: bottle.url).names(for: direct3DKey).isEmpty)
    }

    @Test("The renderer Whisky wrote is taken back once nothing asks for it")
    func recordedRendererIsTakenBack() async throws {
        let bottle = try makeBottle()
        try await syncLauncher(bottle, renderer: "gl")

        let document = try await syncLauncher(bottle, renderer: nil)

        #expect(section(direct3DKey, in: document) == [#""renderer"=-"#])
        #expect(registry.values(direct3DKey)["renderer"] == nil)
        #expect(recordedRenderer(bottle) == nil)
    }

    @Test("A renderer Whisky wrote and the user deleted is forgotten, with nothing removed")
    func deletedRendererIsForgotten() async throws {
        let bottle = try makeBottle()
        try await syncLauncher(bottle, renderer: "gl")
        registry.apply("[-\(direct3DKey)]")

        let document = try await syncLauncher(bottle, renderer: nil)

        #expect(!document.contains("Direct3D"))
        #expect(recordedRenderer(bottle) == nil)
    }

    @Test("A renderer Whisky wrote and the user deleted is written again while a launch wants it")
    func deletedRendererIsRewrittenWhileWanted() async throws {
        let bottle = try makeBottle()
        try await syncLauncher(bottle, renderer: "gl")
        registry.apply("[-\(direct3DKey)]")

        let document = try await syncLauncher(bottle, renderer: "gl")

        #expect(section(direct3DKey, in: document) == [#""renderer"="gl""#])
        #expect(recordedRenderer(bottle) == "gl")
    }

    @Test("A renderer the user changed after Whisky wrote it stays, and is no longer Whisky's")
    func rendererChangedByTheUserStays() async throws {
        let bottle = try makeBottle()
        try await syncLauncher(bottle, renderer: "gl")
        registry.set(direct3DKey, ["renderer": "vulkan"])

        let takeBack = try await syncLauncher(bottle, renderer: nil)
        let rewrite = try await syncLauncher(bottle, renderer: "gl")

        #expect(!takeBack.contains("renderer"))
        #expect(!rewrite.contains("renderer"))
        #expect(registry.values(direct3DKey) == ["renderer": "vulkan"])
        #expect(recordedRenderer(bottle) == nil)
    }

    @Test("A renderer the user set is never written over, recorded, or removed", arguments: ["vulkan", "gl"])
    func usersRendererIsLeftAlone(_ users: String) async throws {
        let bottle = try makeBottle()
        registry.set(direct3DKey, ["renderer": users])

        let write = try await syncLauncher(bottle, renderer: "gl")
        #expect(section(direct3DKey, in: write).isEmpty)
        #expect(recordedRenderer(bottle) == nil)

        let takeBack = try await syncLauncher(bottle, renderer: nil)
        #expect(section(direct3DKey, in: takeBack).isEmpty)
        #expect(registry.values(direct3DKey) == ["renderer": users])
    }

    @Test("With no renderer recorded or set and none asked for, the Direct3D key is not created")
    func nothingToDoCreatesNoKey() async throws {
        let bottle = try makeBottle()

        let document = try await syncLauncher(bottle, renderer: nil)

        #expect(!document.contains("Direct3D"))
        #expect(registry.keys[direct3DKey.lowercased()] == nil)
    }

    @Test("A launch reads the renderer from the bottle's user.reg, whatever the name's case")
    func rendererIsReadFromUserReg() async throws {
        let bottle = try makeBottle()
        let userReg = #"""
        WINE REGISTRY Version 2
        ;; All keys relative to \\User\\S-1-5-21-0-0-0-1000

        [Software\\Wine\\AppDefaults\\Launcher.exe\\Direct3D] 1731628800
        #time=1db36a0c0000000
        "Renderer"="vulkan"

        """#
        try userReg.write(to: bottle.url.appending(path: "user.reg"), atomically: true, encoding: .utf8)
        var documents: [String] = []

        try await Wine.syncDLLOverrides(
            bottle: bottle, scopes: [(scope: .direct3D("Launcher.exe"), overrides: "renderer=gl")],
            importer: { document, _ in documents.append(document) }
        )

        #expect(Wine.registryValue(bottleURL: bottle.url, key: direct3DKey, name: "renderer") == "vulkan")
        #expect(documents.count == 1)
        #expect(documents.first?.contains("renderer") == false)
        #expect(recordedRenderer(bottle) == nil)
    }

    @Test("The swapped layout asks for the renderer, and a degraded one after it takes Whisky's back")
    func swappedThenDegradedReleasesTheRenderer() async throws {
        let bottle = try makeBottle()
        let layouts: [(RockstarD3DLayout, [String: String])] = [
            (.swapped(source: URL(filePath: "/originals/d3d11.dll")), ["renderer": "gl"]),
            (.degraded(.disabledByUser), [:])
        ]
        for (layout, expected) in layouts {
            var scopes = Wine.DLLOverrideScopes(bottle: "")
            Wine.addRockstarChainScopes(to: &scopes, layout: { layout }, launcherSet: { _ in "d3d11=n,b" })
            try await Wine.syncDLLOverrides(
                bottle: bottle, scopes: scopes.entries,
                importer: { document, _ in self.registry.apply(document) },
                currentValue: { key, name in self.registry.values(key)[name.lowercased()] }
            )
            #expect(registry.values(direct3DKey) == expected, "\(layout.summary)")
        }
        #expect(recordedRenderer(bottle) == nil)
    }

    @Test("Only the scope's own value names are read from its string", arguments: [
        "renderer=gl;d3d11=n,b", "renderer=gl;csmt=0"
    ])
    func onlyOwnedNamesAreWritten(_ values: String) {
        let edits = Wine.ownedValueEdits(
            for: [(scope: .direct3D("Launcher.exe"), overrides: values)],
            record: DLLOverrideRecord(), current: { _, _ in nil }
        )

        #expect(edits == [
            OwnedRegistryValueEdit(key: direct3DKey, name: "renderer", line: .set("gl"), owned: "gl")
        ])
    }
}
