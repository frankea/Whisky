//
//  DLLOverridePreservationTests.swift
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

/// A prefix registry that applies the `.reg` documents the DLL override sync
/// writes the way `reg import` does: section headers, `[-Key]`, and the
/// `"name"="value"` and `"name"=-` value lines.
@MainActor
final class SimulatedRegistry {
    /// Lowercased key to lowercased value name to data.
    private(set) var keys: [String: [String: String]] = [:]

    var importer: Wine.RegistryImporter {
        { document, _ in self.apply(document) }
    }

    func set(_ key: String, _ values: [String: String]) {
        keys[key.lowercased(), default: [:]].merge(values) { _, new in new }
    }

    func values(_ key: String) -> [String: String] {
        keys[key.lowercased()] ?? [:]
    }

    func apply(_ document: String) {
        var current: String?
        for line in document.components(separatedBy: "\r\n") {
            if line.hasPrefix("[-"), line.hasSuffix("]") {
                keys[String(line.dropFirst(2).dropLast()).lowercased()] = nil
                current = nil
            } else if line.hasPrefix("["), line.hasSuffix("]") {
                let key = String(line.dropFirst().dropLast()).lowercased()
                keys[key] = keys[key] ?? [:]
                current = key
            } else if let key = current, line.hasPrefix("\"") {
                let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                let name = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: "\"")).lowercased()
                if parts[1] == "-" {
                    keys[key]?[name] = nil
                } else {
                    keys[key]?[name] = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                }
            }
        }
    }
}

/// What a launch leaves in the prefix registry's DLL override keys, now that
/// it removes only the values it could have written (adurham/Whisky).
@Suite("DLL overrides other tools wrote")
@MainActor
final class DLLOverridePreservationTests {
    private let tempRoot: URL
    private let registry = SimulatedRegistry()
    private let bottleKey = Wine.DLLOverrideScope.bottle.registryKey
    private let gameKey = Wine.DLLOverrideScope.program("Game.exe").registryKey

    init() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "dll_override_preservation_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func makeBottle(_ backend: GraphicsBackend) throws -> (bottle: Bottle, game: URL) {
        let bottleURL = tempRoot.appending(path: "Bottle")
        let game = bottleURL.appending(path: "drive_c/Games/Game/Game.exe")
        try FileManager.default.createDirectory(
            at: game.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("MZ".utf8).write(to: game)
        let bottle = Bottle(bottleUrl: bottleURL)
        bottle.settings.graphicsBackend = backend
        return (bottle, game)
    }

    /// Runs a launch's DLL override sync against the simulated registry.
    private func launch(_ url: URL, in bottle: Bottle) async throws {
        var environment = Wine.constructWineEnvironment(
            for: bottle, recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: false
        )
        try await Wine.applyDLLOverrides(
            for: url, bottle: bottle, wineEnvironment: &environment, applyToDescendants: false,
            recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: false,
            writer: { bottle, scopes in
                try await Wine.syncDLLOverrides(bottle: bottle, scopes: scopes, importer: self.registry.importer)
            }
        )
    }

    @Test("A winetricks override survives a D3DMetal launch and a switch back to DXVK")
    func winetricksOverrideSurvivesBackendSwitch() async throws {
        let (bottle, game) = try makeBottle(.dxvk)
        try await launch(game, in: bottle)
        #expect(registry.values(bottleKey)["dxgi"] == "n,b")

        // What `winetricks d3dx9 xact` and winecfg leave behind.
        registry.set(bottleKey, ["d3dx9_43": "native", "xaudio2_7": "native,builtin"])
        registry.set(gameKey, ["dinput8": "native"])

        bottle.settings.graphicsBackend = .d3dMetal
        try await launch(game, in: bottle)
        // D3DMetal writes nothing at bottle level: DXVK's set goes, the rest stays.
        #expect(registry.values(bottleKey) == ["d3dx9_43": "native", "xaudio2_7": "native,builtin"])
        #expect(registry.values(gameKey) == ["dinput8": "native"])

        bottle.settings.graphicsBackend = .dxvk
        try await launch(game, in: bottle)
        let bottleValues = registry.values(bottleKey)
        #expect(bottleValues["d3dx9_43"] == "native")
        #expect(bottleValues["xaudio2_7"] == "native,builtin")
        for dll in ["dxgi", "d3d9", "d3d10core", "d3d11"] {
            #expect(bottleValues[dll] == "n,b", "\(dll)")
        }
        #expect(registry.values(gameKey)["dinput8"] == "native")
    }

    @Test("Winetricks' starred backend overrides go on a D3DMetal launch, its others stay")
    func starredBackendOverridesGo() async throws {
        let (bottle, game) = try makeBottle(.d3dMetal)
        // What `winetricks dxvk d3dx9` writes: every name with a leading `*`.
        registry.set(bottleKey, [
            "*d3d11": "native", "*dxgi": "native", "*d3d12": "native", "*d3dx9_43": "native"
        ])
        registry.set(gameKey, ["*d3d9": "native", "*xaudio2_7": "native"])

        try await launch(game, in: bottle)
        #expect(registry.values(bottleKey) == ["*d3dx9_43": "native"])
        #expect(registry.values(gameKey) == ["*xaudio2_7": "native"])
    }

    @Test("A deleted custom override is taken back, and only that one")
    func removedCustomOverrideIsTakenBack() async throws {
        let (bottle, game) = try makeBottle(.d3dMetal)
        registry.set(bottleKey, ["d3dx9_43": "native"])
        bottle.settings.dllOverrides = [DLLOverrideEntry(dllName: "version", mode: .nativeThenBuiltin)]
        try await launch(game, in: bottle)
        #expect(registry.values(bottleKey) == ["d3dx9_43": "native", "version": "n,b"])

        bottle.settings.dllOverrides = []
        try await launch(game, in: bottle)
        #expect(registry.values(bottleKey) == ["d3dx9_43": "native"])
    }

    @Test("Launching one program does not forget what another's launch wrote")
    func recordKeepsOtherProgramsNames() {
        let otherKey = Wine.DLLOverrideScope.program("Other.exe").registryKey
        var record = DLLOverrideRecord().updated(with: [(key: otherKey, overrides: ["version": "n,b"])])
        record = record.updated(with: [(key: gameKey, overrides: ["dinput8": "n", "dxgi": "n,b"])])

        #expect(record.names(for: otherKey) == ["version"])
        // Managed names are always removable, so they are not recorded.
        #expect(record.names(for: gameKey) == ["dinput8"])

        let document = Wine.registryDocument(for: [(key: otherKey, overrides: [:])], record: record)
        #expect(document.contains(#""version"=-"#))
        #expect(!document.contains("dinput8"))
    }

    @Test("A launch that finishes during another's import keeps its recorded names")
    func overlappingLaunchesKeepEachOthersNames() async throws {
        let (bottle, _) = try makeBottle(.d3dMetal)
        let otherKey = Wine.DLLOverrideScope.program("Other.exe").registryKey
        // Launch B saves its names while launch A's import is still running.
        let importer: Wine.RegistryImporter = { document, bottle in
            self.registry.apply(document)
            try DLLOverrideRecord.load(from: bottle.url)
                .updated(with: [(key: otherKey, overrides: ["version": "n,b"])])
                .save(to: bottle.url)
        }
        try await Wine.syncDLLOverrides(
            bottle: bottle, scopes: [(scope: .program("Game.exe"), overrides: "dinput8=n")], importer: importer
        )

        let record = DLLOverrideRecord.load(from: bottle.url)
        #expect(record.names(for: gameKey) == ["dinput8"])
        #expect(record.names(for: otherKey) == ["version"])
    }

    @Test("A launch that starts during another's import takes back the name that import wrote")
    func overlappingLaunchesOfOneProgramTakeBackStaleNames() async throws {
        let (bottle, _) = try makeBottle(.d3dMetal)
        var releaseFirst: CheckedContinuation<Void, Never>?
        var held = false
        let importer: Wine.RegistryImporter = { document, _ in
            if !held {
                held = true
                await withCheckedContinuation { releaseFirst = $0 }
            }
            self.registry.apply(document)
        }
        func sync(_ overrides: String) async throws {
            try await Wine.syncDLLOverrides(
                bottle: bottle, scopes: [(scope: .program("Game.exe"), overrides: overrides)], importer: importer
            )
        }

        // The first launch's import is still running when the user swaps the
        // custom override and launches again.
        let first = Task { try await sync("aaa=n") }
        while releaseFirst == nil {
            await Task.yield()
        }
        let second = Task { try await sync("bbb=n") }
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        releaseFirst?.resume()
        try await first.value
        try await second.value

        #expect(registry.values(gameKey) == ["bbb": "n"])
        #expect(DLLOverrideRecord.load(from: bottle.url).names(for: gameKey) == ["bbb"])
    }

    @Test("A program name that would break the key header gets no entry")
    func unsafeExecutableNamesAreSkipped() {
        #expect(Wine.DLLOverrideScopes.isKeySegment("Game [v1.2].exe"))
        #expect(!Wine.DLLOverrideScopes.isKeySegment("New\nline.exe"))
        #expect(!Wine.DLLOverrideScopes.isKeySegment("Sub\\Key.exe"))
        #expect(!Wine.DLLOverrideScopes.isKeySegment(""))
        #expect(!Wine.DLLOverrideScopes.isKeySegment("Tab\tName.exe"))
        #expect(!Wine.DLLOverrideScopes.isKeySegment("C1\u{85}Line.exe"))
        // Format characters are not control codes: a ZWNJ is part of Persian words.
        let persian = "\u{0645}\u{06CC}\u{200C}\u{062E}\u{0648}\u{0627}\u{0647}\u{0645}.exe"
        #expect(Wine.DLLOverrideScopes.isKeySegment(persian))
        #expect(Wine.DLLOverrideScopes.isKeySegment("Game\u{200D}.exe"))

        var scopes = Wine.DLLOverrideScopes(bottle: "dxgi=n,b")
        scopes.add(["a\n[HKEY_CURRENT_USER\\Software\\Injected]\n.exe", "Game.exe"], "d3d11=n,b")
        let document = Wine.registryDocument(
            for: scopes.entries.map { (key: $0.scope.registryKey, overrides: Wine.parseDLLOverrides($0.overrides)) }
        )
        #expect(scopes.entries.count == 2)
        #expect(!document.contains("Injected"))
        #expect(document.contains("AppDefaults\\Game.exe\\DllOverrides"))
    }

    @Test("A record saved before owned values existed still loads")
    func oldRecordWithoutValuesDecodes() throws {
        let (bottle, _) = try makeBottle(.d3dMetal)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>names</key>
            <dict>
                <key>\(gameKey.lowercased())</key>
                <array><string>dinput8</string></array>
            </dict>
        </dict>
        </plist>
        """
        try plist.write(to: DLLOverrideRecord.url(in: bottle.url), atomically: true, encoding: .utf8)

        let record = DLLOverrideRecord.load(from: bottle.url)

        #expect(record.names(for: gameKey) == ["dinput8"])
        #expect(record.values.isEmpty)
    }

    @Test("The record survives a save and load")
    func recordRoundTrips() throws {
        let (bottle, _) = try makeBottle(.d3dMetal)
        let direct3D = Wine.DLLOverrideScope.direct3D("Launcher.exe").registryKey
        let record = DLLOverrideRecord().updated(with: [(key: bottleKey, overrides: ["Version": "n,b"])])
            .updated(with: [OwnedRegistryValueEdit(key: direct3D, name: "renderer", line: .set("gl"), owned: "gl")])
        try record.save(to: bottle.url)
        #expect(DLLOverrideRecord.load(from: bottle.url) == record)
        #expect(DLLOverrideRecord.load(from: tempRoot.appending(path: "missing")) == DLLOverrideRecord())
    }
}
